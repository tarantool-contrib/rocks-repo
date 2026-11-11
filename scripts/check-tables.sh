#!/usr/bin/env bash
# Check the tables, and the descriptions and targets of the packages: each
# entry is well formed, and, when BASE (a git commit
# of this repository) is given, no version-revision the index FILE has is
# changed from what BASE holds: a published release never changes, so a
# new build of a version is a new rock_revision.
#
# Usage: scripts/check-tables.sh FILE [BASE]
# shellcheck disable=SC2016 # The jq programs are in single quotes.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# = 1 ] || [ $# = 2 ] || die "usage: check-tables.sh FILE [BASE]"
index=$1
base=${2:-}

problems=()

# check TABLE FILTER adds the messages FILTER prints for the table.
check() {
	local out
	out=$(jq -r "$2" "$1") || die "$1 is not JSON"
	if [ -n "$out" ]; then
		mapfile -t -O "${#problems[@]}" problems <<<"$out"
	fi
}

common='
	def hex($n): type == "string" and test("^[0-9a-f]{\($n)}$");
	def str: type == "string" and length > 0;
	if type != "object" then "not an object of versions" else
	to_entries[] | .key as $v | .value as $e | "\($v)" as $at
	| (if ($v | test("^[0-9][0-9A-Za-z.]*$")) then empty
	   else "\($at): a version is digits, letters and dots" end),
	  (if $e.version == $v then empty else "\($at): version is \($e.version)" end),
	  (if ($e.rock_revision | type) == "number" and $e.rock_revision >= 1
	      and ($e.rock_revision | floor) == $e.rock_revision then empty
	   else "\($at): rock_revision is no positive integer" end),
'

check "$root/wasm/releases.json" "$common"'
	  (if ($e.sdk_asset | str) and ($e.sdk_md5 | hex(32)) then empty
	   else "\($at): no sdk_asset and sdk_md5" end),
	  (if ($e.platforms // []) == [] then
		(if ($e.ref | str) then empty else "\($at): no platforms and no ref to build" end)
	   else
		($e.platforms[] | select(
			([.goos, .goarch, .asset, .rock_arch, .module] | all(str) | not)
			or (.sha256 | hex(64) | not))
		 | "\($at): the platform \(.rock_arch) lacks a field")
	   end)
	end | "wasm/releases.json: " + .'

check "$root/emmylua/releases.json" "$common"'
	  (if ($e.ref | str) and ($e.source_md5 | hex(32)) then empty
	   else "\($at): no ref and source_md5" end),
	  ($e.platforms // [] | .[] | select(
		([.goos, .goarch, .suffix] | all(str) | not)
		or ([.sha256.emmylua_check, .sha256.emmylua_doc_cli, .sha256.emmylua_ls,
		     .sha256.luafmt] | all(hex(64)) | not))
	   | "\($at): the platform \(.suffix) lacks a field")
	end | "emmylua/releases.json: " + .'

check "$root/emmylua/targets.json" '
	def str: type == "string" and length > 0;
	(if (.rust | str) then empty else "no rust" end),
	(if (.targets | type) == "array" and (.targets | length) > 0 then
		(.targets[] | select(([.arch, .os, .target] | all(str) | not) or (.glibc | type) != "string")
		 | "the target \(.arch) lacks a field")
	 else "no targets" end)
	| "emmylua/targets.json: " + .'

check "$root/wasm/targets.json" '
	def str: type == "string" and length > 0;
	if (.targets | type) == "array" and (.targets | length) > 0 then
		(.targets[] | select(([.arch, .os, .module] | all(str) | not)
			or ([.container, .target] | all(type == "string") | not))
		 | "the target \(.arch) lacks a field")
	else "no targets" end
	| "wasm/targets.json: " + .'

# The archs are those tt packs and the index names.
for rock in wasm emmylua; do
	bad=$(jq -r '.targets[].arch | select(test("^(linux|macosx)-(x86_64|aarch64)$") | not)' \
		"$root/$rock/targets.json")
	[ -z "$bad" ] || problems+=("$rock/targets.json: no such arch: $bad")
done

