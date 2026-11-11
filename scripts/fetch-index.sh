#!/usr/bin/env bash
# Write tt-rocks-index.json of the branch index to FILE, or the empty index
# while the repository has no such branch.
#
# Usage: scripts/fetch-index.sh FILE
#
# It reads the branch with git rather than from raw.githubusercontent.com,
# which serves it minutes stale: a run right after a publication would not
# see it.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# = 1 ] || die "usage: fetch-index.sh FILE"
out=$1

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

index_checkout "$work"
cp "$work/tt-rocks-index.json" "$out"
