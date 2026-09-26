#!/usr/bin/env bash
# Render one shared Go installer, workflow, makefile, or changelog config.
#
#   render-target.sh TARGET            rewrite TARGET, report updated/unchanged
#   render-target.sh --check TARGET    verify TARGET matches; exit 1 on drift
#
# TARGET's basename selects the template:
#   test.yml / release.yml / cliff.toml   byte-identical copies
#   makefile / Makefile      shared body with the target's config block preserved
#   install.sh / install.ps1 shared installer body, with syntax checks
#
# TARGET is relative to the caller's cwd. Copies can be created from scratch;
# stamped files need their config and the "# ---- end config ----" marker first.
# Exit: 0 success, 1 drift/missing target or render failure, 2 invalid usage/structure.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$DIR/../common/stamp-template.sh"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

CHECK=0
case "${1:-}" in
  --check) CHECK=1; shift ;;
  -h|--help) usage; exit 0 ;;
  -*) echo "unknown option: $1" >&2; exit 2 ;;
esac

[ "$#" -eq 1 ] && [ -n "$1" ] || {
  usage >&2
  echo "error: expected one TARGET path" >&2
  exit 2
}
TARGET=$1

case "$(basename "$TARGET")" in
  install.sh)  KIND=sh; TEMPLATE="$DIR/templates/install.template.sh" ;;
  install.ps1) KIND=ps1; TEMPLATE="$DIR/templates/install.template.ps1" ;;
  test.yml)    KIND=copy; TEMPLATE="$DIR/templates/test.template.yml" ;;
  release.yml) KIND=copy; TEMPLATE="$DIR/templates/release.template.yml" ;;
  cliff.toml)  KIND=copy; TEMPLATE="$DIR/templates/cliff.template.toml" ;;
  makefile|Makefile) KIND=makefile; TEMPLATE="$DIR/templates/makefile.template" ;;
  *) echo "error: no render policy for '$TARGET'" >&2; exit 2 ;;
esac

[ -f "$TEMPLATE" ] || { echo "error: $TEMPLATE not found" >&2; exit 1; }
if [ "$KIND" != copy ] && [ ! -x "$STAMP" ]; then
  echo "error: $STAMP not found or not executable" >&2
  exit 1
fi

printf '  %-40s ' "$TARGET"
if [ -e "$TARGET" ] && [ ! -f "$TARGET" ]; then
  echo "ERROR -- target is not a regular file" >&2
  exit 1
fi
if [ ! -f "$TARGET" ]; then
  if [ "$CHECK" -eq 1 ]; then
    echo "MISSING"
    exit 1
  fi
  if [ "$KIND" != copy ]; then
    echo "MISSING -- create a config block ending with '# ---- end config ----' first"
    exit 1
  fi
fi

if [ "$KIND" = copy ]; then
  if [ -f "$TARGET" ] && cmp -s "$TEMPLATE" "$TARGET"; then
    echo "unchanged"
    exit 0
  fi
  if [ "$CHECK" -eq 1 ]; then
    echo "DRIFT (differs from $TEMPLATE)"
    exit 1
  fi
  if ! mkdir -p "$(dirname "$TARGET")" || ! cp "$TEMPLATE" "$TARGET"; then
    echo "ERROR -- could not write $TARGET" >&2
    exit 1
  fi
  echo "updated"
  exit 0
fi

# Installers need syntax validation in addition to the common config/body stamp.
# PowerShell parsing is optional locally; preserve literal paths through the environment.
check_syntax() {
  local syntax_target=$1
  case "$KIND" in
    sh)
      sh -n "$syntax_target" || return 1
      if command -v dash >/dev/null 2>&1; then dash -n "$syntax_target" || return 1; fi
      ;;
    ps1)
      command -v pwsh >/dev/null 2>&1 || return 0
      INSTALLER_PARSE_PATH="$syntax_target" pwsh -NoProfile -NonInteractive -Command '
        $ErrorActionPreference = "Stop"
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
          (Resolve-Path -LiteralPath $env:INSTALLER_PARSE_PATH).Path, [ref]$null, [ref]$errors)
        if ($errors) { $errors | ForEach-Object { $_.ToString() }; exit 1 }
      ' || return 1
      ;;
  esac
  return 0
}

if ! check_syntax "$TEMPLATE"; then
  echo "ERROR -- $TEMPLATE fails its syntax check" >&2
  exit 1
fi

SUFFIX=""
if [ "$KIND" = ps1 ] && ! command -v pwsh >/dev/null 2>&1; then
  SUFFIX=" (unchecked: no pwsh)"
fi

if [ "$CHECK" -eq 1 ]; then set -- --check; else set --; fi
out=$("$STAMP" "$@" "$TEMPLATE" "$TARGET" "$TARGET" 2>&1)
status=$?
# In check mode a matching body can still have an invalid consumer config. In
# render mode validate the resulting file, after replacing any old body.
if [ "$status" -le 1 ] && ! check_syntax "$TARGET"; then
  echo "ERROR -- $TARGET fails its syntax check" >&2
  exit 1
fi
case "$status" in
  0) echo "$out$SUFFIX" ;;
  1) echo "DRIFT (body differs from $TEMPLATE)$SUFFIX" ;;
  *) echo "ERROR"; printf '%s\n' "$out" >&2 ;;
esac
exit "$status"
