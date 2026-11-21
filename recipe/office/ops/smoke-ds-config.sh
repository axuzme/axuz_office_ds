#!/usr/bin/env bash
# axuz_ops/office/ops/smoke-ds-config.sh — smoke LOCAL do Document Server COMPILADO com a config que o ops instala (sem Docker).
#
# O QUE: gera o config com lib/office_ds_config.py (a mesma que o install-office-ds.sh usa), sobe o launcher `docservice` do
#   artefato DIRETO (node proprio do artefato, user atual, estado em tmp), com os segredos por VARIAVEL DE AMBIENTE (como o unit
#   faz) e prova: (1) /healthcheck == true; (2) escuta SO em 127.0.0.1:<porta> (nenhum 0.0.0.0/::); (3) o estatico de browser
#   (/web-apps/apps/api/documents/api.js) sai 200; (4) a API de comando SEM JWT e recusada (JWT ligado, segredo nao e o placeholder);
#   (5) o processo e o conversor embutido sobem sem Postgres/Redis/RabbitMQ (nenhum deles existe neste teste = prova do runtime em memoria).
# NAO cobre: abrir/editar docx no navegador (isso e office/smoke/run.sh, gate O1.0, que usa o app de exemplo) nem o hardening do
#   systemd (so numa maquina com systemd real: `systemd-analyze security axuz-office_ds.service` + `office-ds install` em hml).
# ONDE: maquina de build, depois de `run-build.sh server verify`. NUNCA na VPS. Chame sob limite quando pesado:
#   bash axuz_ops/scripts/limitado.sh --perfil test --mem 3G -- bash axuz_ops/office/ops/smoke-ds-config.sh [DIR_DO_ARTEFATO]
# SAIDA: 0 = tudo passou; 1 = falha (log em <tmp>/docservice.log, mantido); 2 = artefato ausente.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS="$(cd "$HERE/../.." && pwd)"
REPO="$(cd "$OPS/.." && pwd)"
ART="${1:-${AXUZ_OFFICE_WS:-$REPO/.build/office}/work/build_tools/out/linux_64/onlyoffice/documentserver}"
PORT="${SMOKE_PORT:-26031}"
[[ -x "$ART/server/DocService/docservice" ]] || { echo "artefato ausente: $ART (rode run-build.sh server verify)" >&2; exit 2; }
T="$(mktemp -d)"; PID=""; rc=0
# cleanup — mata o docservice (grupo) e apaga o estado. Onde: trap EXIT.
cleanup() { [[ -z "$PID" ]] || kill -- "-$PID" 2>/dev/null || true; if [[ "$rc" = 0 ]]; then rm -rf "$T"; else echo "log mantido em $T" >&2; fi; }
trap cleanup EXIT
# http <GET|POST> <url> [corpo-json] — imprime "<codigo>\t<corpo>" (codigo 000 se sem resposta). Python (urllib) em vez de curl:
#   o gate check-no-blob proibe curl na receita (so lib/lock.sh baixa coisa); aqui so ha loopback, mas a regra e uma so.
http() {
  python3 -I -c '
import sys, urllib.request, urllib.error
m, u, b = sys.argv[1], sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else None)
r = urllib.request.Request(u, data=b.encode() if b else None, method=m, headers={"Content-Type": "application/json"})
try:
    x = urllib.request.urlopen(r, timeout=5); print("%d\t%s" % (x.status, x.read(2000).decode("utf-8", "replace")))
except urllib.error.HTTPError as e:
    print("%d\t%s" % (e.code, e.read(2000).decode("utf-8", "replace")))
except Exception:
    print("000\t")
' "$@"
}
chk() { # <nome> <comando...> — roda e conta
  local n="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  OK   $n"; else echo "  FAIL $n"; rc=1; fi
}
mkdir -p "$T/state/lib/documentserver/App_Data/cache/files" "$T/state/Data"
python3 -I "$OPS/lib/office_ds_config.py" --doc "$ART" --state "$T/state" --out "$T/cfg" --port "$PORT"
export NODE_ENV=production-linux NODE_CONFIG_DIR="$T/cfg" NODE_DISABLE_COLORS=1 LD_LIBRARY_PATH="$ART/server/FileConverter/bin"
OFFICE_DS_JWT_SECRET="$(openssl rand -hex 32)"; OFFICE_DS_CACHE_SECRET="$(openssl rand -hex 32)"; export OFFICE_DS_JWT_SECRET OFFICE_DS_CACHE_SECRET
setsid "$ART/server/DocService/docservice" >"$T/docservice.log" 2>&1 &
PID=$!
for _ in $(seq 1 90); do [[ "$(http GET "http://127.0.0.1:$PORT/healthcheck")" = $'200\ttrue' ]] && break; sleep 1; done
chk "healthcheck == true" test "$(http GET "http://127.0.0.1:$PORT/healthcheck")" = $'200\ttrue'
listen="$(ss -ltnH 2>/dev/null | awk -v p=":$PORT" '$4 ~ p"$" {print $4}' | sort -u | tr '\n' ' ')"
chk "escuta so em 127.0.0.1:$PORT (achei: ${listen:-nada})" test "$listen" = "127.0.0.1:$PORT "
code="$(http GET "http://127.0.0.1:$PORT/web-apps/apps/api/documents/api.js" | cut -f1)"
chk "api.js do editor 200 (estatico servido pelo proprio DS)" test "$code" = 200
body="$(http POST "http://127.0.0.1:$PORT/coauthoring/CommandService.ashx" '{"c":"version"}' | cut -f2)"
chk "CommandService sem JWT NAO responde sucesso (JWT ligado): ${body:0:60}" bash -c '! grep -q "\"error\":0" <<<"$1"' _ "$body"
chk "docservice vivo (conversor embutido, sem Postgres/Redis/RabbitMQ)" kill -0 "$PID"
chk "log sem tentativa de conectar a banco/broker externo" bash -c '! grep -qiE "ECONNREFUSED.*(5432|6379|5672)|amqp|redis.*error" "$1"' _ "$T/docservice.log"
[[ "$rc" = 0 ]] && echo "smoke-ds-config: OK" || echo "smoke-ds-config: FALHOU"
exit "$rc"
