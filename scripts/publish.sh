#!/usr/bin/env bash
# Publish VERSION of ROCK as the release ROCK-VERSION-REVISION, REVISION
# being its rock_revision in ROCK/releases.json: pack its rocks with tt,
# create the release as a draft, upload the rocks and the rockspec, check
# what GitHub holds, publish.
#
# Usage: scripts/publish.sh [--pack-only] ROCK VERSION [BUILDS]
#
# BUILDS holds the builds of a version built from source, a tar per target,
# as the build jobs of the publish workflow leave them:
# BUILDS/ROCK-VERSION-ARCH.tar, of the four programs for emmylua, of the one
# module for wasm.
#
# --pack-only packs and checks the rocks and stops: nothing is published.
#
# A published release is never changed: if it is there, it is only checked
# to have the assets it should, and indexing it is left to
# scripts/index-push.sh. A draft is what a failed run left: it is deleted
# and the release made anew.
#
# $TT, default tt, packs the rocks: tt wasm rock and tt emmylua rock, with
# the tables of this repository.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

pack_only=false
if [ "${1:-}" = --pack-only ]; then
	pack_only=true
	shift
fi
[ $# = 2 ] || [ $# = 3 ] || die "usage: publish.sh [--pack-only] ROCK VERSION [BUILDS]"
rock=$1
version=$2
builds=${3:-}
tt=${TT:-tt}

export TT_WASM_RELEASES=$root/wasm/releases.json
export TT_EMMYLUA_RELEASES=$root/emmylua/releases.json

revision=$(revision "$rock" "$version")
tag=$(tag "$rock" "$version" "$revision")
mapfile -t archs < <(archs "$rock" "$version")
[ ${#archs[@]} -gt 0 ] || die "$rock $version has no platforms"

# The assets of the release, sorted: a rock for each arch and the rockspec.
expected=$(
	for arch in "${archs[@]}"; do
		echo "$tag.$arch.rock"
	done | sort
	echo "$tag.rockspec"
)
expected=$(sort <<<"$expected")

state=none
if ! $pack_only; then
	state=$(release_state "$tag")
fi
if [ "$state" = published ]; then
	have=$(gh release view "$tag" --json assets --jq '.assets[].name' | sort)
	if [ "$have" != "$expected" ]; then
		die "$tag is published with the assets"$'\n'"$have"$'\n'"rather than"$'\n'"$expected"$'\n'"A published release never changes: publish a new rock_revision of $rock $version."
	fi
	say "$tag is published"
	exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pack=$work/pack
dist=$work/dist
mkdir -p "$pack" "$dist"

if from_source "$rock" "$version"; then
	[ -n "$builds" ] || die "$rock $version is built from source: name the directory of the builds"
	for arch in "${archs[@]}"; do
		build=$builds/$rock-$version-$arch.tar
		[ -f "$build" ] || die "no build of $rock $version for $arch: $build"
		mkdir -p "$work/build/$arch"
		tar -xf "$build" -C "$work/build/$arch"
		case $rock in
		emmylua)
			# The directory of the programs.
			from=$work/build/$arch
			;;
		wasm)
			# The module, the one file of the build.
			mapfile -t files < <(find "$work/build/$arch" -type f)
			[ ${#files[@]} = 1 ] || die "the build $build is not one module"
			from=${files[0]}
			;;
		*)
			die "unknown rock: $rock"
			;;
		esac
		"$tt" "$rock" rock --version "$version" --arch "$arch" --from "$from" --out "$pack"
	done
else
	"$tt" "$rock" rock --version "$version" --out "$pack"
fi

# Take the rock of each arch; tt writes manifests too, which the index
# stands for.
for arch in "${archs[@]}"; do
	[ -f "$pack/$tag.$arch.rock" ] || die "tt packed no $tag.$arch.rock"
	cp "$pack/$tag.$arch.rock" "$dist/"
done
for file in "$pack"/*.rock; do
	[ -f "$dist/${file##*/}" ] || die "tt packed ${file##*/}, which $rock/releases.json does not name"
done

# The rockspec is the one the rocks hold, the same in each.
unzip -p "$dist/$tag.${archs[0]}.rock" "$tag.rockspec" > "$dist/$tag.rockspec"
for arch in "${archs[@]}"; do
	unzip -p "$dist/$tag.$arch.rock" "$tag.rockspec" | cmp -s - "$dist/$tag.rockspec" ||
		die "the rockspec of $tag.$arch.rock differs from that of $tag.${archs[0]}.rock"
done
grep -qxF "package = \"$rock\"" "$dist/$tag.rockspec" ||
	die "$tag.rockspec is not of the package $rock"
grep -qxF "version = \"$version-$revision\"" "$dist/$tag.rockspec" ||
	die "$tag.rockspec is not of the version $version-$revision"

(cd "$dist" && sha256sum -- *) > "$work/sha256"
if $pack_only; then
	say "$tag would be published with:"
	cat "$work/sha256" >&2
	exit 0
fi

# A draft is left by a failed run, which may have uploaded only some of the
# assets: start again. There may be several drafts of a tag.
for _ in 1 2 3 4 5; do
	[ "$state" = draft ] || break
	say "$tag: deleting the draft a failed run left"
	gh release delete "$tag" --yes
	sleep 2
	state=$(release_state "$tag")
done
case $state in
none) ;;
draft) die "$tag: the drafts do not go away" ;;
*) die "$tag got $state while this run packed it" ;;
esac

