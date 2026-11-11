#!/usr/bin/env bash
# Print the Tarantool release the package ROCK is built against: the lower
# bound of [platform].tarantool of its manifest in CHECKOUT, a checkout of
# its repository at the ref of a version, as MAJOR.MINOR.PATCH.
#
# Usage: scripts/package-tarantool.sh ROCK CHECKOUT
#
# A module built against the headers of the oldest Tarantool it supports
# loads on the newer ones; built against newer ones, it may not load on the
# older. The constraint is that of LuaRocks, as tt reads it: >= 3.3.0,
# < 4.0.0 and ~> 3.3.0 and = 3.3.0 all give 3.3.0, the highest of several
# lower bounds is the one, and a version of fewer parts is padded with
# zeros (>= 3.3 is 3.3.0). [ce] is the default flavor. It fails for:
#
#   - [ee]: no Enterprise SDK is installed here;
#   - no lower bound (*, < 4.0.0): the rocks are built against the oldest
#     Tarantool a package supports, which it is to declare;
#   - > V: it names no release, the oldest is to be declared by >=;
#   - a lower bound of no release (3.3.0.1, 3.3.0-beta1) or below 3.0.0,
#     which tt does not install.
#
# python3 reads the manifest: 3.11 or newer, for tomllib.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# = 2 ] || die "usage: package-tarantool.sh ROCK CHECKOUT"
rock=$1
[ "$(kind "$rock")" = package ] || die "$rock is not a package"
manifest=$(project "$rock" "$2")/app.manifest.toml
[ -f "$manifest" ] || die "$rock: no $manifest"

program='
import re
import sys

try:
    import tomllib
except ImportError:
    sys.exit("python3 has no tomllib: it is to be 3.11 or newer")

path = sys.argv[1]


def fail(message):
    sys.exit("[platform].tarantool of %s: %s" % (path, message))


try:
    with open(path, "rb") as f:
        manifest = tomllib.load(f)
except (OSError, tomllib.TOMLDecodeError) as e:
    sys.exit("reading %s: %s" % (path, e))

declared = (manifest.get("platform") or {}).get("tarantool")
if not isinstance(declared, str) or not declared.strip():
    fail("there is none: declare the versions of Tarantool the package supports, such as >=3.3.0,<4.0.0")

# The flavor suffix, as tt splits it off.
expr = declared
if expr.endswith("]"):
    expr, _, flavor = expr[:-1].rpartition("[")
    if flavor == "ee":
        fail("%r is of Tarantool Enterprise, which is not built here: there is no Enterprise SDK" % declared)
    if flavor != "ce" or not expr:
        fail("%r has a flavor of neither [ce] nor [ee]" % declared)

space = " \t\n\v\f\r"
rest = expr.strip(space)
if rest == "*":
    rest = ""
token = re.compile(r"[ \t\n\v\f\r]*@?([<>=~!]*)[ \t\n\v\f\r]*([0-9A-Za-z._-]+)[ \t\n\v\f\r,]*")
lower, above = [], []
while rest:
    m = token.match(rest)
    if not m:
        fail("%r is not a constraint tt reads" % declared)
    op, version = m.group(1), m.group(2)
    if op in ("", "=", "==", ">=", "~>"):
        lower.append(version)
    elif op == ">":
        above.append(version)
    elif op not in ("<", "<=", "~=", "!="):
        fail("%r has the unknown operator %r" % (declared, op))
    rest = rest[m.end():]


def release(version):
    if not re.fullmatch(r"[0-9]+(\.[0-9]+){0,2}", version):
        fail("the lower bound %s is not a Tarantool release such as 3.3.0" % version)
    parts = [int(p) for p in version.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


oldest = max((release(v) for v in lower), default=None)
if any(oldest is None or release(v) >= oldest for v in above):
    fail("%r bounds the version from below by >, which names no release: "
         "declare the oldest Tarantool the package supports by >=" % declared)
if oldest is None:
    fail("%r has no lower bound: the rocks are built against the oldest Tarantool "
         "a package supports, so declare it, such as >=3.3.0" % declared)
if oldest < (3, 0, 0):
    fail("%r supports Tarantool %d.%d.%d, older than 3.0.0, the oldest tt installs" % ((declared,) + oldest))
print("%d.%d.%d" % oldest)
'

python3 -I -c "$program" "$manifest" || die "$rock: no Tarantool to build against"
