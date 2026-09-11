#!/usr/bin/env bash
# Render one shared file in a GDExtension addon repo.
#
#   render-target.sh TARGET            rewrite TARGET, report updated/unchanged
#   render-target.sh --check TARGET    verify TARGET matches; exit 1 on drift
#
# The basename picks the policy:
#
#   package.sh   body stamped from package.template.sh, the repo's own config block
#                (everything through "# ---- end config ----") preserved; sh -n
#                syntax-checked, plus dash -n when dash is installed
#   build.yml    byte-identical copy of build.template.yml; package.sh owns the
#                per-repo archive name, so the workflow needs no config
#
# --check never writes. It is what you want in a preflight or pre-tag gate: it fails
# if someone edited a repo's copy directly instead of editing the template.
#
# One target per call -- repos drive their own list from a render-gdext.sh that
# loops and calls this. The stamping itself is generic and lives in
# common/stamp-template.sh; everything here is gdext-specific policy.
set -uo pipefail

# Resolve relative to this script, so the repo works no matter where it is cloned.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$DIR/../common/stamp-template.sh"

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; }

# Flags come before TARGET, so --help is reachable rather than being swallowed as a
# path. TARGET is relative to the caller's cwd -- deliberately no cd here.
CHECK=0
case "${1:-}" in
  --check) CHECK=1; shift ;;
  -h|--help) usage; exit 0 ;;
  -*) echo "unknown option: $1" >&2; exit 2 ;;
esac

TARGET="${1:-}"
[ -n "$TARGET" ] || { usage >&2; echo "error: expected a TARGET path" >&2; exit 2; }

fail=0
err() { echo "  error: $*" >&2; fail=1; }

case "$(basename "$TARGET")" in
  package.sh) KIND=package; TEMPLATE="$DIR/package.template.sh" ;;
  build.yml)  KIND=workflow; TEMPLATE="$DIR/build.template.yml" ;;
  *) echo "error: no render policy for '$TARGET'" >&2; exit 2 ;;
esac

[ -f "$TEMPLATE" ] || { echo "error: $TEMPLATE not found" >&2; exit 1; }
[ -x "$STAMP" ] || { echo "error: $STAMP not found or not executable" >&2; exit 1; }

# Label with the target's parent dir, e.g. tree-sitter-gd -> "tree-sitter-gd". A
# target at the repo root has no parent to name, so fall back to the cwd -- the
# caller cd's into the repo before looping, so that is the repo name.
name=$(basename "$(dirname "$TARGET")")
[ "$name" = "." ] && name=$(basename "$PWD")
printf '  %-16s %-28s ' "$name" "$TARGET"

if [ ! -f "$TARGET" ] && [ "$CHECK" -eq 1 ]; then
  echo "MISSING"
  exit 1
fi

if [ "$KIND" = workflow ]; then
  # Byte-identical copy: no config block to preserve, just copy or diff.
  if [ -f "$TARGET" ] && cmp -s "$TEMPLATE" "$TARGET"; then
    echo "unchanged"
    exit 0
  fi
  if [ "$CHECK" -eq 1 ]; then
    echo "DRIFT (differs from $TEMPLATE)"
    exit 1
  fi
  mkdir -p "$(dirname "$TARGET")"
  cp "$TEMPLATE" "$TARGET"
  echo "updated"
  exit 0
fi

# package.sh: stamp the template body below the marker, preserving the config block.
if [ ! -f "$TARGET" ]; then
  echo
  err "$TARGET not found -- create it with just a config block and the"
  err "'# ---- end config ----' marker, then re-run to receive the body"
  exit 1
fi

if ! sh -n "$TEMPLATE" 2>&1; then
  echo
  err "$TEMPLATE fails its syntax check"
  exit 1
fi

if [ "$CHECK" -eq 1 ]; then
  status=$("$STAMP" --check "$TEMPLATE" "$TARGET" "$TARGET" 2>&1)
  case "$?" in
    0) echo "$status" ;;
    1) echo "DRIFT (body differs from $TEMPLATE)"; fail=1 ;;
    *) echo; err "$status" ;;
  esac
  exit "$fail"
fi

status=$("$STAMP" "$TEMPLATE" "$TARGET" "$TARGET" 2>&1)
if [ $? -ne 0 ]; then
  echo; err "$status"
  exit 1
fi

# Syntax-check the rendered result, not just the template: a config block can
# introduce its own errors.
if ! sh -n "$TARGET" 2>&1; then echo; err "$TARGET fails its syntax check"; exit 1; fi
if command -v dash >/dev/null 2>&1 && ! dash -n "$TARGET" 2>&1; then
  echo; err "$TARGET fails dash syntax check"
  exit 1
fi

echo "$status"
exit 0
