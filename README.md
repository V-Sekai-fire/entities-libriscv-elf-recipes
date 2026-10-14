# entities-libriscv-elf-recipes

Builds the example ELFs in entities-libriscv from pinned sources in a
container:

- `fib.rv64.elf`: `examples/embed/linux_fib.c`, built with riscv-gnu-toolchain
  2022.11.23 (GCC 12.2.0), `rv64gv`, `lp64d`. `examples/noexcept` and
  `examples/package` link to it.
- `program.elf`: `examples/wasm/program`, built with LuaJIT and with
  riscv-gnu-toolchain 2025.01.20 (GCC 14.2.0), `rv64g_zba_zbb_zbc_zbs`, `lp64d`.

`pins.exs` holds every commit. `Containerfile` builds the newlib compiler and
then the ELF.

```sh
elixir build.exs                      # all recipes, into out/<recipe>/
elixir build.exs --recipe fib --src /opt/other --out out2
elixir build.exs --check              # exit 1 if an ELF differs from pins.exs
CONTAINER=docker elixir build.exs
```

## Reproducibility

Each compile maps the build directory to `/rgt` with `-ffile-prefix-map`.
`GCCPKGVER` is set to an 11-character commit hash. Because of this, the ELF
does not depend on the build directory or on the depth of the clone. To check
this, build with two `--src` values and compare the sha256 values.

Status: the two-directory comparison has not run to completion yet.
`pins.exs` has `sha256: nil` until it does.

## Sources

The toolchain sources come from these places:

- riscv-gnu-toolchain, gcc (gcc-mirror), and newlib (mirror/newlib-cygwin):
  from GitHub.
- binutils: from sourceware.org. riscv-gnu-toolchain pins binutils as a
  submodule of sourceware.org, and no GitHub mirror has the 2025.01.20 pin.
  sourceware.org rate-limits parallel clones (HTTP 429). The Containerfile
  retries that fetch.
