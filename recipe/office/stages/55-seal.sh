#!/usr/bin/env bash
# axuz_ops/office/stages/55-seal.sh — poda os blobs npm nao usados e registra a origem dos binarios que NOS compilamos.
#
# O QUE: seal_prune + seal_manifest (lib/seal.sh) sobre o artefato do stage server.
# ONDE: roda no container axuz-office-builder:snapshot (run-build.sh, stage seal), entre server e verify. Idempotente.
# EFEITO: remove oracledb/bare-* prebuilds/win-ca roots.exe/winser nssm.exe/obj.target do sharp do artefato e grava
#   built-from-source.tsv nele. O gate (check-no-blob.sh) nao e afrouxado: binario fora do manifesto continua reprovando.
set -euo pipefail
source /recipe/lib/seal.sh
OUT=/work/build_tools/out/linux_64/onlyoffice/documentserver
[[ -d "$OUT" ]] || { echo "AXUZ-SEAL: artefato ausente: $OUT" >&2; exit 2; }
[[ -f /work/prepare.ok ]] || { echo "AXUZ-SEAL: /work/prepare.ok ausente (rode prepare)" >&2; exit 2; }
seal_prune "$OUT"
seal_manifest "$OUT" /work /ws
chown -R 1000:1000 "$OUT" 2>/dev/null || true
echo "seal ok"
