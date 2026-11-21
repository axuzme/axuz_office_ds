#!/usr/bin/env bash
# axuz_ops/office/smoke/run.sh — smoke funcional do Document Server recem-compilado (O1.a-pre).
#
# O QUE: monta o artefato num rootfs de teste, sobe Postgres/Redis/RabbitMQ + DS + app de exemplo numa rede docker
#   privada SEM saida (DNS apontando para TEST-NET e iptables DENTRO do container do DS: so loopback e RFC1918, resto
#   REJECT com contador) e roda os drivers e2e do gate O1.0 (chromium headless via CDP): abrir, editar, salvar e
#   co-editar docx/xlsx/pptx/odt, e a edicao mobile (docx). Ao fim le o contador da regra REJECT (precisa ser 0) e o
#   log do navegador (nenhuma requisicao externa originada do DS).
# ONDE: depois do stage `verify` de run-build.sh. Roda no host (precisa de docker, chromium e node >= 22).
# USO:  bash axuz_ops/office/smoke/run.sh [formatos]     (default docx,xlsx,pptx,odt)
# SAIDA: <ws>/smoke-out/ (shots, log, egress.txt, resultado.md). rc 0 = tudo passou e egress == 0.
# DISCO: aborta se / ficar < 10G livres. Higiene: derruba containers e a rede de teste ao fim (KEEP=1 mantem).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WS="${AXUZ_OFFICE_WS:-$REPO/.build/office}"
T="$WS/ds-test"
OUTD="$WS/smoke-out"
FORMATS="${1:-docx,xlsx,pptx,odt}"
ART="$WS/work/build_tools/out/linux_64/onlyoffice/documentserver"
N=axuz-office-net
LIM="$(cd "$HERE/../.." && pwd)/scripts/limitado.sh"

disco_ok() { local av; av=$(( $(stat -f -c '%a * %S' /) / 1073741824 )); (( av >= 10 )) || { echo "DISCO_BAIXO ${av}G" >&2; exit 4; }; }
down() {
  [[ "${KEEP:-0}" == 1 ]] && return 0
  docker rm -f axuz-office-ds axuz-office-example axuz-office-example2 axuz-office-pg axuz-office-redis axuz-office-rabbit >/dev/null 2>&1 || true
  docker network rm "$N" >/dev/null 2>&1 || true
  pgrep -x chromium | xargs -r kill 2>/dev/null || true
}
trap down EXIT
disco_ok
[[ -d "$ART" ]] || { echo "artefato ausente: $ART (rode run-build.sh server verify)" >&2; exit 2; }
mkdir -p "$OUTD" "$T"

# ---- 1) rootfs de teste a partir do artefato (nada do artefato e alterado: copia) ----
RF="$T/rootfs"
rm -rf "$RF" "$T/data"
mkdir -p "$RF/var/www/onlyoffice" "$RF/etc/onlyoffice" "$T/data/ds-lib" "$T/data/ds-log" "$T/data/example-files/files"
rsync -a "$ART/" "$RF/var/www/onlyoffice/documentserver/"
mkdir -p "$RF/etc/onlyoffice/documentserver"
cp -a "$ART/server/Common/config/." "$RF/etc/onlyoffice/documentserver/"
cp "$HERE/ds-local.json" "$RF/etc/onlyoffice/documentserver/local.json"
docker build -q -f "$HERE/Dockerfile.test" -t axuz-office-test:ds "$HERE" >/dev/null

# ---- 2) fontes e temas (equivale ao documentserver-generate-allfonts.sh do pacote) ----
docker run --rm --memory 3g --cpus 2 -v "$RF/var/www/onlyoffice:/var/www/onlyoffice" -v "$HERE/gen-fonts.sh:/gen-fonts.sh:ro" \
  --user 1000:1000 axuz-office-test:ds bash /gen-fonts.sh | tail -2

# ---- 3) infra de teste ----
docker network inspect "$N" >/dev/null 2>&1 || docker network create "$N" >/dev/null
docker rm -f axuz-office-pg axuz-office-redis axuz-office-rabbit axuz-office-ds axuz-office-example axuz-office-example2 >/dev/null 2>&1 || true
docker run -d --name axuz-office-pg --network "$N" --memory 1g -e POSTGRES_USER=onlyoffice -e POSTGRES_PASSWORD=onlyoffice -e POSTGRES_DB=onlyoffice postgres:17-alpine >/dev/null
docker run -d --name axuz-office-redis --network "$N" --memory 256m redis:7-alpine >/dev/null
docker run -d --name axuz-office-rabbit --network "$N" --memory 1g rabbitmq:3.13-alpine >/dev/null
until docker exec axuz-office-pg pg_isready -U onlyoffice >/dev/null 2>&1; do sleep 1; done; sleep 3
docker exec -i axuz-office-pg psql -q -U onlyoffice -d onlyoffice < "$ART/server/schema/postgresql/createdb.sql"
until docker exec axuz-office-rabbit rabbitmq-diagnostics -q ping >/dev/null 2>&1; do sleep 2; done

