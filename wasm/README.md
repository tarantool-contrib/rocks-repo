# wasm

The Lua C module of [tarantool-wasm](https://github.com/tarantool/tarantool-wasm-rs),
`require('wasm')`, which runs WebAssembly components in Tarantool 3.6 and
newer, as a binary rock.

`releases.json` is the table `tt wasm rock` reads from `TT_WASM_RELEASES`, by
version. Each version is a tarantool-wasm release, built here from its tag,
`ref` (`v0.1.0`), by the publish workflow for each target of `targets.json`,
the way tarantool-wasm-rs builds its own releases:

- Linux: in the CentOS 8 container of packpack, for glibc 2.28, with the
  OpenSSL, Rust and WIT setup actions of tarantool-wasm-rs, `cargo build
  --locked --release --target <triple>`;
- macOS: on the runner, with OpenSSL from Homebrew, `cargo build --locked
  --release`.

The module, `module` of the target, is packed by `tt wasm rock --from` as
`lib/wasm.so` or `lib/wasm.dylib`. `sdk_asset` and `sdk_md5` name the SDK
archive of the release, the source the rockspec names; `rock_revision` is
the revision of the rock. A version with `platforms` would instead be packed
from the module assets of the release.

```toml
[dependencies]
wasm = { version = "0.1.0", registry = "https://raw.githubusercontent.com/tarantool-contrib/rocks-repo/index/" }
```
