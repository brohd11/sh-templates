#!/usr/bin/env bash
# Render this repo's shared macOS app installer, release workflow, and changelog config.
#
#   ./render-mac.sh           rewrite each target, report updated/unchanged
#   ./render-mac.sh --check   verify each matches; exit 1 on drift
#
# Copy this entry script into a consumer repo as render-mac.sh. Bootstrap install.sh
# with its config block and marker; provide scripts/package.sh (see sh-templates README).
# Templates and rendering live in the pinned sh-templates submodule.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
RENDERER="$ROOT/sh-templates/mac-apps/render-target.sh"

TARGETS=(
  "install.sh"
  ".github/workflows/release.yml"
  "cliff.toml"
)

case "${1:-}" in
  --check|"") ;;
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { echo "error: expected at most one option" >&2; exit 2; }

if [ ! -x "$RENDERER" ]; then
  echo "$(basename "$0"): required submodule renderer not found: $RENDERER" >&2
  echo "Initialize it with: git submodule update --init sh-templates" >&2
  exit 1
fi

fail=0
for target in "${TARGETS[@]}"; do
  "$RENDERER" "$@" "$target" || fail=1
done
exit "$fail"
