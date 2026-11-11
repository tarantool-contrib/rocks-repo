#!/usr/bin/env bash
# Print the entry of ROCK/releases.json for a version, for scripts/add.sh to
# add.
#
# Usage:
#   scripts/entry.sh wasm VERSION         tarantool-wasm-rs at the tag
#                                         vVERSION, built from source here
#   scripts/entry.sh emmylua VERSION      EmmyLua release VERSION, packed
#                                         from its assets
#   scripts/entry.sh emmylua VERSION REF  EmmyLua at REF, built from source
#                                         here and published as VERSION
#   scripts/entry.sh PACKAGE VERSION      a tt package at the tag vVERSION
#                                         of its repository, built here
#   scripts/entry.sh PACKAGE VERSION REF  a tt package at REF, built here
#                                         and published as VERSION
#
# A version packed from upstream assets lists them by platform with the
# sha256 GitHub publishes for them; one built from source names the ref
# instead, and is built for the targets of ROCK/targets.json. The source of
# a rockspec is what the lock of a project records the md5 of; nothing
# installs from it. For wasm it is the SDK archive of the release, for
# EmmyLua the GitHub archive of the ref. tt package pack writes the
# rockspec of a package, and names its version: the tag v* at the ref, as a
# LuaRocks version (v1.2.0-rc1 is 1.2.0.rc1), or the VERSION file; a build
# of another version than VERSION fails.
set -euo pipefail

rock=$1
version=$2
ref=${3:-}
root=$(cd "$(dirname "$0")/.." && pwd)

if [ -f "$root/$rock/package.json" ]; then
	if [ -z "$ref" ]; then
		ref=v$version
		url=$(jq -r .repository "$root/$rock/package.json")
		git ls-remote --exit-code --tags "$url" "refs/tags/$ref" > /dev/null ||
			{ echo "$url has no tag $ref" >&2; exit 1; }
	fi
	jq -n --arg v "$version" --arg ref "$ref" \
		'{($v): {version: $v, rock_revision: 1, ref: $ref}}'
	exit 0
fi

md5() {
	curl -sSfL "$1" | md5sum | cut -d' ' -f1
}

# digest ASSETS NAME prints the sha256 of the asset NAME.
digest() {
	jq -er --arg name "$2" '.[] | select(.name == $name) | .digest | sub("^sha256:"; "")' <<<"$1"
}

case $rock in
wasm)
	repo=tarantool/tarantool-wasm-rs
	assets=$(gh release view "v$version" -R "$repo" --json assets --jq .assets)
	sdk=tarantool-wasm-$version-sdk.tar.gz
	digest "$assets" "$sdk" > /dev/null ||
		{ echo "v$version has no $sdk" >&2; exit 1; }
	jq -n --arg v "$version" --arg sdk "$sdk" \
		--arg md5 "$(md5 "https://github.com/$repo/releases/download/v$version/$sdk")" \
		'{($v): {version: $v, rock_revision: 1, ref: "v\($v)", sdk_asset: $sdk, sdk_md5: $md5}}'
	;;
emmylua)
	repo=EmmyLuaLs/emmylua-analyzer-rust
	source_md5=$(md5 "https://github.com/$repo/archive/${ref:-$version}.tar.gz")
	if [ -n "$ref" ]; then
		jq -n --arg v "$version" --arg ref "$ref" --arg md5 "$source_md5" \
			'{($v): {version: $v, rock_revision: 1, ref: $ref, source_md5: $md5}}'
		exit 0
	fi
	assets=$(gh release view "$version" -R "$repo" --json assets --jq .assets)
	platforms=()
	# linux-x86_64, linux-aarch64 and macosx-aarch64.
	for platform in linux:amd64:linux-x64-glibc.2.17 linux:arm64:linux-aarch64-glibc.2.17 \
		darwin:arm64:darwin-arm64; do
		IFS=: read -r goos goarch suffix <<<"$platform"
		sums=()
		for program in emmylua_check emmylua_doc_cli emmylua_ls luafmt; do
			sum=$(digest "$assets" "$program-$suffix.tar.gz") ||
				{ echo "$version has no sha256 of $program-$suffix.tar.gz" >&2; exit 1; }
			sums+=(--arg "$program" "$sum")
		done
		platforms+=("$(jq -nc --arg goos "$goos" --arg goarch "$goarch" --arg suffix "$suffix" \
			"${sums[@]}" '{goos: $goos, goarch: $goarch, suffix: $suffix, sha256: {
				emmylua_check: $emmylua_check, emmylua_doc_cli: $emmylua_doc_cli,
				emmylua_ls: $emmylua_ls, luafmt: $luafmt}}')")
	done
	printf '%s\n' "${platforms[@]}" | jq -s --arg v "$version" --arg md5 "$source_md5" \
		'{($v): {version: $v, rock_revision: 1, ref: $v, source_md5: $md5, platforms: .}}'
	;;
*)
	echo "unknown rock: $rock" >&2
	exit 2
	;;
esac
