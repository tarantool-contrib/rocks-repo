#!/usr/bin/env bash
# Print, as JSON, what the publish workflow has to do: the version-revisions
# of the tables the index FILE lacks, and the builds from source they need.
#
# Usage: scripts/plan.sh FILE
#
#   {
#     "publish": [{"rock": "emmylua", "version": "0.30.0pre1", "revision": 1,
#                  "tag": "emmylua-0.30.0pre1-1", "release": "none",
#                  "source": true}],
#     "builds": [{"rock": "emmylua", "version": "0.30.0pre1", "ref": "599c…",
#                 "arch": "linux-x86_64", "os": "ubuntu-22.04",
#                 "target": "x86_64-unknown-linux-gnu", "glibc": "2.17",
#                 "rust": "1.99.1"}]
#   }
#
# release is the state of the release of the tag: none, draft (a failed
# run left it; seen only with push access) or published (its entry is
# missing: it needs indexing alone). A version built from source needs a
# build of each target of ROCK/targets.json unless its release is
# published: a build is the target, the other fields of targets.json, and
# the rock, version and ref. What is to be done is also reported on stderr.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# = 1 ] || die "usage: plan.sh FILE"
index=$1
jq -e '.format == 1' "$index" > /dev/null || die "$index is not an index of format 1"

items=()
for rock in $(rocks); do
	for version in $(versions "$rock"); do
		revision=$(revision "$rock" "$version")
		tag=$(tag "$rock" "$version" "$revision")
		if index_has "$index" "$rock" "$version-$revision"; then
			continue
		fi
		state=$(release_state "$tag")
		source=false
		if from_source "$rock" "$version"; then
			source=true
		fi
		case $state in
		published) say "$tag: published, not indexed: index it" ;;
		draft) say "$tag: a draft: delete it and publish anew" ;;
		*) say "$tag: publish it" ;;
		esac
		items+=("$(jq -nc --arg rock "$rock" --arg version "$version" \
			--argjson revision "$revision" --arg tag "$tag" --arg state "$state" \
			--argjson source "$source" '{rock: $rock, version: $version,
				revision: $revision, tag: $tag, release: $state, source: $source}')")
	done
done

if [ ${#items[@]} = 0 ]; then
	say "the index has every version of the tables"
fi

builds=()
for item in "${items[@]}"; do
	jq -e '.source and .release != "published"' <<<"$item" > /dev/null || continue
	read -r rock version < <(jq -r '"\(.rock) \(.version)"' <<<"$item")
	ref=$(jq -r --arg v "$version" '.[$v].ref' "$(table "$rock")")
	builds+=("$(jq -c --arg rock "$rock" --arg version "$version" --arg ref "$ref" '
		del(.targets) as $common
		| .targets[] | $common + . + {rock: $rock, version: $version, ref: $ref}
	' "$root/$rock/targets.json")")
done

jq -n --slurpfile publish <(printf '%s\n' "${items[@]}") \
	--slurpfile builds <(printf '%s\n' "${builds[@]}") \
	'{publish: $publish, builds: $builds}'
