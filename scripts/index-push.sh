#!/usr/bin/env bash
# Add the entries of those of the releases TAG... that are published to
# tt-rocks-index.json of the branch index, in one commit, and push it.
#
# Usage: scripts/index-push.sh TAG...
#
# A release that is not published (its publication failed) is left out and
# makes the script fail once the others are pushed. An entry the branch has
# already is refused (scripts/index.sh), and so is a push that is not a
# fast-forward: the next run of the publish workflow starts over from what
# the branch holds then.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# -ge 1 ] || die "usage: index-push.sh TAG..."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
index_checkout "$work"

published=()
left=()
for tag; do
	if [ "$(release_state "$tag")" = published ]; then
		published+=("$tag")
	else
		left+=("$tag")
	fi
done

if [ ${#published[@]} -gt 0 ]; then
	"$root/scripts/index.sh" "$work/tt-rocks-index.json" "${published[@]}"

	{
		echo "Index ${published[*]}"
		echo
		for tag in "${published[@]}"; do
			echo "- https://github.com/${GH_REPO:-}/releases/tag/$tag"
		done
		if [ -n "${GITHUB_RUN_ID:-}" ]; then
			echo
			echo "Run: ${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
		fi
	} > "$work/message"

	git -C "$work" add tt-rocks-index.json
	git -C "$work" -c user.name="$bot_name" -c user.email="$bot_email" \
		commit -q -F "$work/message"
	rgit -C "$work" push -q "$(remote)" HEAD:refs/heads/index
	say "pushed $(git -C "$work" rev-parse --short HEAD) to the branch index: ${published[*]}"
fi

if [ ${#left[@]} -gt 0 ]; then
	die "not published, so not indexed: ${left[*]}"
fi