# Every other rock is a package: its table names the ref of each version,
# package.json the repository and the Tarantool its builds use, and
# targets.json the archs, or the one arch all of a package with no native
# file.
for rock in $(rocks); do
	case $rock in
	wasm | emmylua)
		[ ! -e "$root/$rock/package.json" ] ||
			problems+=("$rock/package.json: $rock is packed by tt $rock rock, not a package")
		continue
		;;
	esac
	if [ ! -f "$root/$rock/package.json" ]; then
		problems+=("$rock: no package.json: a rock here is wasm, emmylua or a tt package")
		continue
	fi
	[[ $rock =~ ^[a-z][a-z0-9-]*$ ]] ||
		problems+=("$rock: not the name of a tt package: lowercase letters, digits and dashes, from a letter")

	check "$root/$rock/releases.json" "$common"'
		  (if ($e.ref | str) then empty else "\($at): no ref to build" end),
		  (($e | keys) - ["version", "rock_revision", "ref"] | .[] | "\($at): no such field: \(.)")
		end | "'"$rock"'/releases.json: " + .'

	check "$root/$rock/package.json" '
		def relpath: type == "string" and test("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$")
			and (split("/") | all(. != "." and . != ".."));
		if type != "object" then "not an object" else
		(if (.repository | type) == "string"
			and (.repository | test("^https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))
			and (.repository | test("\\.git$") | not) then empty
		 else "repository is not https://github.com/OWNER/NAME" end),
		(if .path == null or (.path | relpath) then empty
		 else "path is not a relative path in the repository" end),
		(if (.tarantool | type) == "string" and (.tarantool | test("^[0-9]+([.][0-9]+){0,2}$")) then empty
		 else "tarantool is not a Tarantool release such as 3, 3.5 or 3.5.1" end),
		(if .source_rock == null or (.source_rock | type) == "boolean" then empty
		 else "source_rock is no boolean" end),
		(keys - ["repository", "path", "tarantool", "source_rock"] | .[] | "no such field: \(.)")
		end | "'"$rock"'/package.json: " + .'

	check "$root/$rock/targets.json" '
		def str: type == "string" and length > 0;
		if type != "object" then "not an object"
		elif (.targets | type) == "array" and (.targets | length) > 0 then
			(.targets[] | select(([.arch, .os] | all(str) | not) or (.container | type) != "string")
			 | "the target \(.arch) lacks a field"),
			(.targets[] | (keys - ["arch", "os", "container"] | .[]) as $k
			 | "the target \(.arch) has no such field: \($k)"),
			(.targets[].arch | select(type == "string")
			 | select(test("^((linux|macosx)-(x86_64|aarch64)|all)$") | not)
			 | "no such arch: \(.)"),
			(if ([.targets[].arch] | unique | length) == (.targets | length) then empty
			 else "an arch is listed twice" end),
			(if ([.targets[].arch] | index("all")) == null or (.targets | length) == 1 then empty
			 else "a target of the arch all is the only one" end),
			(keys - ["targets"] | .[] | "no such field: \(.)")
		else "no targets" end
		| "'"$rock"'/targets.json: " + .'
done

# Against BASE: an indexed version-revision is as BASE has it.
if [ -n "$base" ]; then
	for rock in $(rocks); do
		old=$(git -C "$root" show "$base:$rock/releases.json" 2> /dev/null || echo '{}')
		while read -r version; do
			[ -n "$version" ] || continue
			key=$version-$(jq -r --arg v "$version" '.[$v].rock_revision' <<<"$old")
			index_has "$index" "$rock" "$key" || continue
			if ! jq -e --arg v "$version" --argjson old "$old" '
				.[$v] == null or .[$v].rock_revision != $old[$v].rock_revision
				or .[$v] == $old[$v]' "$(table "$rock")" > /dev/null; then
				problems+=("$rock/releases.json: $version: $rock $key is published; publish the change as a new rock_revision")
			fi
		done < <(jq -r 'keys[]' <<<"$old")
	done
fi

if [ ${#problems[@]} -gt 0 ]; then
	for problem in "${problems[@]}"; do
		if [ -n "${GITHUB_ACTIONS:-}" ]; then
			printf '::error::%s\n' "$problem"
		else
			printf 'error: %s\n' "$problem" >&2
		fi
	done
	die "${#problems[@]} problems"
fi
say "the tables are good"
