#!/usr/bin/env bash
# Add the entries of those of the releases TAG... that are published to
# tt-rocks-index.json of the branch index, set the yanked flags of its
# entries as the tables say, in one commit, and push it.
#
# Usage: scripts/index-push.sh [TAG...]
#
# A release that is not published (its publication failed) is left out and
# makes the script fail once the others are pushed. An entry the branch has
# already is refused (scripts/index.sh), and so is a push that is not a
# fast-forward: the next run of the publish workflow starts over from what
# the branch holds then.
#
# An entry of a table with "yanked", the reason, yanks its version-revision:
# its entry of the index gets "yanked": true, and loses it once the table
# has it no more (yank_changes of scripts/lib.sh). That is the one change
# an entry ever has. With nothing to index or yank, nothing is pushed.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
index_checkout "$work"
index=$work/tt-rocks-index.json

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
	"$root/scripts/index.sh" "$index" "${published[@]}"
fi
mapfile -t yanks < <(apply_yanks "$index")
for yank in "${yanks[@]}"; do
	say "$yank"
done

if [ ${#published[@]} -gt 0 ] || [ ${#yanks[@]} -gt 0 ]; then
	subject=()
	if [ ${#published[@]} -gt 0 ]; then
		subject+=("Index ${published[*]}")
	fi
	if [ ${#yanks[@]} -gt 0 ]; then
		what=$(printf '%s\n' "${yanks[@]}" | sed 's/:.*//' | paste -sd ',' | sed 's/,/, /g')
		subject+=("$what")
	fi
	{
		printf '%s\n' "${subject[@]}" | paste -sd ';' | sed 's/;/; /g; s/^./\U&/'
		echo
		for tag in "${published[@]}"; do
			echo "- https://github.com/${GH_REPO:-}/releases/tag/$tag"
		done
		for yank in "${yanks[@]}"; do
			echo "- $yank"
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
	say "pushed $(git -C "$work" rev-parse --short HEAD) to the branch index"
else
	say "nothing to index or yank"
fi

if [ ${#left[@]} -gt 0 ]; then
	die "not published, so not indexed: ${left[*]}"
fi
