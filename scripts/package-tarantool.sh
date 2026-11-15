#!/usr/bin/env bash
# Print the Tarantool release the package ROCK is built against: the lower
# bound of [platform].tarantool of its manifest in CHECKOUT, a checkout of
# its repository at the ref of a version, as MAJOR.MINOR.PATCH, or the
# higher one of a dependency on tarantool the rock declares: one of
# [dependencies], or of a component of the product the rock is the release
# of (the product of ROCK/package.json, the default one by default).
#
# Usage: scripts/package-tarantool.sh ROCK CHECKOUT
#
# A module built against the headers of the oldest Tarantool it supports
# loads on the newer ones; built against newer ones, it may not load on the
# older. The constraint is that of LuaRocks, as tt reads it: >= 3.3.0,
# < 4.0.0 and ~> 3.3.0 and = 3.3.0 all give 3.3.0, the highest of several
# lower bounds is the one, and a version of fewer parts is padded with
# zeros (>= 3.3 is 3.3.0). [ce] is the default flavor. A product needing a
# newer Tarantool than the package, a C module of the API of 3.5.0 beside
# Lua that runs on 3.1.0, says so by its dependency on tarantool, which
# tt puts into its rockspec: the rocks of that product are built against
# 3.5.0, those of the others against 3.1.0. It fails for:
#
#   - [ee]: no Enterprise SDK is installed here;
#   - no lower bound (*, < 4.0.0): the rocks are built against the oldest
#     Tarantool a package supports, which it is to declare;
#   - > V: it names no release, the oldest is to be declared by >=;
#   - a lower bound of no release (3.3.0.1, 3.3.0-beta1) or below 3.0.0,
#     which tt does not install;
#   - a product the manifest does not have.
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

path, product = sys.argv[1], sys.argv[2]


def fail(message, where="[platform].tarantool"):
    sys.exit("%s of %s: %s" % (where, path, message))


try:
    with open(path, "rb") as f:
        manifest = tomllib.load(f)
except (OSError, tomllib.TOMLDecodeError) as e:
    sys.exit("reading %s: %s" % (path, e))

space = " \t\n\v\f\r"
token = re.compile(r"[ \t\n\v\f\r]*@?([<>=~!]*)[ \t\n\v\f\r]*([0-9A-Za-z._-]+)[ \t\n\v\f\r,]*")


def release(version, where):
    if not re.fullmatch(r"[0-9]+(\.[0-9]+){0,2}", version):
        fail("the lower bound %s is not a Tarantool release such as 3.3.0" % version, where)
    parts = [int(p) for p in version.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


def bound(declared, where):
    """The lower bound of the constraint declared, None for none."""
    # The flavor suffix, as tt splits it off.
    expr = declared
    if expr.endswith("]"):
        expr, _, flavor = expr[:-1].rpartition("[")
        if flavor == "ee":
            fail("%r is of Tarantool Enterprise, which is not built here: there is no Enterprise SDK"
                 % declared, where)
        if flavor != "ce" or not expr:
            fail("%r has a flavor of neither [ce] nor [ee]" % declared, where)
    rest = expr.strip(space)
    if rest == "*":
        rest = ""
    lower, above = [], []
    while rest:
        m = token.match(rest)
        if not m:
            fail("%r is not a constraint tt reads" % declared, where)
        op, version = m.group(1), m.group(2)
        if op in ("", "=", "==", ">=", "~>"):
            lower.append(version)
        elif op == ">":
            above.append(version)
        elif op not in ("<", "<=", "~=", "!="):
            fail("%r has the unknown operator %r" % (declared, op), where)
        rest = rest[m.end():]
    oldest = max((release(v, where) for v in lower), default=None)
    if any(oldest is None or release(v, where) >= oldest for v in above):
        fail("%r bounds the version from below by >, which names no release: "
             "declare the oldest Tarantool the package supports by >=" % declared, where)
    return oldest


declared = (manifest.get("platform") or {}).get("tarantool")
if not isinstance(declared, str) or not declared.strip():
    fail("there is none: declare the versions of Tarantool the package supports, such as >=3.3.0,<4.0.0")
oldest = bound(declared, "[platform].tarantool")
if oldest is None:
    fail("%r has no lower bound: the rocks are built against the oldest Tarantool "
         "a package supports, so declare it, such as >=3.3.0" % declared)
if oldest < (3, 0, 0):
    fail("%r supports Tarantool %d.%d.%d, older than 3.0.0, the oldest tt installs" % ((declared,) + oldest))

# The components of the product, as tt makes them: every component when
# there is no [products], those of the product named, or of the default.
components = manifest.get("components") or {}
products = manifest.get("products") or {}
if not products:
    if product:
        fail("there is no product %s: the manifest has no [products]" % product, "[products]")
    names = list(components)
else:
    if not product:
        defaults = [n for n, p in products.items() if (p or {}).get("default") is True]
        if len(defaults) != 1:
            fail("no one product is the default", "[products]")
        product = defaults[0]
    if product not in products:
        fail("there is no product %s" % product, "[products]")
    names = (products[product] or {}).get("components") or []

# The dependencies on tarantool the rock declares, of [dependencies] and of
# its components, raise the lower bound.
declarations = [("[dependencies].tarantool", manifest.get("dependencies") or {})]
declarations += [("[components.%s.dependencies].tarantool" % n,
                  (components.get(n) or {}).get("dependencies") or {}) for n in names]
for where, dependencies in declarations:
    dependency = dependencies.get("tarantool")
    if dependency is None:
        continue
    if isinstance(dependency, dict):
        dependency = dependency.get("version", "*")
    if not isinstance(dependency, str):
        fail("is not a constraint", where)
    lower = bound(dependency, where)
    if lower is not None and lower > oldest:
        oldest = lower
print("%d.%d.%d" % oldest)
'

python3 -I -c "$program" "$manifest" "$(package "$rock" product)" || die "$rock: no Tarantool to build against"
