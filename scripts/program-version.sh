#!/usr/bin/env bash
# Print the version the programs of an EmmyLua build report: VERSION, the
# version of the rock, as the semver Cargo takes, with the commit the build
# is of as build metadata.
#
#   0.30.0pre1 599c33862491… → 0.30.0-pre1+599c338
#   0.31.0     a1b2c3d4e5f6… → 0.31.0+a1b2c3d
#
# Usage: scripts/program-version.sh VERSION COMMIT
#
# A LuaRocks version puts a prerelease right after the patch (0.30.0pre1):
# a dash there would start the revision of the rock. Cargo wants semver,
# where the dash is what starts a prerelease, so it goes in. Build metadata
# does not change how versions sort.
source "$(dirname "$0")/lib.sh"

[ $# = 2 ] || die "usage: program-version.sh VERSION COMMIT"
version=$1
commit=$2

[[ $commit =~ ^[0-9a-f]{40}$ ]] || die "not a full commit hash: $commit"
[[ $version =~ ^([0-9]+\.[0-9]+\.[0-9]+)([A-Za-z][0-9A-Za-z]*)?$ ]] ||
	die "$version is not MAJOR.MINOR.PATCH with an optional prerelease such as pre1"

semver=${BASH_REMATCH[1]}
if [ -n "${BASH_REMATCH[2]}" ]; then
	semver+=-${BASH_REMATCH[2]}
fi

echo "$semver+${commit:0:7}"
