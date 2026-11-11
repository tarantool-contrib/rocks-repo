# rocks-repo

Experimental binary rocks for tt 3, one URL for all of them:

```
https://raw.githubusercontent.com/tarantool-contrib/rocks-repo/index/
```

| Rock | What it is | Table |
| --- | --- | --- |
| `wasm` | The Lua C module of [tarantool-wasm](https://github.com/tarantool/tarantool-wasm-rs): WebAssembly components in Tarantool 3.6 and newer | [`wasm/releases.json`](wasm/releases.json) |
| `emmylua` | The programs of [EmmyLua](https://github.com/EmmyLuaLs/emmylua-analyzer-rust): `emmylua_check`, `emmylua_ls`, `emmylua_doc_cli`, `luafmt`, for `tt emmylua` | [`emmylua/releases.json`](emmylua/releases.json) |

Each version has a binary rock for `linux-x86_64`, `linux-aarch64` and
`macosx-aarch64`. Once published, a rock never changes; a new build of a
version is a new rock revision.

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
  `TT_WASM_RELEASES` and `TT_EMMYLUA_RELEASES`; `<rock>/targets.json`, the
  targets a version is built for when it is built from source here; the
  scripts and the workflows. A version with `platforms` is packed from the
  assets of an upstream release; one without is built from the source at
  its `ref`.
- **Releases**: one per version-revision, tagged `<rock>-<version>-<revision>`
  (`emmylua-0.25.1-1`), with an asset `<rock>-<version>-<revision>.<arch>.rock`
  per platform and `<rock>-<version>-<revision>.rockspec`. A release is made
  as a draft, its assets uploaded and checked, then published.
- **`index`**: one file, `tt-rocks-index.json`, written by the publish
  workflow only. For each version-revision of each rock it lists the URL and
  the sha256 of the rockspec and of the rock of each platform:

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
```

The checksums of upstream assets are those GitHub reports for them: review
the upstream release before merging. Once the pull request is merged, the
publish workflow builds what is built from source, packs the rocks with tt,
publishes the release and adds it to the index.

To rebuild a published version, raise its `rock_revision`: the new revision
is published next to the old one, which stays.

## Workflows

- **publish** (push to `master` changing a table, the scripts or the workflows;
  by hand): every version-revision the index lacks is built if it is built
  from source (by cargo on each target: EmmyLua with cargo-zigbuild for glibc
  2.17 on Linux, wasm the way tarantool-wasm-rs builds its releases), packed
  by `tt <rock> rock`, published as a release, and added to the index in one
  commit to `index`. A release a failed run published is indexed by the next
  run; a draft a failed run left is deleted and made anew.
- **check** (pull requests; nightly): every published release is in the
  index, every URL of the index answers with the sha256 it lists, and each
  rockspec is the one inside the rocks. On a pull request, also the tables,
  the scripts, and a dry pack of the versions it adds.
- **watch** (daily): a pull request for each new release of EmmyLua and
  tarantool-wasm-rs.

The tt that packs the rocks is built from the commit `ref` of
[`.github/actions/setup-tt/action.yml`](.github/actions/setup-tt/action.yml)
names.

## For the administrators

- Enable immutable releases (Settings, General, Releases): a published
  release can then change neither its assets nor its tag.
- Let GitHub Actions create pull requests (Settings, Actions, General,
  Workflow permissions), for the watch workflow.
- Let the publish workflow push the branch `index`: if a ruleset covers it,
  let GitHub Actions bypass it.
