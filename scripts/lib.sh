# shellcheck shell=bash
# What the scripts share; they source it.
#
# A table, ROCK/releases.json, holds the versions of ROCK by version: for
# wasm and emmylua in the format tt reads from TT_<ROCK>_RELEASES, for a
# package (a tt package, ROCK/package.json describing it) the ref of its
# repository each version is built from. A version is published as the
# release ROCK-VERSION-REVISION, REVISION being its rock_revision: a rock
# for each of its archs, ROCK-VERSION-REVISION.ARCH.rock, and the rockspec,
# ROCK-VERSION-REVISION.rockspec. The branch index holds
# tt-rocks-index.json, which lists the published releases.
#
# The scripts run gh against $GH_REPO, and git against $ROCKS_REMOTE,
# default the repository $GH_REPO on GitHub, authorized with $GH_TOKEN.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# The name and the address the commits of the workflows are made by.
# shellcheck disable=SC2034 # The scripts that source this use them.
bot_name='github-actions[bot]'
# shellcheck disable=SC2034
bot_email='41898282+github-actions[bot]@users.noreply.github.com'

# die MESSAGE reports MESSAGE and exits.
die() {
	printf '%s: %s\n' "${0##*/}" "$*" >&2
	exit 1
}

# say MESSAGE reports MESSAGE.
say() {
	printf '%s\n' "$*" >&2
}

# rocks prints the rocks of the repository, one per line: the directories
# with a releases.json.
rocks() {
	local file
	for file in "$root"/*/releases.json; do
		[ -e "$file" ] || continue
		file=${file%/releases.json}
		printf '%s\n' "${file##*/}"
	done
}

# table ROCK prints the path of the table of ROCK.
table() {
	local file=$root/$1/releases.json
	[ -f "$file" ] || die "unknown rock: $1"
	printf '%s\n' "$file"
}

# versions ROCK prints the versions of the table of ROCK, one per line.
versions() {
	jq -r 'keys[]' "$(table "$1")"
}

# revision ROCK VERSION prints the rock_revision of VERSION.
revision() {
	jq -er --arg v "$2" '.[$v].rock_revision // empty' "$(table "$1")" ||
		die "$1/releases.json has no rock_revision of $2"
}

# tag ROCK VERSION REVISION prints the tag of the release of the rock.
tag() {
	printf '%s-%s-%s\n' "$1" "$2" "$3"
}

# kind ROCK prints the kind of ROCK: package for a tt package, which
# ROCK/package.json describes and tt package pack packs, or wasm or emmylua,
# which tt wasm rock and tt emmylua rock pack.
kind() {
	if [ -f "$root/$1/package.json" ]; then
		echo package
		return
	fi
	case $1 in
	wasm | emmylua) echo "$1" ;;
	*) die "unknown rock: $1" ;;
	esac
}

# package ROCK FIELD prints FIELD of ROCK/package.json, empty when it has
# none.
package() {
	jq -r --arg f "$2" '.[$f] // "" | tostring' "$root/$1/package.json"
}

# source_rock ROCK succeeds when the package ROCK publishes its source rock
# too.
source_rock() {
	[ "$(kind "$1")" = package ] &&
		jq -e '.source_rock == true' "$root/$1/package.json" > /dev/null
}

# project ROCK CHECKOUT prints the directory of the project of the package
# ROCK in CHECKOUT, a checkout of its repository: CHECKOUT/PATH, PATH being
# that of ROCK/package.json, or CHECKOUT.
project() {
	local path
	path=$(package "$1" path)
	printf '%s\n' "$2${path:+/$path}"
}

# upstream ROCK prints the GitHub repository ROCK is built or packed from.
upstream() {
	case $(kind "$1") in
	wasm) echo tarantool/tarantool-wasm-rs ;;
	emmylua) echo EmmyLuaLs/emmylua-analyzer-rust ;;
	package)
		local url
		url=$(package "$1" repository)
		[[ $url =~ ^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$ ]] ||
			die "$1/package.json: the repository $url is not https://github.com/OWNER/NAME"
		echo "${BASH_REMATCH[1]}"
		;;
	esac
}

