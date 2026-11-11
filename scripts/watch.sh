#!/usr/bin/env bash
# Open a pull request for each release of tarantool-wasm-rs and EmmyLua the
# tables lack, adding it with scripts/entry.sh and scripts/add.sh.
#
# Usage: scripts/watch.sh [--dry-run]
#
# A release is new when it is newer than the newest version of the table
# that is an upstream release, packed from its assets or built from its tag
# (EmmyLua snapshots built from a commit do not count); with no such
# version, only the latest release is. Drafts and pre-releases are not. A release with a pull request already, open or closed, is left
# alone: a closed one was declined. A release scripts/entry.sh cannot make
# an entry of (an asset is missing, say) is reported and tried again on the
# next run.
#
# --dry-run prints the new releases, ROCK VERSION a line, and changes
# nothing.
#
# The branch of a pull request, watch/ROCK-VERSION, is made from HEAD of
# the checkout and pushed to the remote.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

dry_run=false
if [ "${1:-}" = --dry-run ]; then
	dry_run=true
	shift
fi
[ $# = 0 ] || die "usage: watch.sh [--dry-run]"

# prefix ROCK prints what the tag of an upstream release puts before its
# version.
prefix() {
	case $1 in
	wasm) echo v ;;
	*) echo ;;
	esac
}

# releases ROCK prints the versions of the releases of ROCK upstream.
releases() {
	gh release list -R "$(upstream "$1")" --exclude-drafts --exclude-pre-releases \
		--limit 100 --json tagName --jq '.[].tagName' |
		sed -n "s/^$(prefix "$1")\([0-9]\{1,\}[.][0-9]\{1,\}[.][0-9]\{1,\}\)$/\1/p"
}

# floor ROCK prints the newest version of the table that is an upstream
# release.
floor() {
	jq -r --arg p "$(prefix "$1")" 'to_entries[]
		| select(((.value.platforms // []) != []) or .value.ref == $p + .key) | .key' \
		"$(table "$1")" | sort -V | tail -n 1
}

# newer A B succeeds when the version A is newer than B.
newer() {
	[ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

new=()
for rock in wasm emmylua; do
	known=$(versions "$rock")
	low=$(floor "$rock")
	mapfile -t found < <(releases "$rock" | sort -V)
	if [ -z "$low" ] && [ ${#found[@]} -gt 0 ]; then
		found=("${found[-1]}")
	fi
	for version in "${found[@]}"; do
		grep -qxF "$version" <<<"$known" && continue
		[ -z "$low" ] || newer "$version" "$low" || continue
		new+=("$rock $version")
	done
done

if $dry_run; then
	[ ${#new[@]} = 0 ] || printf '%s\n' "${new[@]}"
	exit 0
fi
if [ ${#new[@]} = 0 ]; then
	say "the tables have every release"
	exit 0
fi

base=$(git -C "$root" rev-parse HEAD)
work=$(mktemp -d)
trap 'git -C "$root" worktree remove --force "$work/tree" 2> /dev/null || true; rm -rf "$work"' EXIT

failed=0
for item in "${new[@]}"; do
	read -r rock version <<<"$item"
	branch=watch/$rock-$version
	if [ -n "$(gh pr list --head "$branch" --state all --json number --jq '.[].number')" ]; then
		say "$rock $version: $branch has a pull request already"
		continue
	fi
	if ! entry=$("$root/scripts/entry.sh" "$rock" "$version"); then
		say "warning: $rock $version: no entry; trying again on the next run"
		failed=1
		continue
	fi

	url=https://github.com/$(upstream "$rock")/releases/tag/$(prefix "$rock")$version
	if jq -e 'all(.[]; (.platforms // []) == [])' <<<"$entry" > /dev/null; then
		how="Built here from the tag of the release for the targets of \`$rock/targets.json\`; the md5 is that of the source archive the rockspec names."
	else
		how="Packed from the assets of the release, checked against the sha256 GitHub reports for them; the md5 is that of the source archive the rockspec names."
	fi

	git -C "$root" worktree add -q --detach "$work/tree" "$base"
	"$work/tree/scripts/add.sh" "$rock" <<<"$entry"
	git -C "$work/tree" add "$rock/releases.json"
	git -C "$work/tree" -c user.name="$bot_name" -c user.email="$bot_email" \
		commit -q -m "$rock: add $version" -m "$url" -m "$how"
	# The branch is the workflow's: a run whose pull request failed left it.
	rgit -C "$work/tree" push -q --force "$(remote)" "HEAD:refs/heads/$branch"
	git -C "$root" worktree remove --force "$work/tree"

	cat > "$work/body" <<-EOF
		Adds $rock $version, $url, to \`$rock/releases.json\`.

		$how Review the release before merging: once this is merged, the publish workflow publishes \`$rock-$version-1\`.

		Opened by the watch workflow. Pull requests it opens run no checks; close and reopen this one to run them.
	EOF
	gh pr create --base master --head "$branch" --title "$rock: add $version" --body-file "$work/body"
done
exit "$failed"
