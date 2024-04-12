llvm for Playbit

## Packages

    llvm-VERSION-toolchain-HOST      clang, lld et al for running on HOST
    llvm-VERSION-compiler-rt-TARGET  clang builtins, sanitizers etc for TARGET
    llvm-VERSION-libcxx-TARGET       libc++, libc++abi and libunwind for TARGET
    llvm-VERSION-sysroot-TARGET      libc and system headers for TARGET


## Using

Use a pre-built version for your host system and install packages for whatever targets
you want to build for:

```shell
$ mkdir sdk
$ _add() { wget -O- http://files.playb.it/llvm-17.0.3-$1.tar.xz | tar -C sdk -x; }
$ _add toolchain-$(uname -m)-playbit
$ _add compiler-rt-aarch64-linux
$ _add compiler-rt-x86_64-linux
$ _add compiler-rt-wasm32-wasi
$ _add libcxx-aarch64-linux
$ _add libcxx-x86_64-linux
$ _add libcxx-wasm32-wasi
$ _add sysroot-aarch64-playbit
$ _add sysroot-x86_64-playbit
$ _add sysroot-wasm32-playbit
```

Build an example program:

```shell
$ cat << END > hello.c
#include <stdio.h>
int main(int argc, char* argv[]) {
  printf("hello from C program %s\n", argv[0]);
  return 0;
}
END
$ sdk/bin/clang hello.c -o hello
$ ./hello
hello from C program ./hello
```

Note: If you are getting an error "./hello: not found" it is probably because
the dynamic linker `/lib/ld.so.1` can't be found (it was recently added, March 10, 2024.)
Workaround for this is either: a) build & use a new playbit-system.qcow2 image, or compile with `-static` to embed libc at compile time.

Build for another architecture by setting `--target`:

```shell
$ sdk/bin/clang hello.c -o hello.a64 --target=aarch64-playbit
$ sdk/bin/clang hello.c -o hello.x86 --target=x86_64-playbit
$ sdk/bin/clang hello.c -o hello.wasm --target=wasm32-playbit
```

Let's verify that it worked:

```shell
$ for f in hello.a64 hello.x86; do \
sdk/bin/readelf --file-header $f | grep Machine; done
  Machine:                           AArch64
  Machine:                           Advanced Micro Devices X86-64
$ head -c4 hello.wasm | hexdump -c
0000000  \0   a   s   m
```

To list available pre-built versions of the SDK, use tools/webfiles:

```shell
$ tools/webfiles ls playbit-sdk-
2024-03-10 15:16:02   65 Bytes playbit-sdk-aarch64-20240312015803.tar.xz.sha256
2024-03-10 15:16:00   67.0 MiB playbit-sdk-aarch64-20240312015803.tar.xz
2024-03-10 15:16:21   65 Bytes playbit-sdk-x86_64-20240312015803.tar.xz.sha256
2024-03-10 15:16:19   70.9 MiB playbit-sdk-x86_64-20240312015803.tar.xz
```


## Layout

Each "SDK" contains compiler, linker and tools for the host architecture, plus a complete set of headers & libraries for every target architecture.

```
sdk/
  bin/                -- clang, ld.lld et al
  lib/clang/include/  -- target-agnostic compiler headers (stdint.h etc)
  lib/clang/lib/      -- target-specific compiler libraries (builtins.a etc)
  sysroot-generic/    -- headers & libraries for all *-playbit targets
  sysroot-ARCH/       -- headers & libraries for ARCH-playbit target
```


## Building

See `./build.sh -h` for options.

To build everything, run `build.sh` without arguments:

```shell
$ ./build.sh
```
