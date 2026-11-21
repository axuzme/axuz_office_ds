#!/usr/bin/env bash
# axuz_ops/office/release.sh — empacota e publica o ONLYOFFICE Document Server (`office_ds`) compilado por nos.
#
# O QUE: lado MAQUINA DE BUILD do deploy do DS (ADR 2026-11-13-docs-online-editor, decisao 12.3; piso 23 exceção escopada).
#   Pega a saida do build (`.../out/linux_64/onlyoffice/documentserver`), REVERIFICA (check-no-blob + check-agpl-notices),
#   e gera em <out>/<tag>/: o tar.zst DETERMINISTICO (ordem, dono 0, mtime = data do commit da receita), `SHA256SUMS` de
#   cada arquivo, SBOM CycloneDX (`sbom.cdx.json`), `version.json` (SHAs exatos de cada repo do blobs.lock + commit da
#   receita), `NOTICE-AXUZ.txt`, `SOURCE.md` (AGPL secao 13) e `release.json` (tag, arquivo, sha256, tamanho). Ao final
#   imprime as linhas a colar no modulo do ops (tag + sha256 + source_sha): o hash vai pro GIT ANTES de a VPS poder instalar.
# DEFAULT = --dry-run: monta tudo localmente e NAO publica nem cria nada no GitHub. `--publish` e explicito.
# PORTOES (fail-closed, valem para dry-run e publish): (1) a receita (`office/` e `security/office/`) esta limpa e o HEAD
#   esta PUSHADO (build "so de commit pushado", ADR 12.3b); (2) artefato presente e check-no-blob/check-agpl-notices ok;
#   (3) so no --publish: `blobs.lock` sem linha `[~]` (item on-hold = rota de fonte incompleta, ex.: os 5 .wasm do sdkjs)
#   e `gh` autenticado. Falhou um portao = rc 1/3 e nada e criado. Sem `--skip-*`: nao ha como afrouxar.
# PUBLICACAO: release do repo espelho `axuzme/axuz_office_ds` (PRIVADO por ora). Se o repo nao existe, `--publish` (ou
#   `--init-mirror`) o cria privado e grava README/SOURCE.md. Tag imutavel: tag ja existente com sha256 diferente = erro.
# ONDE: maquina de build dev/hml, depois de `run-build.sh ... verify` e `smoke/run.sh`. NUNCA roda na VPS.
# USO:   bash axuz_ops/office/release.sh [--artifact DIR] [--out DIR] [--repo OWNER/NOME] [--tag TAG]
#                                        [--dry-run | --publish] [--init-mirror]
# AMBIENTE: AXUZ_OFFICE_WS (workspace de build, default <repo>/.build/office); RELEASE_ZSTD_LEVEL (default 19);
#   RELEASE_MIRROR_URL (so testes: remoto git do espelho).
# SAIDA: 0 ok · 1 portao reprovou · 2 uso · 3 falha de publicacao/gh.
set -euo pipefail

OFFICE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS="$(cd "$OFFICE/.." && pwd)"
WS="${AXUZ_OFFICE_WS:-$(cd "$OPS/.." && pwd)/.build/office}"
ART="$WS/work/build_tools/out/linux_64/onlyoffice/documentserver"
OUT="$WS/release"
REPO="axuzme/axuz_office_ds"
TAG=""; MODE=dry; INIT_ONLY=0
LEVEL="${RELEASE_ZSTD_LEVEL:-19}"

log() { printf '\033[0;36m[office-release]\033[0m %s\n' "$*"; }
die() { printf '\033[0;31m[office-release x]\033[0m %s\n' "$2" >&2; exit "$1"; }

while (($#)); do
  case "$1" in
    --artifact) ART="${2:?--artifact precisa de DIR}"; shift 2 ;;
    --out) OUT="${2:?--out precisa de DIR}"; shift 2 ;;
    --repo) REPO="${2:?--repo precisa de OWNER/NOME}"; shift 2 ;;
    --tag) TAG="${2:?--tag precisa de valor}"; shift 2 ;;
    --dry-run) MODE=dry; shift ;;
    --publish) MODE=publish; shift ;;
    --init-mirror) INIT_ONLY=1; shift ;;
    -h|--help) sed -n '2,/^# SAIDA/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die 2 "argumento desconhecido: $1" ;;
  esac
