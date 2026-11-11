# rocks-repo

Experimental binary rocks for tt 3, one URL for all of them:

```
https://raw.githubusercontent.com/tarantool-contrib/rocks-repo/index/
```

| Rock | What it is | Table |
| --- | --- | --- |
| `wasm` | The Lua C module of [tarantool-wasm](https://github.com/tarantool/tarantool-wasm-rs): WebAssembly components in Tarantool 3.6 and newer | [`wasm/releases.json`](wasm/releases.json) |
| `emmylua` | The programs of [EmmyLua](https://github.com/EmmyLuaLs/emmylua-analyzer-rust): `emmylua_check`, `emmylua_ls`, `emmylua_doc_cli`, `luafmt`, for `tt emmylua` | [`emmylua/releases.json`](emmylua/releases.json) |

Each version of these has a binary rock for `linux-x86_64`, `linux-aarch64`
and `macosx-aarch64`. Any other rock here is a [package](#packages): a tt
package, built and packed by `tt package pack`. Once published, a rock never
changes; a new build of a version is a new rock revision.

## Using the rocks

Declare a rock with this repository as its registry in `app.manifest.toml`:

```toml
[dependencies]
wasm = { version = "0.1.0", registry = "https://raw.githubusercontent.com/tarantool-contrib/rocks-repo/index/" }

[dev_dependencies]
emmylua = { version = "0.30.0pre1", registry = "https://raw.githubusercontent.com/tarantool-contrib/rocks-repo/index/" }
```

tt reads `tt-rocks-index.json` there, so a tt that knows the index is needed;
`tt rocks` (the LuaRocks of tt) cannot use it. `tt wasm prepare` and
`tt emmylua prepare` are to declare the rocks from here by default.

## Layout

- **`master`**: the tables, `<rock>/releases.json`, in the format tt reads from
  `TT_WASM_RELEASES` and `TT_EMMYLUA_RELEASES`, or that of a
  [package](#packages); `<rock>/targets.json`, the targets a version is built
  for when it is built from source here; `<rock>/package.json` and
  `<rock>/setup.sh` of a package; the scripts and the workflows. A version
  with `platforms` is packed from the assets of an upstream release; one
  without is built from the source at its `ref`.
- **Releases**: one per version-revision, tagged `<rock>-<version>-<revision>`
  (`emmylua-0.25.1-1`), with an asset `<rock>-<version>-<revision>.<arch>.rock`
  per arch and `<rock>-<version>-<revision>.rockspec`. An arch is a platform,
  `all` for the `.all` rock of a package with no native file, or `src` for
  the source rock of a package. A release is made as a draft, its assets
  uploaded and checked, then published.
- **`index`**: one file, `tt-rocks-index.json`, written by the publish and
  yank workflows only. For each version-revision of each rock it lists the
  URL and the sha256 of the rockspec and of the rock of each arch, and
  `"yanked": true` for a [yanked](#yanking-a-version) one:

  ```json
  {
    "format": 1,
    "repository": {
      "emmylua": {
        "0.25.1-1": {
          "rockspec": {
            "url": "https://github.com/tarantool-contrib/rocks-repo/releases/download/emmylua-0.25.1-1/emmylua-0.25.1-1.rockspec",
            "sha256": "…"
          },
          "artifacts": [
            {
              "arch": "linux-x86_64",
              "url": "https://github.com/tarantool-contrib/rocks-repo/releases/download/emmylua-0.25.1-1/emmylua-0.25.1-1.linux-x86_64.rock",
              "sha256": "…",
              "size": 19777374
            }
          ]
        }
      }
    }
  }
  ```

## Adding a version

Add it to the table in a pull request. The watch workflow opens one every
day for each new release upstream; by hand:

```sh
# A release of tarantool-wasm-rs, built here from its tag v0.2.0.
scripts/entry.sh wasm 0.2.0 | scripts/add.sh wasm

# A release of EmmyLua, packed from its assets.
scripts/entry.sh emmylua 0.26.0 | scripts/add.sh emmylua

# EmmyLua at a commit, built from source here. A snapshot before 0.31.0 is
# 0.31.0pre1, pre2, ...: never a version upstream may release.
scripts/entry.sh emmylua 0.31.0pre1 <commit> | scripts/add.sh emmylua

# A package at its tag v1.3.0, built here.
scripts/entry.sh hello 1.3.0 | scripts/add.sh hello
```

The checksums of upstream assets are those GitHub reports for them: review
the upstream release before merging. Once the pull request is merged, the
publish workflow builds what is built from source, packs the rocks with tt,
publishes the release and adds it to the index.

To rebuild a published version, raise its `rock_revision`: the new revision
is published next to the old one, which stays.

## Packages

A package is a tt package, a project with an `app.manifest.toml`, in a
repository on GitHub. `tt package pack --format rock` builds it at the tag of
a version and packs it as a rock, its rockspec made from the manifest: the
dependencies are the ranges of `[dependencies]`, the source is
`[package].repository` at the tag. Its directory here, named as
`[package].name`, holds:

- `package.json`, what it is and how it is built:

  ```json
  {
    "repository": "https://github.com/example/hello",
    "path": "lua",
    "source_rock": true
  }
  ```

  `repository` is the repository on GitHub, `path` the directory of the
  project in it if it is not the root, and `source_rock`, false by default,
  whether the source rock (`tt package pack --format rock-src`, arch `src`)
  is published too: a tt that finds no rock of its platform or `all` builds
  the package from it, so it serves the platforms no target builds for.
- `targets.json`, where its rocks are built: a target per platform for a
  package with a native file (a C or Rust module, a program), or the one
  target of arch `all` for a package with none, whose `.all` rock installs
  anywhere. `os` is the runner, `container` an image to build in or empty.

  ```json
  {
    "targets": [
      {"arch": "linux-x86_64", "os": "ubuntu-24.04", "container": ""},
      {"arch": "linux-aarch64", "os": "ubuntu-24.04-arm", "container": ""},
      {"arch": "macosx-aarch64", "os": "macos-15", "container": ""}
    ]
  }
  ```

- `releases.json`, the versions: `ref` is what the build checks out, the
  tag `v<version>` as a rule; `version` is the LuaRocks version tt names the
  package by at that ref (the tag `v1.2.0-rc1` is `1.2.0.rc1`, a `VERSION`
  file overrides the tag); `rock_revision` the revision of the rock.

  ```json
  {"1.2.0": {"version": "1.2.0", "rock_revision": 1, "ref": "v1.2.0"}}
  ```

- `setup.sh`, optional: what the build needs besides tt, Tarantool and what
  the runner or the container has (CMake, a Rust toolchain; git and Python
  3.11 or newer in a container), run by bash in the root of this repository
  before the package is checked out, `ARCH` naming the target.

A build checks the package out with its submodules, its history and its
tags, and builds it against the oldest Tarantool `[platform].tarantool` of
its manifest allows, its lower bound: a module built against the headers of
the oldest Tarantool it supports loads on the newer ones, built against newer
ones it may not load on the older. `>=3.3.0,<4.0.0`, `~> 3.3` and `>=3.3` are
built against 3.3.0. A package is to declare its lower bound, as a release
of 3.0.0 or newer by `>=`: `*`, `<4.0.0` or `>3.3.0` fails the build, and so
does `[ee]`, Tarantool Enterprise, of which there is no SDK here
(`scripts/package-tarantool.sh`). tt installs that Tarantool, prebuilt on
Linux, built from source on macOS, and the install is cached by the release
and the runner: each is installed, or built, once.

The version tt names the package by has to be the one of the table, of a
clean tree, and its arch that of the target: a tag that is not the version,
a `setup.sh` that changes the checkout, or a native file in a package of
arch `all`, fails the build. The build runs the code of the package with no
token that writes; the job that publishes runs neither the package nor tt,
and only checks the rocks of the builds: one of each arch of the targets and
no other, their rockspec the same in each and beside each, of the package
and the version-revision.

Packing a package as a rock needs a tt with `tt package pack --format rock`
and `rock-src`, which the tt
[`.github/actions/setup-tt/action.yml`](.github/actions/setup-tt/action.yml)
builds is not yet: the commit it names is to be moved to one that has them
before a package is added.

The watch workflow reads the tags `vMAJOR.MINOR.PATCH` of the repository of a
package with git, and opens a pull request for each one newer than the
newest of the table; a pre-release tag is added by hand, with its ref.

## Yanking a version

The yank workflow, run by hand with a rock and a version-revision
(`0.25.1-1`) and a reason, marks its entry of the index `"yanked": true` in
one commit to `index` (`scripts/yank.sh`). Its release and its rocks stay: a
project that locked it still installs it, but tt resolves no new dependency
to it. Yanking is the one change an entry of the index ever has.

## Workflows

- **publish** (push to `master` changing a table, the scripts or the workflows;
  by hand): every version-revision the index lacks is built if it is built
  from source (by cargo on each target: EmmyLua with cargo-zigbuild for glibc
  2.17 on Linux, wasm the way tarantool-wasm-rs builds its releases; a package
  by `tt package pack` on each target), packed by `tt <rock> rock`, published
  as a release, and added to the index in one commit to `index`. A package
  that fails to build fails its own publication only. A release a failed run
  published is indexed by the next run; a draft a failed run left is deleted
  and made anew.
- **check** (pull requests; nightly): every published release is in the
  index, every URL of the index answers with the sha256 it lists, and each
  rockspec is the one inside the rocks. On a pull request, also the tables,
  the scripts, and a dry pack of the versions it adds that are packed from
  upstream assets: nothing is built from source on a pull request.
- **watch** (daily): a pull request for each new release of EmmyLua and
  tarantool-wasm-rs and each new tag of a package.
- **yank** (by hand): yanks a version-revision.

The tt that packs the rocks is built from the commit `ref` of
[`.github/actions/setup-tt/action.yml`](.github/actions/setup-tt/action.yml)
names. The yank workflow runs in the group of the publish workflow, one run
at a time writing `index`; GitHub keeps one run of a group waiting and
cancels any other, so a yank waiting behind a run of publish may be cancelled
by the next one, and is then to be run again.

## For the administrators

- Enable immutable releases (Settings, General, Releases): a published
  release can then change neither its assets nor its tag.
- Let GitHub Actions create pull requests (Settings, Actions, General,
  Workflow permissions), for the watch workflow.
- Let the publish and yank workflows push the branch `index`: if a ruleset
  covers it, let GitHub Actions bypass it.
