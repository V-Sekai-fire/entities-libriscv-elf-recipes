# Builds a pinned riscv-gnu-toolchain newlib compiler, then one example ELF
# from entities-libriscv with it. build.exs passes every ARG from pins.exs.
#
# SRC is the directory everything is built in. Every compile maps it to /rgt
# with -ffile-prefix-map, so the ELF does not depend on it: building with two
# different SRC values gives the same bytes.

ARG UBUNTU=22.04
FROM docker.io/library/ubuntu:${UBUNTU} AS toolchain
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
ARG RGT_TAG
ARG ARCH
ARG ABI
ARG GCC_SHA
ARG BINUTILS_SHA
ARG NEWLIB_SHA
ARG SRC=/src
ARG JOBS=4
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      autoconf automake autotools-dev curl python3 libmpc-dev libmpfr-dev libgmp-dev \
      gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev \
      libexpat-dev git ca-certificates >/dev/null && rm -rf /var/lib/apt/lists/*
WORKDIR ${SRC}
RUN fetch() { mkdir -p "$1" && git -C "$1" init -q && git -C "$1" fetch -q --depth 1 "$2" "$3" \
                && git -C "$1" checkout -q FETCH_HEAD; } \
 && git clone -q --depth 1 --branch "${RGT_TAG}" https://github.com/riscv-collab/riscv-gnu-toolchain.git rgt \
 && for i in 1 2 3 4 5; do git -C rgt submodule update -q --init --depth 1 binutils && break; \
      echo "binutils fetch failed (sourceware rate limit?), retry $i" >&2; sleep $((i * 60)); done \
 && test "$(git -C rgt/binutils rev-parse HEAD)" = "${BINUTILS_SHA}" \
 && fetch gcc https://github.com/gcc-mirror/gcc.git "${GCC_SHA}" \
 && fetch newlib https://github.com/mirror/newlib-cygwin.git "${NEWLIB_SHA}"
# GCCPKGVER is what lands in .comment. riscv-gnu-toolchain takes it from
# `git describe`, whose length depends on the clone; pin it to 11 characters.
RUN mkdir build && cd build \
 && ../rgt/configure --prefix=/opt/riscv --with-arch="${ARCH}" --with-abi="${ABI}" --disable-gdb \
      --with-gcc-src="${SRC}/gcc" --with-binutils-src="${SRC}/rgt/binutils" \
      --with-newlib-src="${SRC}/newlib" >/dev/null \
 && make -j"${JOBS}" newlib GCCPKGVER="g${GCC_SHA:0:11}" \
      CFLAGS_FOR_TARGET_EXTRA="-ffile-prefix-map=${SRC}=/rgt" \
      CXXFLAGS_FOR_TARGET_EXTRA="-ffile-prefix-map=${SRC}=/rgt" >/dev/null \
 && cd .. && rm -rf build gcc newlib rgt
ENV PATH=/opt/riscv/bin:$PATH

FROM toolchain AS elf
ARG RECIPE
ARG LIBRISCV_SHA
ARG LUAJIT_SHA
ARG SRC=/src
WORKDIR ${SRC}/work
RUN git init -q libriscv \
 && git -C libriscv fetch -q --depth 1 https://github.com/V-Sekai-fire/entities-libriscv.git "${LIBRISCV_SHA}" \
 && git -C libriscv checkout -q FETCH_HEAD
RUN mkdir -p /out && MAP="-ffile-prefix-map=${SRC}=/rgt" && case "${RECIPE}" in \
  fib) \
    cd libriscv/examples/embed \
    && riscv64-unknown-elf-gcc -O2 "$MAP" linux_fib.c -o /out/fib.rv64.elf \
    && riscv64-unknown-elf-strip /out/fib.rv64.elf ;; \
  program) \
    git -C libriscv submodule update -q --init --depth 1 examples/wasm/program/LuaJIT \
    && test "$(git -C libriscv/examples/wasm/program/LuaJIT rev-parse HEAD)" = "${LUAJIT_SHA}" \
    && cd libriscv/examples/wasm/program \
    && make -C LuaJIT -j4 CROSS=riscv64-unknown-elf- XCFLAGS="$MAP" >/dev/null \
    && sed -i "s|riscv64-unknown-elf-g++ -O2|riscv64-unknown-elf-g++ -O2 $MAP|" build.sh \
    && ./build.sh && cp program.elf /out/program.elf ;; \
  *) echo "unknown RECIPE ${RECIPE}" >&2; exit 1 ;; \
  esac