# The notes say where the rocks come from.
repo=${GH_REPO:-}
commit=${GITHUB_SHA:-$(git -C "$root" rev-parse HEAD 2> /dev/null || true)}
notes=$work/notes
{
	echo "\`$rock\` $version-$revision: binary rocks for tt 3, one per platform."
	echo
	if from_source "$rock" "$version"; then
		ref=$(jq -r --arg v "$version" '.[$v].ref' "$(table "$rock")")
		rust=$(jq -r '.rust // empty' "$root/$rock/targets.json")
		echo "Built from [$(upstream "$rock")@$ref](https://github.com/$(upstream "$rock")/tree/$ref)"
		echo "${rust:+with Rust $rust }for the targets of \`$rock/targets.json\` by the publish"
		echo "workflow, and packed by \`tt $rock rock --from\`."
	else
		echo "Packed by \`tt $rock rock\` from the assets of the upstream release, each"
		echo "checked against the sha256 \`$rock/releases.json\` holds it to."
	fi
	echo
	if [ -n "$repo" ] && [ -n "$commit" ]; then
		echo "- Tables: https://github.com/$repo/tree/$commit"
	fi
	if [ -n "${GITHUB_RUN_ID:-}" ]; then
		echo "- Run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-$repo}/actions/runs/$GITHUB_RUN_ID"
	fi
	if [ -n "${TT_COMMIT:-}" ]; then
		echo "- tt: https://github.com/tarantool/tt/tree/$TT_COMMIT"
	fi
	if [ -n "$repo" ]; then
		echo "- Index: https://raw.githubusercontent.com/$repo/index/tt-rocks-index.json"
	fi
	echo
	echo "| Asset | sha256 |"
	echo "| --- | --- |"
	awk '{print "| `" $2 "` | `" $1 "` |"}' "$work/sha256"
} > "$notes"

target=()
if [ -n "$commit" ]; then
	target=(--target "$commit")
fi

gh release create "$tag" --draft --latest=false --title "$rock $version-$revision" \
	--notes-file "$notes" "${target[@]}" > /dev/null
gh release upload "$tag" "$dist"/*

# The draft holds what was packed, byte for byte, by the digests of GitHub.
have=$(gh release view "$tag" --json assets \
	--jq '.assets[] | "\(.digest // "none" | sub("^sha256:"; ""))  \(.name)"' | sort -k2)
want=$(sort -k2 "$work/sha256")
if [ "$have" != "$want" ]; then
	die "the draft $tag holds"$'\n'"$have"$'\n'"rather than"$'\n'"$want"
fi

gh release edit "$tag" --draft=false --latest=false > /dev/null

view=$(gh release view "$tag" --json isDraft,isImmutable)
[ "$(jq -r .isDraft <<<"$view")" = false ] || die "$tag is still a draft"
if [ "$(jq -r .isImmutable <<<"$view")" != true ]; then
	say "warning: $tag is published, but not immutable: enable immutable releases"
fi
say "$tag is published"
