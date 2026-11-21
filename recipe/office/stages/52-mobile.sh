#!/usr/bin/env bash
# axuz_ops/office/stages/52-mobile.sh — build do editor mobile (word/cell/slide) a partir do src patchado do web-apps.
#
# O QUE: o artefato do stage server traz apps/*/mobile/dist PRE-COMPILADO do upstream (sem o patch de edicao). Aqui
#   rodamos `npm ci` (lockfile estrito, sem scripts) no vendor/framework7-react se faltar node_modules, depois
#   `npm run deploy-{word,cell,slide}` com a nossa node, e copiamos dist/ e css/ gerados para o artefato, substituindo o upstream.
#   Confere o marcador axuz-mobile-edit-v1 (patch web-apps-0004) em cada bundle; sem ele, falha.
# ONDE: roda no container axuz-office-builder:snapshot (run-build.sh, stage mobile), entre server e seal.
# EFEITO: OUT/web-apps/apps/{documenteditor,spreadsheeteditor,presentationeditor}/mobile/{dist,css} sao os do nosso build.
set -euo pipefail
source /recipe/lib/lock.sh
T=/ws/toolchain
W=/work/web-apps
OUT=/work/build_tools/out/linux_64/onlyoffice/documentserver
MARK='axuz-mobile-edit-v1'
[[ -f /work/prepare.ok ]] || lock_die "rode o stage prepare antes"
[[ -x "$T/node/bin/node" ]] || lock_die "node proprio ausente (stage node)"
[[ -d "$OUT/web-apps/apps" ]] || lock_die "artefato ausente (rode o stage server antes)"
grep -qF "$MARK" "$W/apps/documenteditor/mobile/src/lib/patch.jsx" || lock_die "patch web-apps-0004 nao aplicado no src (rode prepare)"
export PATH="$T/node/bin:$PATH" HOME=/tmp npm_config_cache=/ws/npm-cache-mobile
# versao de producto, como o build_tools a le (check_build_version: arquivo `version`, BUILD_NUMBER=0). Sem isso o webpack
# cai no default '6.2.0.123d' e o bundle vira "develop": busca o SDK em sdkjs/develop/... (404) e o editor nunca abre.
PRODUCT_VERSION="$(tr -d '\r\n' < /work/build_tools/version)"; BUILD_NUMBER="${BUILD_NUMBER:-0}"
[[ "$PRODUCT_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]] || lock_die "versao do build_tools invalida: '$PRODUCT_VERSION'"
export PRODUCT_VERSION BUILD_NUMBER

cd "$W/vendor/framework7-react"
if [[ ! -d node_modules ]]; then
  npm ci --include=dev --ignore-scripts --no-audit --no-fund
fi
for pair in word:documenteditor cell:spreadsheeteditor slide:presentationeditor; do
  ed="${pair%%:*}"; app="${pair##*:}"
  echo "== mobile $ed"
  npm run "deploy-$ed" 2>&1 | tail -4
  src="$W/apps/$app/mobile"; dst="$OUT/web-apps/apps/$app/mobile"
  grep -rqF "$MARK" "$src/dist" || lock_die "$app: bundle gerado sem o marcador $MARK"
  ! grep -rqF '6.2.0.123d' "$src/dist/js" || lock_die "$app: bundle com versao develop (PRODUCT_VERSION nao chegou ao webpack)"
  rm -rf "$dst/dist" "$dst/css"
  cp -a "$src/dist" "$dst/dist"
  cp -a "$src/css" "$dst/css"
  find "$dst/dist" -name '*.map' -delete
  echo "mobile $app ok: $(du -sh "$dst/dist" | cut -f1)"
done
chown -R 1000:1000 "$OUT/web-apps" 2>/dev/null || true
echo "mobile ok"
