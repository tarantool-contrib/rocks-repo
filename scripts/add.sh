#!/usr/bin/env bash
# Add the entries scripts/entry.sh prints, read from stdin, to
# ROCK/releases.json. A version already there is an error: its rocks are
# published, and projects lock them. A new build of it is a new
# rock_revision, edited by hand.
#
# Usage: scripts/entry.sh emmylua 0.26.0 | scripts/add.sh emmylua
set -euo pipefail

rock=$1
root=$(cd "$(dirname "$0")/.." && pwd)
table=$root/$rock/releases.json

entry=$(cat)
taken=$(jq -rn --argjson old "$(cat "$table")" --argjson new "$entry" \
	'[$new | keys[] | select($old[.])] | join(" ")')
if [ -n "$taken" ]; then
	echo "$rock/releases.json has $taken already" >&2
	exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
jq -S --argjson new "$entry" '. + $new' "$table" > "$tmp"
cat "$tmp" > "$table"
