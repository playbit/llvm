llvm for Playbit

## Packages

The different packages are named symbolically:

- "toolchain" contains compiler & linker for the host platform
- "compiler-rt" contains compiler builtins & sanitizers for a target platform
- "sysroot" contains system headers & libraries for a target platform
- "libcxx" contains libc++ headers & libraries for a target platform
- "llvmdev" contains llvm headers & libraries for a target platform (you don't need this)

```
llvm-VERSION-toolchain-HOST      clang, lld et al for running on HOST
llvm-VERSION-compiler-rt-TARGET  clang builtins, sanitizers etc for TARGET
llvm-VERSION-libcxx-TARGET       libc++, libc++abi and libunwind for TARGET
llvm-VERSION-sysroot-TARGET      libc and system headers for TARGET
```

## Using

Use a pre-built version for your host system and install packages for whatever targets
you want to build for:

```shell
$ mkdir llvm && cd llvm
$ tar -xf ../llvm-17.0.3-toolchain-$(uname -m)-playbit.tar.xz
$ tar -xf ../llvm-17.0.3-compiler-rt-aarch64-linux.tar.xz
$ tar -xf ../llvm-17.0.3-compiler-rt-x86_64-linux.tar.xz
$ tar -xf ../llvm-17.0.3-compiler-rt-wasm32-wasi.tar.xz
$ tar -xf ../llvm-17.0.3-libcxx-aarch64-linux.tar.xz
$ tar -xf ../llvm-17.0.3-libcxx-x86_64-linux.tar.xz
$ tar -xf ../llvm-17.0.3-libcxx-wasm32-wasi.tar.xz
$ tar -xf ../llvm-17.0.3-sysroot-aarch64-playbit.tar.xz
$ tar -xf ../llvm-17.0.3-sysroot-x86_64-playbit.tar.xz
$ tar -xf ../llvm-17.0.3-sysroot-wasm32-playbit.tar.xz
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


## Building from source

See `./build.sh -h` for options.

To build everything, run `build.sh` without arguments:

```shell
$ ./build.sh
```

To build select hosts and targets specific versions:

```shell
$ ./build.sh --sysroot-target=aarch64-macos aarch64-macos
```

## Developement

When making changes and testing them in Playbit, you can use the `dev.sh` script:

```shell
./dev.sh
```

By default, this will re-apply all the patches and then rebuild LLVM.

⚠️ NOTE: that you must delete the corresponding folder in `./built-target/aarch64-playbit/` to have your changes reflected.

To make changes directly to the code test out your changes in Playbit quickly, run:

```shell
./dev.sh --no-patch
```

Otherwise, you can rebuild everything (but this will be much slower):

```shell
./dev.sh --clean
```
