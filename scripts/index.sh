#!/usr/bin/env bash
# Add the entries of the published releases TAG... to the index FILE.
#
# Usage: scripts/index.sh FILE TAG...
#
# An entry lists the rockspec and the rock of each arch of the release,
# with their URLs, the sha256 GitHub computed for them on upload (the
# digests of the assets) and the sizes of the rocks. An arch is a platform,
# OS-CPU, or all for an .all rock, or src for a source rock. A
# version-revision the index has already is refused: an entry, once
# written, never changes, but for being yanked (scripts/index-push.sh).
# The file is written deterministically: keys of rocks and versions
# sorted, artifacts by arch, entries in the order of the format.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# -ge 2 ] || die "usage: index.sh FILE TAG..."
index=$1
shift
jq -e '.format == 1' "$index" > /dev/null || die "$index is not an index of format 1"

new='{}'
for tag; do
	read -r rock key < <(split_tag "$tag") || die "$tag is the tag of no rock of the repository"
	if index_has "$index" "$rock" "$key" || jq -e --arg r "$rock" --arg k "$key" '.[$r][$k]' <<<"$new" > /dev/null; then
		die "$rock $key is in the index already"
	fi

	view=$(gh release view "$tag" --json tagName,isDraft,assets)
	entry=$(jq -c --arg tag "$tag" '
		def sha: if (.digest // "") | test("^sha256:[0-9a-f]{64}$") then .digest[7:]
			else error("\(.name) has no sha256 digest") end;
		def link: .name as $name
			| if (.url | startswith("https://"))
				and (.url | endswith("/releases/download/\($tag)/\($name)")) then .url
			else error("\($name) is at \(.url), not at the tag \($tag)") end;
		def rock: .name | startswith("\($tag).") and endswith(".rock");
		if .isDraft then error("\($tag) is a draft") else . end
		| (.assets | map(select(.name == "\($tag).rockspec"))) as $specs
		| (.assets | map(select(rock))) as $rocks
		| (.assets | map(select(.name != "\($tag).rockspec" and (rock | not)) | .name)) as $other
		| if ($specs | length) != 1 then error("\($tag) has no \($tag).rockspec")
		  elif ($rocks | length) == 0 then error("\($tag) has no rocks")
		  elif ($other | length) > 0 then error("\($tag) has assets of no rock: \($other | join(", "))")
		  else {
			rockspec: ($specs[0] | {url: link, sha256: sha}),
			artifacts: ($rocks
				| map({arch: .name[($tag | length) + 1:-5], url: link, sha256: sha, size})
				| sort_by(.arch))
		  } end
		| if all(.artifacts[]; .arch | test("^([a-z0-9_]+-[a-z0-9_]+|all|src)$")) then .
		  else error("\($tag) has a rock of no arch: \([.artifacts[].arch] | join(", "))") end
	' <<<"$view" 2>&1) || die "$tag: ${entry#jq: error (at <stdin>:*): }"

	# The rocks are those of the archs of the table, if it still has the
	# revision.
	version=${key%-*}
	if [ "$(jq -r --arg v "$version" '.[$v].rock_revision // empty' "$(table "$rock")")" = "${key##*-}" ]; then
		want=$(archs "$rock" "$version")
		have=$(jq -r '.artifacts[].arch' <<<"$entry")
		[ "$have" = "$want" ] ||
			die "$tag has rocks of"$'\n'"$have"$'\n'"but $rock/releases.json names"$'\n'"$want"
	fi

	new=$(jq -c --arg r "$rock" --arg k "$key" --argjson e "$entry" '.[$r][$k] = $e' <<<"$new")
	say "index $rock $key"
done

tmp=$(mktemp "$index.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq --argjson new "$new" '
	def sorted: to_entries | sort_by(.key) | from_entries;
	reduce ($new | to_entries[]) as $r (.;
		reduce ($r.value | to_entries[]) as $v (.;
			if .repository[$r.key][$v.key] != null then error("\($r.key) \($v.key) is in the index already")
			else .repository[$r.key][$v.key] = $v.value end))
	| .repository |= (map_values(sorted) | sorted)
' "$index" > "$tmp"
mv "$tmp" "$index"
trap - EXIT