# ok_url <url> — 0 se GET responde 2xx. Python (urllib) em vez de curl: o gate check-no-blob proibe curl na receita
# (so lib/lock.sh baixa coisa); aqui so ha loopback/rede do teste, mas a regra e uma so (igual a ops/smoke-ds-config.sh).
ok_url() {
  python3 -I -c 'import sys, urllib.request
try:
    urllib.request.urlopen(sys.argv[1], timeout=5).read(1); sys.exit(0)
except Exception:
    sys.exit(1)' "$1"
}

# ---- 4) DS com a trava de egress ----
docker run -d --name axuz-office-ds --network "$N" --dns 192.0.2.1 --cap-add NET_ADMIN --memory 6g --cpus 4 \
  -p 127.0.0.1:8000:8000 -p 127.0.0.1:3000:3000 \
  -v "$RF/var/www/onlyoffice:/var/www/onlyoffice" -v "$RF/etc/onlyoffice:/etc/onlyoffice:ro" \
  -v "$T/data/ds-lib:/var/lib/onlyoffice" -v "$T/data/ds-log:/var/log/onlyoffice" \
  -v "$HERE/ds-start.sh:/ds-start.sh:ro" -v "$HERE/run-services.sh:/run-services.sh:ro" axuz-office-test:ds bash /ds-start.sh >/dev/null
for i in $(seq 1 90); do ok_url http://127.0.0.1:8000/healthcheck && break; sleep 2; done
ok_url http://127.0.0.1:8000/healthcheck || { echo "DS nao subiu"; tail -30 "$T/data/ds-log/docservice.log" "$T/data/ds-log/converter.log" 2>/dev/null; exit 3; }

# ---- 5) app de exemplo (do fonte, npm ci estrito, node PROPRIO do artefato) ----
EXSRC="$WS/work/document-server-integration/web/documentserver-example/nodejs"
EXD="$T/example"; rm -rf "$EXD"; mkdir -p "$EXD"; cp -a "$EXSRC/." "$EXD/"
# o artefato so leva o binario node (sem npm, patch build_tools-0005): o npm ci usa a toolchain NOSSA (stage node), so no harness
docker run --rm --user 1000:1000 -e HOME=/tmp -v "$EXD:/app" -v "$WS/toolchain/node:/node:ro" -w /app axuz-office-test:ds \
  bash -c 'PATH=/node/bin:$PATH npm ci --ignore-scripts --no-audit --no-fund --omit=dev >/dev/null 2>&1 && echo example-deps-ok'
mkdir -p "$T/example-config"; cp -a "$EXD/config/." "$T/example-config/"
printf '{"server":{"port":3001,"siteUrl":"http://127.0.0.1:8000/","token":{"secret":"axuz-gate-test-secret"},"exampleUrl":"http://127.0.0.1:3001"}}\n' > "$T/example-config/local.json"
docker run -d --name axuz-office-example2 --network container:axuz-office-ds --memory 1g --user 1000:1000 -e NODE_ENV=production-linux -e NODE_CONFIG_DIR=/app/config \
  -v "$EXD:/app" -v "$T/example-config:/app/config:ro" -v "$T/data/example-files:/var/lib/onlyoffice/documentserver-example" \
  -v "$RF/var/www/onlyoffice/documentserver/node:/node:ro" -w /app axuz-office-test:ds /node/bin/node ./bin/www >/dev/null
DSIP="$(docker inspect -f '{{(index .NetworkSettings.Networks "'"$N"'").IPAddress}}' axuz-office-ds)"
for i in $(seq 1 30); do ok_url "http://$DSIP:3001/" && break; sleep 1; done

# ---- 6) drivers e2e (chromium headless, CDP) ----
export EX_URL="http://$DSIP:3001" SMOKE_OUT="$OUTD" DS_LOG="$T/data/ds-log/docservice.log"
GW="$(docker network inspect "$N" -f '{{(index .IPAM.Config 0).Gateway}}')"
export FILES_DIR="$T/data/example-files/files/__ffff_$GW"
export SAMPLE_ODT="$WS/work/core/OdfFile/Test/Test/ExampleFiles/44363.odt"
cd "$HERE/e2e"
rc=0
bash "$LIM" --perfil test --mem 3G --jobs 1 -- node run-desktop.mjs "$FORMATS" | tee "$OUTD/desktop.log" || rc=1
bash "$LIM" --perfil test --mem 3G --jobs 1 -- node mobile.mjs docx | tee "$OUTD/mobile.log" || rc=1

# ---- 7) egress e erros ----
docker exec axuz-office-ds iptables -nvL OUTPUT > "$OUTD/egress.txt" 2>&1 || true
REJ="$(awk '/REJECT/ {print $1; exit}' "$OUTD/egress.txt")"
echo "pacotes na regra REJECT (saida bloqueada): ${REJ:-?}" | tee -a "$OUTD/egress.txt"
BAD="$({ grep -cE 'ENOTFOUND|EAI_AGAIN|ETIMEDOUT' "$T/data/ds-log/docservice.log" "$T/data/ds-log/converter.log" 2>/dev/null || true; } | awk -F: '{s+=$2} END{print s+0}')"
echo "erros de resolucao/timeout externos nos logs: $BAD" | tee -a "$OUTD/egress.txt"
[[ "${REJ:-1}" == 0 ]] || rc=1
grep -q "ok\|true" "$OUTD/desktop.log" || rc=1
echo "smoke rc=$rc" | tee -a "$OUTD/egress.txt"
exit "$rc"
