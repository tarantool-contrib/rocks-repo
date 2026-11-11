# emmylua

The programs of [EmmyLua](https://github.com/EmmyLuaLs/emmylua-analyzer-rust),
`emmylua_check`, `emmylua_ls`, `emmylua_doc_cli` and `luafmt`, as a binary
rock for `tt emmylua`.

`releases.json` is the table `tt emmylua rock` reads from
`TT_EMMYLUA_RELEASES`, by version:

- A version with `platforms` is an upstream release: `tt emmylua rock` packs
  its rock for each platform (`linux-x64-glibc.2.17`,
  `linux-aarch64-glibc.2.17` and `darwin-arm64` assets) from the release
  assets, each checked against its `sha256`.
- A version without is EmmyLua at the commit `ref`, built here by the publish
  workflow for each target of `targets.json` (`cargo zigbuild` against glibc
  2.17 on Linux, as upstream releases are; `cargo build` on macOS) and packed
  by `tt emmylua rock --from`. Its name is a snapshot before the next release,
  `0.30.0pre1`, where the crates say `0.30.0`. Before the build the workflow
  stamps the crates with the version of the rock, as semver, with the commit
  as build metadata (`scripts/program-version.sh`), by EmmyLua's own
  `tools/edit_version`, and updates `Cargo.lock` for those crates alone: the
  programs of `0.30.0pre1` report `0.30.0-pre1+599c338`.

`source_md5` is the md5 of the GitHub archive of `ref`, the source the
rockspec names; `rock_revision` is the revision of the rock.

`targets.json` names the targets and the Rust the builds use;
`requirements-zigbuild.txt` pins cargo-zigbuild and zig by hash. A change to
them applies to the builds of versions not published yet.

```toml
[dev_dependencies]
emmylua = { version = "0.30.0pre1", registry = "https://raw.githubusercontent.com/tarantool-contrib/rocks-repo/index/" }
```
