#!/usr/bin/env bash
# Stamp the shared gdext files into this repo.
#
#   ./render-gdext.sh           rewrite each target, report updated/unchanged
#   ./render-gdext.sh --check   verify they match; exit 1 on drift
#
# --check is what you want in a pre-tag gate: it fails if a shared file was edited
# directly instead of editing the shared template.
#
# The rendering itself lives in the install_scripts repo (gdext/render-target.sh).
# Everything here is repo-local policy: which targets to render.
#
# Bootstrap for a new repo: commit a package.sh containing only its config block
# (ADDON_SRC/ADDON_DEST/VERSION_FILE) and the "# ---- end config ----" marker, then
# run this once to receive the body.
set -uo pipefail

cd "$(dirname "$0")" || exit 1

INSTALL_SCRIPTS_DIR="${INSTALL_SCRIPTS_DIR:-$HOME/main/install_scripts}"
RENDERER="$INSTALL_SCRIPTS_DIR/gdext/render-target.sh"

TARGETS=(
  "package.sh"
  ".github/workflows/build.yml"
)

case "${1:-}" in
  --check|"") ;;
  -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

# Rendering is in place: the target supplies its own config block and receives the
# result. Accumulate failure so --check can gate a preflight -- a single drifted or
# broken target must fail the whole run.
fail=0
for t in "${TARGETS[@]}"; do
  "$RENDERER" "$@" "$t" || fail=1
done

exit "$fail"
