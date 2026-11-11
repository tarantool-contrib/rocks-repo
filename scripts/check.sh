#!/usr/bin/env bash
# Check the index FILE against the releases:
#
#   - the entries are of the format, their URLs end in the names of the
#     files they are of, an arch is a platform, all or src, and yanked, of
#     a version withdrawn, is a boolean;
#   - every published release ROCK-* of a rock of the repository is in the
#     index;
#   - every URL of the index answers with what its sha256 (and size) says;
#   - the rockspec of an entry is the rockspec each of its rocks holds.
#
# Usage: scripts/check.sh FILE
#
# It downloads every file the index names, of the yanked versions too: a
# project that locked one still installs it. The versions of the tables the
# index lacks are reported, not failed: the publish workflow adds them; so
# are the yanked ones. A relative URL is resolved against $INDEX_URL,
# default the URL the index is served from.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# = 1 ] || die "usage: check.sh FILE"
index=$1
base=${INDEX_URL:-https://raw.githubusercontent.com/${GH_REPO:-}/index/}

errors=0

# fail MESSAGE reports a problem; the check fails at the end.
fail() {
	errors=$((errors + 1))
	if [ -n "${GITHUB_ACTIONS:-}" ]; then
		printf '::error::%s\n' "${*//$'\n'/%0A}"
	else
		printf 'error: %s\n' "$*" >&2
	fi
}

# notice MESSAGE reports what is fine but worth knowing.
notice() {
	if [ -n "${GITHUB_ACTIONS:-}" ]; then
		printf '::notice::%s\n' "$*"
	else
		printf 'notice: %s\n' "$*" >&2
	fi
}

# download URL FILE fetches URL into FILE.
download() {
	local url=$1
	[[ $url == *://* ]] || url=${base%/}/$url
	curl -fsSL --retry 3 --retry-all-errors --connect-timeout 30 -o "$2" "$url"
}

# The format.
problems=$(jq -r '
	def hex64: type == "string" and test("^[0-9a-f]{64}$");
	def named($name): type == "string"
		and (test("^https://") or (test("^[a-z][a-z0-9+.-]*:") | not))
		and (split("?")[0] | split("/") | last) == $name;
	if .format != 1 then "the index is of format \(.format), not 1"
	elif (.repository | type) != "object" then "the index has no repository"
	else
		.repository | to_entries[] | .key as $rock | .value | to_entries[]
		| .key as $key | .value as $e | "\($rock) \($key)" as $at
		| if ($key | test("^[^-]+-[0-9]+$") | not) then "\($at): not a version-revision"
		  else
			(if ($e.rockspec.url | named("\($rock)-\($key).rockspec")) then empty
			 else "\($at): the rockspec URL \($e.rockspec.url) is not of \($rock)-\($key).rockspec" end),
			(if ($e.rockspec.sha256 | hex64) then empty else "\($at): the rockspec has no sha256" end),
			(if $e.yanked == null or ($e.yanked | type) == "boolean" then empty
			 else "\($at): yanked is no boolean" end),
			(if ($e.artifacts | type) == "array" and ($e.artifacts | length) > 0 then
				($e.artifacts[] | "\($rock)-\($key).\(.arch).rock" as $name
				 | (if (.arch | type) == "string" and (.arch | test("^([a-z0-9_]+-[a-z0-9_]+|all|src)$"))
				    then empty else "\($at): \(.arch | tojson) is no arch" end),
				   (if (.url | named($name)) then empty
				    else "\($at): the URL \(.url) is not of \($name)" end),
				   (if (.sha256 | hex64) then empty else "\($at): \($name) has no sha256" end),
				   (if .size == null or (.size | type) == "number" then empty
				    else "\($at): the size of \($name) is no number" end)),
				(if ([$e.artifacts[].arch] | unique | length) == ($e.artifacts | length) then empty
				 else "\($at): an arch is listed twice" end)
			 else "\($at): no artifacts" end)
		  end
	end' "$index")
while IFS= read -r problem; do
	[ -z "$problem" ] || fail "$problem"
done <<<"$problems"
if [ "$errors" -gt 0 ]; then
	die "$index is not of the format"
fi

# Every published release is in the index.
tags=$(gh release list --exclude-drafts --limit 1000 --json tagName --jq '.[].tagName')
count=$(grep -c . <<<"$tags" || true)
[ "$count" -lt 1000 ] || fail "1000 releases or more: raise the --limit of gh release list"
while read -r tag; do
	[ -n "$tag" ] || continue
	if ! read -r rock key < <(split_tag "$tag"); then
		continue
	fi
	index_has "$index" "$rock" "$key" ||
		fail "the release $tag is published but not in the index: run the publish workflow to index it"
done <<<"$tags"

# Every file of the index is what the index says it is.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
entries=$(jq -r '.repository | to_entries[] | .key as $r | .value | keys[] | "\($r) \(.)"' "$index")
checked=0
while read -r rock key; do
	[ -n "$rock" ] || continue
	entry=$(jq -c --arg r "$rock" --arg k "$key" '.repository[$r][$k]' "$index")
	if jq -e '.yanked == true' <<<"$entry" > /dev/null; then
		notice "$rock $key is yanked"
	fi
	spec=$work/$rock-$key.rockspec
	url=$(jq -r .rockspec.url <<<"$entry")
	if ! download "$url" "$spec"; then
		fail "$rock $key: $url does not answer"
		continue
	fi
	if [ "$(sha256sum < "$spec" | cut -d' ' -f1)" != "$(jq -r .rockspec.sha256 <<<"$entry")" ]; then
		fail "$rock $key: the sha256 of $url is not that of the index"
	fi
	while read -r arch url sha size; do
		file=$work/$rock-$key.$arch.rock
		if ! download "$url" "$file"; then
			fail "$rock $key: $url does not answer"
			continue
		fi
		if [ "$(sha256sum < "$file" | cut -d' ' -f1)" != "$sha" ]; then
			fail "$rock $key: the sha256 of $url is not that of the index"
		fi
		if [ "$size" != null ] && [ "$(wc -c < "$file")" != "$size" ]; then
			fail "$rock $key: the size of $url is $(wc -c < "$file"), the index says $size"
		fi
		if ! unzip -p "$file" "$rock-$key.rockspec" > "$work/inner" 2> /dev/null; then
			fail "$rock $key: $url holds no $rock-$key.rockspec"
		elif ! cmp -s "$work/inner" "$spec"; then
			fail "$rock $key: the rockspec in $url differs from the rockspec of the entry"
		fi
		rm -f "$file" "$work/inner"
		checked=$((checked + 1))
	done < <(jq -r '.artifacts[] | "\(.arch) \(.url) \(.sha256) \(.size // "null")"' <<<"$entry")
	rm -f "$spec"
done <<<"$entries"

# What the publish workflow has yet to add.
for rock in $(rocks); do
	for version in $(versions "$rock"); do
		key=$version-$(revision "$rock" "$version")
		index_has "$index" "$rock" "$key" ||
			notice "$rock $key of $rock/releases.json is not in the index yet: the publish workflow adds it"
	done
done

if [ "$errors" -gt 0 ]; then
	die "$errors problems"
fi
say "the index is good: $(grep -c . <<<"$entries" || true) versions, $checked rocks"
