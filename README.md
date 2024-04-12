llvm for Playbit

## Packages

    llvm-VERSION-toolchain-HOST      clang, lld et al for running on HOST
    llvm-VERSION-compiler-rt-TARGET  clang builtins, sanitizers etc for TARGET
    llvm-VERSION-libcxx-TARGET       libc++, libc++abi and libunwind for TARGET
    llvm-VERSION-sysroot-TARGET      libc and system headers for TARGET


## Using

Use a pre-built version for your host system and install packages for whatever targets
you want to build for: (or use the `llvm-install` helper script)

```shell
$ mkdir llvm && cd llvm
$ _add() { wget -q -O- http://files.playb.it/llvm-17.0.3-$1.tar.xz | tar -x; }
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
$ bin/clang hello.c -o hello
$ ./hello
hello from C program ./hello
```

Build for another architecture by setting `--target`:

```shell
$ bin/clang hello.c -o hello.a64 --target=aarch64-playbit
$ bin/clang hello.c -o hello.x86 --target=x86_64-playbit
$ bin/clang hello.c -o hello.wasm --target=wasm32-playbit
```

Let's verify that it worked:

```shell
$ for f in hello.a64 hello.x86; do \
bin/readelf --file-header $f | grep Machine; done
  Machine:                           AArch64
  Machine:                           Advanced Micro Devices X86-64
$ head -c4 hello.wasm | hexdump -c
0000000  \0   a   s   m
```

You can list available pre-built LLVM components using tools/webfiles:
`tools/webfiles ls llvm-17.0.3-`

> Note: If you are getting an error "./hello: not found" it is probably because
> the dynamic linker `/lib/ld.so.1` can't be found (it changed March 10 2024.)
> Workaround: compile with `-static` or `-Wl,--dynamic-linker=/lib/ld-musl-aarch64.so.1`


## Packages

The different packages are named symbolically:

- "toolchain" contains compiler & linker for the host platform
- "compiler-rt" contains compiler builtins & sanitizers for a target platform
- "sysroot" contains system headers & libraries for a target platform
- "libcxx" contains libc++ headers & libraries for a target platform
- "llvmdev" contains llvm headers & libraries for a target platform (you don't need this)


## Directory structure

```
bin/                -- clang, ld.lld et al (from "toolchain")
lib/clang/include/  -- compiler headers (stdint.h etc, from "toolchain")
sysroot/SYSTEM/ARCH -- headers & libraries for ARCH-playbit target
```


## Building from source

See `./build.sh -h` for options.

To build everything, run `build.sh` without arguments:

```shell
$ ./build.sh
```
