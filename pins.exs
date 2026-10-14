# Pins for each recipe. build.exs passes every key except :sha256 and :output
# to the Containerfile as a build arg. :sha256 is the expected output; --check
# fails when the built ELF differs.
%{
  libriscv: "2a65a1e971fa8d8ba404d5e566aac3d032f91c51",
  recipes: %{
    fib: %{
      output: "fib.rv64.elf",
      UBUNTU: "22.04",
      RGT_TAG: "2022.11.23",
      ARCH: "rv64gv",
      ABI: "lp64d",
      GCC_SHA: "2ee5e4300186a92ad73f1a1a64cb918dc76c8d67",
      BINUTILS_SHA: "b51c2fec1da205ea3e7354cbb3e253018d64873c",
      NEWLIB_SHA: "415fdd4279b85eeec9d54775ce13c5c412451e08",
      LUAJIT_SHA: "",
      sha256: nil
    },
    program: %{
      output: "program.elf",
      UBUNTU: "24.04",
      RGT_TAG: "2025.01.20",
      ARCH: "rv64g_zba_zbb_zbc_zbs",
      ABI: "lp64d",
      GCC_SHA: "04696df09633baf97cdbbdd6e9929b9d472161d3",
      BINUTILS_SHA: "beb2cdbcda911764b2bed5e57921fe90493260bd",
      NEWLIB_SHA: "26f7004bf73c421c3fd5e5a6ccf470d05337b435",
      LUAJIT_SHA: "702de32f485aa8d6db2b91eaf1d0ae3ba19e10c6",
      sha256: nil
    }
  }
}
