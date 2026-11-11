#!/usr/bin/env bash
# Yank the version-revision KEY of ROCK: mark its entry of
# tt-rocks-index.json of the branch index "yanked": true, in one commit, and
# push it.
#
# Usage: scripts/yank.sh ROCK KEY [REASON]
#
# A yanked version stays where it is, its release and its rocks too: a
# project that locked it still installs it, but tt resolves a new
# dependency to it no more. Yanking is the one change an entry can have,
# and it is not undone here. A version yanked already is left as it is.
# REASON, if given, goes into the message of the commit. As
# scripts/index-push.sh, it refuses a push that is not a fast-forward:
# run it again.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# = 2 ] || [ $# = 3 ] || die "usage: yank.sh ROCK VERSION-REVISION [REASON]"
rock=$1
key=$2
reason=${3:-}
[[ $key =~ ^[0-9][^-]*-[0-9]+$ ]] || die "$key is not a VERSION-REVISION"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
index_checkout "$work"
index=$work/tt-rocks-index.json

index_has "$index" "$rock" "$key" || die "$rock $key is not in the index"
if jq -e --arg r "$rock" --arg k "$key" '.repository[$r][$k].yanked == true' "$index" > /dev/null; then
	say "$rock $key is yanked already"
	exit 0
fi

jq --arg r "$rock" --arg k "$key" '.repository[$r][$k].yanked = true' "$index" > "$work/new"
mv "$work/new" "$index"

{
	echo "Yank $rock $key"
	if [ -n "$reason" ]; then
		echo
		printf '%s\n' "$reason"
	fi
	if [ -n "${GITHUB_RUN_ID:-}" ]; then
		echo
		echo "Run: ${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
	fi
} > "$work/message"

git -C "$work" add tt-rocks-index.json
git -C "$work" -c user.name="$bot_name" -c user.email="$bot_email" \
	commit -q -F "$work/message"
rgit -C "$work" push -q "$(remote)" HEAD:refs/heads/index
say "pushed $(git -C "$work" rev-parse --short HEAD) to the branch index: $rock $key is yanked"
