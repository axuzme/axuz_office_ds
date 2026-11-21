#!/usr/bin/env bash
# check-agpl-notices.sh — gate AGPL do repo espelho (secao 5/13 e termos adicionais do ONLYOFFICE).
# Delega a recipe/security/office/check-agpl-notices.sh (copia do axuz_ops no commit de recipe/RECIPE_COMMIT) com --root recipe/office.
# Uso: bash check-agpl-notices.sh [--artifact <documentserver>] [--self-check]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$HERE/recipe/security/office/check-agpl-notices.sh" --root "$HERE/recipe/office" "$@"