done
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 2 "--repo invalido: $REPO"
[[ "$LEVEL" =~ ^([1-9]|1[0-9]|2[0-2])$ ]] || die 2 "RELEASE_ZSTD_LEVEL invalido: $LEVEL"

# mirror_files <dir> — escreve README.md e SOURCE.md do repo espelho. Onde: init_mirror e o empacotamento.
mirror_files() {
  local d="$1" commit="${2:-}"
  cat >"$d/SOURCE.md" <<EOF
# Fonte correspondente — Editor de documentos (ONLYOFFICE Docs Community Edition, modificado)

Este repositorio acompanha os releases do Document Server que o Axuz opera (\`office_ds\`). O Document Server e o
ONLYOFFICE Docs Community Edition (Ascensio System SIA), licenciado AGPL-3.0 com os termos adicionais do projeto.
O artefato e **modificado** pelo Axuz (aviso em \`NOTICE-AXUZ.txt\`, dentro de cada release).

Como obter o fonte correspondente (AGPL-3.0, secao 13) de um release \`ds-<versao>-<sha8>\`:

1. \`version.json\` (no release e no tar) lista cada repositorio ONLYOFFICE usado com o commit EXATO, mais o commit da
   receita de build (\`recipe_commit\`).
2. A receita (scripts de build, \`blobs.lock\`, \`patches/\`) vive em \`office/\` do repositorio \`axuzme/axuz_ops\`, no
   commit \`recipe_commit\`, e em copia versionada em \`recipe/\` do repositorio \`axuzme/axuz_office_ds\`. Os patches (cada um com
   aviso "Modified by Axuz") estao em \`office/patches/\` (ops) e \`recipe/office/patches/\` (este repositorio).
3. O SBOM (\`sbom.cdx.json\`) e o \`SHA256SUMS\` do release provam o conteudo arquivo a arquivo.

${commit:+Ultima receita registrada neste espelho: \`$commit\`.}

Este repositorio e PRIVADO por ora. Antes de o editor ser oferecido a usuarios externos o fonte correspondente tem de
estar acessivel a eles (tornar este repositorio e o \`office/\` publicos, ou oferecer o fonte por escrito).
EOF
  cat >"$d/README.md" <<EOF
# axuz_office_ds

Espelho de releases do Document Server do Axuz (ONLYOFFICE Docs CE compilado do fonte, sha256 fixado no ops).
Fonte correspondente e patches: ver SOURCE.md. Nada aqui e instalado a mao: o \`axuz_ops\` baixa por tag e verifica o sha256.
EOF
}

# init_mirror — cria o repo espelho (privado) se faltar e grava SOURCE.md/README. Idempotente.
# Onde: --publish e --init-mirror. Efeitos: gh repo create; push de 2 arquivos de texto.
init_mirror() {
  command -v gh >/dev/null || die 3 "gh ausente"
  gh auth status >/dev/null 2>&1 || die 3 "gh nao autenticado"
  if gh repo view "$REPO" >/dev/null 2>&1; then log "repo espelho $REPO ja existe"; else
    log "criando $REPO (privado)"
    gh repo create "$REPO" --private --description "Releases do ONLYOFFICE Document Server compilado pelo Axuz (fonte correspondente em SOURCE.md)" >/dev/null \
      || die 3 "gh repo create falhou"
  fi
  local t; t="$(mktemp -d)"; trap 'rm -rf "$t"' RETURN
  local url="${RELEASE_MIRROR_URL:-git@github.com:$REPO.git}"   # RELEASE_MIRROR_URL: so os testes (repo bare local)
  git clone -q "$url" "$t/m" 2>/dev/null || { git init -q -b main "$t/m"; git -C "$t/m" remote add origin "$url"; }
  # espelho ja populado com SOURCE.md proprio (recipe/, pins, patches): nunca sobrescreve
  if [[ -f "$t/m/SOURCE.md" ]]; then log "espelho ja tem SOURCE.md proprio: preservado"; return 0; fi
  mirror_files "$t/m" "$(git -C "$OPS" rev-parse HEAD)"
  git -C "$t/m" add SOURCE.md README.md
  if git -C "$t/m" diff --cached --quiet; then log "SOURCE.md/README ja atuais"; else
    git -C "$t/m" -c user.name="axuz-ops" -c user.email="ops@axuz.invalid" commit -q -m "docs: SOURCE.md e README do espelho" \
      || die 3 "commit do espelho falhou"
    git -C "$t/m" push -q origin HEAD:main || die 3 "push do espelho falhou"
  fi
}
if [[ "$INIT_ONLY" = 1 ]]; then init_mirror; exit 0; fi

# --- portao 1: receita limpa e pushada ---
RECIPE="$(git -C "$OPS" rev-parse HEAD)"
dirty="$(git -C "$OPS" status --porcelain -- office security/office | wc -l)"
[[ "$dirty" = 0 ]] || die 1 "receita suja ($dirty arquivo(s) em office/ ou security/office/): so se publica de commit pushado"
upstream="$(git -C "$OPS" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
[[ -n "$upstream" ]] || die 1 "branch sem upstream: o HEAD precisa estar pushado"
[[ "$(git -C "$OPS" rev-parse "$upstream")" = "$RECIPE" ]] || git -C "$OPS" merge-base --is-ancestor "$RECIPE" "$upstream" \
  || die 1 "HEAD $RECIPE nao esta em $upstream (push pendente)"
# --- portao 2: artefato verificado ---
[[ -d "$ART/server" && -d "$ART/web-apps" ]] || die 1 "artefato ausente ou incompleto: $ART (rode run-build.sh server verify)"
bash "$OPS/security/office/check-no-blob.sh" --root "$OFFICE" --artifact "$ART" --built-tree "$WS/work" --built-ws "$WS" >/dev/null || die 1 "check-no-blob reprovou o artefato"
bash "$OPS/security/office/check-agpl-notices.sh" --root "$OFFICE" --artifact "$ART" >/dev/null || die 1 "check-agpl-notices reprovou o artefato"
pending="$(awk -F'\t' 'NR>1 && $8=="[~]"{print $1}' "$OFFICE/blobs.lock" | tr '\n' ' ')"
if [[ "$MODE" = publish && -n "$pending" ]]; then die 1 "blobs.lock com item on-hold [~]: ${pending}— rota de fonte incompleta; nao publica"; fi
[[ -z "$pending" ]] || log "AVISO: blobs.lock com [~] (${pending}): dry-run permitido, publish recusado"

# --- versao e tag ---
base="$(awk -F'\t' '$1=="repo-build_tools"{print $7}' "$OFFICE/blobs.lock" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d v)"
[[ -n "$base" ]] || die 1 "versao base nao encontrada em blobs.lock (repo-build_tools)"
[[ -n "$TAG" ]] || TAG="ds-$base-${RECIPE:0:8}"
[[ "$TAG" =~ ^(ds-|v)[0-9][0-9A-Za-z._-]{0,40}$ ]] || die 2 "tag invalida: $TAG (ds-<versao>-<sha8> ou v<versao>-axuz.<n>)"
EPOCH="$(git -C "$OPS" show -s --format=%ct "$RECIPE")"
D="$OUT/$TAG"; rm -rf "$D"; mkdir -p "$D"
FILE="axuz-office-ds-$TAG-linux-amd64.tar.zst"
log "tag $TAG, receita ${RECIPE:0:12}, mtime $EPOCH"

# --- version.json (fontes exatos) + SHA256SUMS + SBOM ---
python3 -I - "$OFFICE/blobs.lock" "$RECIPE" "$TAG" "$base" "$EPOCH" "$D/version.json" "$D/sbom.cdx.json" <<'PY'
import csv, json, sys, datetime
lock, recipe, tag, base, epoch, vout, sout = sys.argv[1:8]
rows = list(csv.DictReader(open(lock, newline=''), delimiter='\t'))
ts = datetime.datetime.fromtimestamp(int(epoch), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
src = [{"id": r["id"], "origem": r["origem"], "pin": r["pin"], "classe": r["classe"], "licenca": r["licenca"], "status": r["status"]} for r in rows]
json.dump({"produto": "ONLYOFFICE Docs Community Edition (modificado pelo Axuz)", "tag": tag, "base_version": base,
           "recipe_repo": "axuzme/axuz_ops", "recipe_path": "office/", "recipe_commit": recipe, "built_from_commit_time": ts,
           "fontes": src}, open(vout, "w"), indent=1, sort_keys=True)
comps = []
for r in rows:
    pin = r["pin"]; c = {"type": "library" if r["classe"] in ("git", "tarball", "git-file") else "application", "name": r["id"],
         "version": pin.split(":", 1)[-1][:12], "licenses": [{"license": {"name": r["licenca"]}}],
         "externalReferences": [{"type": "vcs" if r["classe"].startswith("git") else "distribution", "url": r["origem"]}]}
    if pin.startswith("sha256:"): c["hashes"] = [{"alg": "SHA-256", "content": pin[7:]}]
    comps.append(c)
json.dump({"bomFormat": "CycloneDX", "specVersion": "1.5", "version": 1,
           "metadata": {"timestamp": ts, "component": {"type": "application", "name": "axuz-office-ds", "version": tag}},
           "components": comps}, open(sout, "w"), indent=1, sort_keys=True)
PY
mirror_files "$D" "$RECIPE"
cp "$OFFICE/NOTICE-AXUZ.txt" "$D/NOTICE-AXUZ.txt"

# --- staging deterministico: arvore do artefato + metadados, SHA256SUMS de cada arquivo ---
S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
cp -a "$ART" "$S/documentserver"
mkdir -p "$S/documentserver/AXUZ"
cp "$D/version.json" "$D/sbom.cdx.json" "$D/NOTICE-AXUZ.txt" "$D/SOURCE.md" "$S/documentserver/AXUZ/"
( cd "$S" && find documentserver -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum ) >"$D/SHA256SUMS"
cp "$D/SHA256SUMS" "$S/documentserver/AXUZ/SHA256SUMS"
( cd "$S" && tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner --format=gnu \
    -cf - documentserver | zstd -q -"$LEVEL" -T0 -o "$D/$FILE" )
SHA="$(sha256sum "$D/$FILE" | cut -d' ' -f1)"; SIZE="$(stat -c %s "$D/$FILE")"
printf '%s  %s\n' "$SHA" "$FILE" >"$D/$FILE.sha256"
printf '{"tag":"%s","file":"%s","sha256":"%s","size":%s,"source_sha":"%s","repo":"%s"}\n' "$TAG" "$FILE" "$SHA" "$SIZE" "$RECIPE" "$REPO" >"$D/release.json"
log "pacote: $D/$FILE ($SIZE bytes) sha256=$SHA"

cat <<EOF

== colar em modules/office-ds.yaml (artifact:) e COMMITAR+PUSHAR antes de instalar na VPS ==
    repo: $REPO
    tag: "$TAG"
    file: "$FILE"
    sha256: "$SHA"
    source_sha: "$RECIPE"
EOF

if [[ "$MODE" != publish ]]; then log "DRY-RUN: nada foi publicado (use --publish)"; exit 0; fi
init_mirror
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  remote_sha="$(gh release download "$TAG" --repo "$REPO" --pattern "$FILE.sha256" -O - 2>/dev/null | cut -d' ' -f1 || true)"
  [[ "$remote_sha" = "$SHA" ]] && { log "release $TAG ja publicado com o mesmo sha256: nada a fazer"; exit 0; }
  die 3 "tag $TAG ja existe com sha256 DIFERENTE (tags sao imutaveis): suba a receita e gere outra tag"
fi
gh release create "$TAG" --repo "$REPO" --title "Document Server $TAG" \
  --notes "Build de $RECIPE. sha256 $SHA. Fonte correspondente: SOURCE.md. Instalacao so pelo axuz_ops (sha256 fixado no modulo)." \
  "$D/$FILE" "$D/$FILE.sha256" "$D/SHA256SUMS" "$D/sbom.cdx.json" "$D/version.json" "$D/NOTICE-AXUZ.txt" "$D/SOURCE.md" "$D/release.json" \
  >/dev/null || die 3 "gh release create falhou"
log "publicado: https://github.com/$REPO/releases/tag/$TAG"
