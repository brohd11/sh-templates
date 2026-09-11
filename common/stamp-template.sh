#!/usr/bin/env bash
# Regenerate a file whose top section is bespoke and whose body comes from a template.
#
#   stamp-template.sh [--check] TEMPLATE IN OUT
#
#   TEMPLATE   supplies the body: everything AFTER the marker line
#   IN         supplies the config block: everything UP TO AND INCLUDING the marker
#   OUT        destination; "-" writes the rendered result to stdout
#
# Rendering in place is just IN and OUT being the same path.
#
#   --check    compare against OUT instead of writing; exit 1 if they differ
#
# Exit: 0 success, 1 drift (--check only), 2 usage or structural error.
#
# Content-agnostic -- it does not care what kind of file this is. Callers that need
# the output validated (syntax-checking a shell script, say) should do that themselves.
#
# The marker can be overridden for files using a different delimiter:
#   MARKER='### END HEADER' stamp-template.sh t.txt in.txt out.txt
set -uo pipefail

MARKER="${MARKER:-# ---- end config ----}"

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

die() { echo "stamp-template: $*" >&2; exit 2; }

CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

[ $# -eq 3 ] || { usage >&2; die "expected TEMPLATE IN OUT, got $# argument(s)"; }

template=$1
in_file=$2
out_file=$3

[ -f "$template" ] || die "template not found: $template"
[ -f "$in_file" ] || die "input not found: $in_file"

# --check compares against OUT, so there has to be a real OUT to compare with.
if [ "$CHECK" -eq 1 ] && [ "$out_file" = "-" ]; then
  die "--check needs a real OUT path to compare against, not '-'"
fi

# Both halves require the marker. Bailing out here is what stops a malformed input
# from producing a truncated or doubled result.
grep -qxF "$MARKER" "$template" || die "no '$MARKER' line in template: $template"
grep -qxF "$MARKER" "$in_file" || die "no '$MARKER' line in input: $in_file"

# Body: everything after the marker. Config: everything through it.
body=$(awk -v m="$MARKER" 'found { print } $0 == m { found = 1 }' "$template")
config=$(awk -v m="$MARKER" '{ print } $0 == m { exit }' "$in_file")

rendered=$(printf '%s\n%s\n' "$config" "$body")

# Content goes to stdout, so no status word here -- mixing the two would corrupt
# anything piping this into a diff.
if [ "$out_file" = "-" ]; then
  printf '%s\n' "$rendered"
  exit 0
fi

if [ -f "$out_file" ] && [ "$rendered" = "$(cat "$out_file")" ]; then
  echo "unchanged"
  exit 0
fi

if [ "$CHECK" -eq 1 ]; then
  echo "drift"
  exit 1
fi

printf '%s\n' "$rendered" > "$out_file" || die "could not write: $out_file"

# Carry over the executable bit rather than forcing one, so this works for files
# that are not meant to be executable.
[ -x "$in_file" ] && chmod +x "$out_file"

echo "updated"
exit 0
