#!/usr/bin/env bash
# Pack the rock of arch ARCH of VERSION of the package ROCK from CHECKOUT, a
# checkout of its repository at the ref of VERSION, into OUT/TAG.ARCH/: the
# rock TAG.ARCH.rock and the rockspec TAG.rockspec, as tt package pack
# writes them, TAG being ROCK-VERSION-REVISION.
#
# Usage: scripts/pack-package.sh ROCK VERSION ARCH CHECKOUT OUT
#
# The build jobs of the publish workflow run it. The project is
# CHECKOUT/PATH, PATH being that of ROCK/package.json; tt package pack
# builds it and packs the rock with --format rock, or the source rock with
# --format rock-src for the arch src, and --revision the rock_revision of
# VERSION. The rock tt makes has to be the one the tables name: tt names it
# by the version of the package, from its tag v* at the ref or its VERSION
# file, and by the arch of the host, or all for a package with no native
# file. Another version (the tag is not that of VERSION, the tree is dirty)
# or another arch (targets.json says all of a package with a native file,
# say) fails.
#
# $TT, default tt, packs.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# = 5 ] || die "usage: pack-package.sh ROCK VERSION ARCH CHECKOUT OUT"
rock=$1
version=$2
arch=$3
checkout=$4
out=$5
tt=${TT:-tt}

[ "$(kind "$rock")" = package ] || die "$rock is not a package"
revision=$(revision "$rock" "$version")
tag=$(tag "$rock" "$version" "$revision")
archs "$rock" "$version" | grep -qxF "$arch" ||
	die "$rock $version has no rock of the arch $arch"

project=$checkout
path=$(package "$rock" path)
if [ -n "$path" ]; then
	project=$checkout/$path
fi
[ -f "$project/app.manifest.toml" ] || die "$project has no app.manifest.toml"

format=rock
if [ "$arch" = src ]; then
	format="rock-src"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

(cd "$project" && "$tt" package pack --format "$format" --revision "$revision" --out "$work/pack") >&2

# tt indexes the directory too: the manifests are left out, the index stands
# for them.
made=$(cd "$work/pack" && find . -mindepth 1 -maxdepth 1 ! -name 'manifest*' | sed 's|^\./||' | sort)
want=$(printf '%s\n' "$tag.$arch.rock" "$tag.rockspec" | sort)
if [ "$made" != "$want" ]; then
	ref=$(jq -r --arg v "$version" '.[$v].ref' "$(table "$rock")")
	die "tt packed"$'\n'"$made"$'\n'"rather than"$'\n'"$want"$'\n'"The package at $ref, of a clean tree, is to be of the version $version, and its rock of the arch $arch."
fi
unzip -p "$work/pack/$tag.$arch.rock" "$tag.rockspec" | cmp -s - "$work/pack/$tag.rockspec" ||
	die "the rockspec in $tag.$arch.rock is not the $tag.rockspec tt wrote beside it"

mkdir -p "$out/$tag.$arch"
cp "$work/pack/$tag.$arch.rock" "$work/pack/$tag.rockspec" "$out/$tag.$arch/"
# macOS has shasum rather than sha256sum.
if command -v sha256sum > /dev/null; then
	(cd "$out/$tag.$arch" && sha256sum -- *) >&2
else
	(cd "$out/$tag.$arch" && shasum -a 256 -- *) >&2
fi
