#!/usr/bin/env bash
# Stamp the matching template's body into one repo's installer.
#
#   render-installer.sh TARGET            rewrite TARGET, report updated/unchanged
#   render-installer.sh --check TARGET    verify TARGET matches; exit 1 on drift
#
# TARGET's extension picks the template and the syntax check:
#   *.ps1   install.template.ps1   parsed with pwsh, when pwsh is installed
#   *       install.template.sh    sh -n, plus dash -n when dash is installed
#
# Every installer is identical below the "# ---- end config ----" line; only the
# config block above it differs per project. This rewrites TARGET's body from the
# template while preserving TARGET's own config block verbatim. "# ..." is a comment
# in PowerShell too, so the same marker works for both without an override.
#
# --check never writes. It is what you want in a preflight or pre-tag gate: it fails
# if someone edited a repo's copy directly instead of editing the template.
#
# One target per call -- repos drive their own list from a render-installers.sh that
# loops and calls this. The stamping itself is generic and lives in common/; everything
# here is installer-specific policy: syntax-checking the output.
set -uo pipefail

# Resolve relative to this script, so the repo works no matter where it is cloned.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$DIR/../common/stamp-template.sh"

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

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

# The extension is the only thing distinguishing the two installers, so it selects both
# the template and the checker.
case "$TARGET" in
  *.ps1) TEMPLATE="$DIR/install.template.ps1"; KIND=ps1 ;;
  *)     TEMPLATE="$DIR/install.template.sh";  KIND=sh ;;
esac

[ -f "$TEMPLATE" ] || { echo "error: $TEMPLATE not found" >&2; exit 1; }
[ -x "$STAMP" ] || { echo "error: $STAMP not found or not executable" >&2; exit 1; }

# Parse-check a file without running it. Returns non-zero with the parser's message on
# stderr. For ps1 this needs PowerShell itself: there is no standalone parser, and the
# language is too irregular to approximate. When pwsh is absent the check is skipped
# rather than faked -- on a Mac that is the normal case, and the gate then only bites
# in CI or on Windows.
check_syntax() {
  target=$1
  case "$KIND" in
    sh)
      sh -n "$target" || return 1
      if command -v dash >/dev/null 2>&1; then dash -n "$target" || return 1; fi
      ;;
    ps1)
      command -v pwsh >/dev/null 2>&1 || return 0
      pwsh -NoProfile -NonInteractive -Command '
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
          (Resolve-Path -LiteralPath $args[0]).Path, [ref]$null, [ref]$errors)
        if ($errors) { $errors | ForEach-Object { $_.ToString() }; exit 1 }
      ' -args "$target" || return 1
      ;;
  esac
  return 0
}

# Syntax-check the template before stamping it anywhere. This is the caller's job --
# stamp-template.sh is content-agnostic and makes no assumption that what it's
# stamping is even a script.
check_syntax "$TEMPLATE" || { echo "error: $TEMPLATE fails its syntax check" >&2; exit 1; }

# Say so on the row itself rather than as a line of its own: one target is one process,
# so a standalone note would repeat above every ps1 row.
SUFFIX=""
if [ "$KIND" = ps1 ] && ! command -v pwsh >/dev/null 2>&1; then
  SUFFIX=" (unchecked: no pwsh)"
fi

# Label with the target's parent dir, e.g. gdaddon/install.sh -> "gdaddon". A target
# at the repo root (install.sh) has no parent to name, so fall back to the cwd -- the
# caller cd's into the repo before looping, so that is the repo name. The filename goes
# in too: a repo has more than one installer now, and two identical rows would be
# unreadable in --check output.
name=$(basename "$(dirname "$TARGET")")
[ "$name" = "." ] && name=$(basename "$PWD")
printf '  %-10s %-11s ' "$name" "$(basename "$TARGET")"

if [ ! -f "$TARGET" ]; then
  echo; err "$TARGET not found"
  exit 1
fi

# Rendering is in place: the target supplies its own config block and receives the
# result, so IN and OUT are the same path.
if [ "$CHECK" -eq 1 ]; then
  status=$("$STAMP" --check "$TEMPLATE" "$TARGET" "$TARGET" 2>&1)
  case "$?" in
    0) echo "$status$SUFFIX" ;;
    1) echo "DRIFT (body differs from $TEMPLATE)"; fail=1 ;;
    *) echo; err "$status" ;;
  esac
  if [ "$fail" -ne 0 ]; then
    echo
    echo "FAIL -- re-stamp with: $(basename "$0") $TARGET"
    echo "and edit $TEMPLATE rather than the per-repo copies."
  fi
  exit "$fail"
fi

status=$("$STAMP" "$TEMPLATE" "$TARGET" "$TARGET" 2>&1)
if [ $? -ne 0 ]; then
  echo; err "$status"
  exit 1
fi

# Syntax-check the rendered result, not just the template: a config block can
# introduce its own errors (an unbalanced heredoc in post_install_note, say).
if ! check_syntax "$TARGET"; then echo; err "$TARGET fails its syntax check"; exit 1; fi

echo "$status$SUFFIX"
exit 0