# from_source ROCK VERSION succeeds when VERSION is built here from the
# source at its ref, for each target of ROCK/targets.json, rather than
# packed from the assets of an upstream release: a version without
# platforms, and every version of a package.
from_source() {
	jq -e --arg v "$2" '(.[$v].platforms // []) == []' "$(table "$1")" > /dev/null
}

# archs ROCK VERSION prints the LuaRocks archs VERSION has rocks for, one
# per line, sorted: those of its targets when it is built from source, of
# its platforms otherwise. The rock of a target of arch all is the .all rock
# of a package with no native file; a package publishing its source rock
# has one of arch src too.
archs() {
	local file
	file=$(table "$1")
	if from_source "$1" "$2"; then
		jq -r '.targets[].arch' "$root/$1/targets.json"
		if source_rock "$1"; then
			echo src
		fi
	else
		jq -r --arg v "$2" '.[$v].platforms[]
			| .rock_arch // (({linux: "linux", darwin: "macosx"}[.goos] // .goos) + "-"
				+ ({amd64: "x86_64", arm64: "aarch64"}[.goarch] // .goarch))' "$file"
	fi | sort
}

# split_tag TAG prints "ROCK KEY" of a release tag, KEY being
# VERSION-REVISION, and fails for a tag of no rock of the repository.
split_tag() {
	local rock key
	for rock in $(rocks); do
		key=${1#"$rock"-}
		if [ "$key" != "$1" ] && [[ $key =~ ^[0-9][^-]*-[0-9]+$ ]]; then
			printf '%s %s\n' "$rock" "$key"
			return 0
		fi
	done
	return 1
}

# release_state TAG prints the state of the release TAG: none, draft or
# published. A token without push access sees no drafts: none.
release_state() {
	local out
	if out=$(gh release view "$1" --json isDraft --jq .isDraft 2>&1); then
		case $out in
		true) echo draft ;;
		false) echo published ;;
		*) die "gh release view $1: $out" ;;
		esac
	elif [[ $out == *"release not found"* ]]; then
		echo none
	else
		die "gh release view $1: $out"
	fi
}

# empty_index prints the index of no releases.
empty_index() {
	jq -n '{format: 1, repository: {}}'
}

# index_has FILE ROCK KEY succeeds when the index FILE has the
# version-revision KEY of ROCK.
index_has() {
	jq -e --arg r "$2" --arg k "$3" '.repository[$r][$k] != null' "$1" > /dev/null
}

# remote prints the git remote of the repository.
remote() {
	printf '%s\n' "${ROCKS_REMOTE:-https://github.com/${GH_REPO:?GH_REPO names the repository}.git}"
}

# rgit runs git with the remote authorized by $GH_TOKEN, the way
# actions/checkout does it, without writing the token anywhere.
rgit() {
	if [ -n "${GH_TOKEN:-}" ] && [[ $(remote) == https://github.com/* ]]; then
		local auth
		auth=$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')
		GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.https://github.com/.extraheader \
			GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $auth" git "$@"
	else
		git "$@"
	fi
}

# index_checkout DIR makes DIR a work tree of the branch index of the
# remote, on the branch index, or, when the remote has no such branch yet, a
# repository whose first commit is to make it, with an empty index.
index_checkout() {
	local dir=$1 rc=0
	git init -q -b index "$dir"
	rgit ls-remote --exit-code "$(remote)" refs/heads/index > /dev/null || rc=$?
	case $rc in
	0)
		rgit -C "$dir" fetch -q --depth=1 "$(remote)" refs/heads/index
		git -C "$dir" reset -q --hard FETCH_HEAD
		;;
	2)
		empty_index > "$dir/tt-rocks-index.json"
		;;
	*)
		die "reading the branch index of $(remote)"
		;;
	esac
	jq -e '.format == 1' "$dir/tt-rocks-index.json" > /dev/null ||
		die "tt-rocks-index.json of the branch index is not of format 1"
}
