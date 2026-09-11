#!/usr/bin/env bash
# Stamp the shared installer bodies into this repo's install.sh and install.ps1.
#
#   ./render-installers.sh           rewrite each installer, report updated/unchanged
#   ./render-installers.sh --check   verify they match; exit 1 on drift
#
# --check is what you want in a pre-tag gate: it fails if an installer was edited
# directly instead of editing the shared template.
#
# The stamping itself lives in the install_scripts repo (simple/render-installer.sh).
# Everything here is installer-specific policy: which targets to render.
set -uo pipefail

cd "$(dirname "$0")" || exit 1

INSTALL_SCRIPTS_DIR="${INSTALL_SCRIPTS_DIR:-$HOME/main/install_scripts}"
STAMPER="$INSTALL_SCRIPTS_DIR/simple/render-installer.sh"


TARGETS=(
  "install.sh"
  "install.ps1"
)

case "${1:-}" in
  --check|"") ;;
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

# Rendering is in place: the target supplies its own config block and receives the
# result, so IN and OUT are the same path. Accumulate failure so --check can gate a
# preflight -- a single drifted or broken target must fail the whole run.
fail=0
for t in "${TARGETS[@]}"; do
  "$STAMPER" "$@" "$t" || fail=1
done

exit "$fail"
