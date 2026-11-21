#!/usr/bin/env bash
# axuz_ops/office/stages/60-verify.sh — gates finais sobre o artefato e a arvore de build.
#
# O QUE: check-no-blob.sh (--artifact: todo ELF/.wasm/.node do artefato esta na allowlist, tem hash no lock ou esta em built-from-source.tsv com origem na arvore (stage seal);
#   --verify-tree: HEAD dos repos == lock) e check-agpl-notices.sh (--artifact: NOTICE, LICENSE e cabecalhos upstream).
#   Grava o inventario de binarios (sha256) em /ws/logs/artifact-binaries.tsv e o conjunto de hosts de marketing que
#   sobraram em /ws/logs/marketing-restante.txt.
# ONDE: roda no container axuz-office-builder:snapshot (run-build.sh, stage verify). rc != 0 = nao promovivel.
set -euo pipefail
OUT=/work/build_tools/out/linux_64/onlyoffice/documentserver
[[ -d "$OUT" ]] || { echo "artefato ausente: $OUT" >&2; exit 2; }
mkdir -p /ws/logs
git config --global --add safe.directory '*'   # repos de /work pertencem a outro uid: sem isso o --verify-tree nao le o HEAD
rc=0
bash /security/check-no-blob.sh --root /recipe --artifact "$OUT" --verify-tree /work || rc=1
bash /security/check-agpl-notices.sh --root /recipe --artifact "$OUT" || rc=1
# inventario: ELF / wasm / .node com sha256
: > /ws/logs/artifact-binaries.tsv
while IFS= read -r f; do
  m="$(head -c4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  case "$m" in 7f454c46|0061736d) printf '%s\t%s\t%s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$m" "${f#"$OUT"/}" >> /ws/logs/artifact-binaries.tsv ;; esac
done < <(find "$OUT" -type f)
echo "binarios no artefato: $(wc -l < /ws/logs/artifact-binaries.tsv) (ELF/wasm)"
# marketing que sobrou (fora de cabecalhos de licenca)
grep -rhaoE 'https?://(www|helpcenter|api|support|community|git|bugzilla)\.onlyoffice\.com[^"<> )]*' "$OUT/web-apps/apps" "$OUT/sdkjs" "$OUT/server/DocService" 2>/dev/null \
  | sed -E 's#(https?://[^/]+).*#\1#' | sort | uniq -c | sort -rn > /ws/logs/marketing-restante.txt || true
echo "hosts de marketing remanescentes: $(wc -l < /ws/logs/marketing-restante.txt) (ver /ws/logs/marketing-restante.txt)"
exit "$rc"
