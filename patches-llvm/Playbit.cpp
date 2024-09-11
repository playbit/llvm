//===--- Playbit.cpp - Playbit ToolChain Implementations --------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "Playbit.h"
#include "WebAssembly.h"
#include "Arch/ARM.h"
#include "CommonArgs.h"
#include "clang/Config/config.h"
#include "clang/Driver/Compilation.h"
#include "clang/Driver/Driver.h"
#include "clang/Driver/DriverDiagnostic.h"
#include "clang/Driver/Options.h"
#include "clang/Driver/SanitizerArgs.h"
#include "llvm/Option/ArgList.h"
#include "llvm/ProfileData/InstrProf.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/VirtualFileSystem.h"
#include "llvm/Support/ScopedPrinter.h"

// #include <iostream>

using namespace clang::driver;
using namespace clang::driver::toolchains;
using namespace clang::driver::tools;
using namespace clang;
using namespace llvm::opt;
using namespace clang::driver::tools::arm;

using tools::addMultilibFlag;
using tools::addPathIfExists;
using llvm::sys::path::parent_path;


static std::string fspath(const std::initializer_list<std::string> &IL) {
  SmallString<128> P;
  for (const auto &S : IL)
    llvm::sys::path::append(P, S);
  return static_cast<std::string>(P.str());
}


// based on fuchsia::Linker::ConstructJob
void playbit::Linker::ConstructJob(Compilation &C, const JobAction &JA,
                                   const InputInfo &Output,
                                   const InputInfoList &Inputs,
                                   const ArgList &Args,
                                   const char *LinkingOutput) const {
  const toolchains::Playbit &ToolChain =
      static_cast<const toolchains::Playbit &>(getToolChain());
  const Driver &D = ToolChain.getDriver();

  const llvm::Triple &Triple = ToolChain.getEffectiveTriple();

  ArgStringList CmdArgs;

  // Silence warning for "clang -g foo.o -o foo"
  Args.ClaimAllArgs(options::OPT_g_Group);
  // and "clang -emit-llvm foo.o -o foo"
  Args.ClaimAllArgs(options::OPT_emit_llvm);
  // and for "clang -w foo.o -o foo". Other warning options are already
  // handled somewhere else.
  Args.ClaimAllArgs(options::OPT_w);

  CmdArgs.push_back("-z");
  CmdArgs.push_back("max-page-size=4096");

  CmdArgs.push_back("-z");
  CmdArgs.push_back("now");

  CmdArgs.push_back("-z");
  CmdArgs.push_back("relro");

  //CmdArgs.push_back("--enable-new-dtags");

  if (!ToolChain.SysRoot.empty())
    CmdArgs.push_back(Args.MakeArgString("--sysroot=" + ToolChain.SysRoot));

  bool isPIE;
  if (Args.hasArg(options::OPT_shared) ||
      Args.hasArg(options::OPT_static) ||
      Args.hasArg(options::OPT_r) ||
      Args.hasArg(options::OPT_static_pie) ) {
    isPIE = false;
  } else {
    Arg *A = Args.getLastArg(options::OPT_pie, options::OPT_no_pie, options::OPT_nopie);
    if (A) {
      isPIE = A->getOption().matches(options::OPT_pie);
    } else {
      isPIE = ToolChain.isPIEDefault(Args);
    }
  }
  if (isPIE)
    CmdArgs.push_back("-pie");

  if (Args.hasArg(options::OPT_static_pie)) {
    CmdArgs.push_back("-static");
    CmdArgs.push_back("-pie");
    CmdArgs.push_back("--no-dynamic-linker");
    CmdArgs.push_back("-z");
    CmdArgs.push_back("text");
  }

  if (Args.hasArg(options::OPT_s))
    CmdArgs.push_back("-s");

  if (Args.hasArg(options::OPT_r)) {
    CmdArgs.push_back("-r");
  } else {
    CmdArgs.push_back("--build-id");
    CmdArgs.push_back("--hash-style=gnu");
  }

  if (ToolChain.getArch() == llvm::Triple::aarch64) {
    CmdArgs.push_back("--execute-only");
    std::string CPU = getCPUName(D, Args, Triple);
    if (CPU.empty() || CPU == "generic" || CPU == "cortex-a53")
      CmdArgs.push_back("--fix-cortex-a53-843419");
  }

  CmdArgs.push_back("--eh-frame-hdr");

  const char* m;
  switch (ToolChain.getArch()) {
    case llvm::Triple::aarch64: m = "aarch64linux"; break;
    case llvm::Triple::x86:     m = "elf_i386"; break;
    case llvm::Triple::x86_64:  m = "elf_x86_64"; break;
    case llvm::Triple::riscv32: m = "elf32lriscv"; break;
    case llvm::Triple::riscv64: m = "elf64lriscv"; break;
    default: m = "unknown";
  }
  CmdArgs.push_back("-m");
  CmdArgs.push_back(m);

  if (Args.hasArg(options::OPT_static)) {
    CmdArgs.push_back("-Bstatic"); // == -static
  } else {
    if (Args.hasArg(options::OPT_rdynamic))
      CmdArgs.push_back("-export-dynamic");
    if (Args.hasArg(options::OPT_shared))
      CmdArgs.push_back("-shared");
    if (!Args.hasArg(options::OPT_shared) &&
        !Args.hasArg(options::OPT_r) &&
        !Args.hasArg(options::OPT_static_pie)) {
      // note: we ignore D.DyldPrefix (set with --dyld-prefix=) since the user can
      // override -dynamic-linker with -Wl,-dynamic-linker,/some/path
      CmdArgs.push_back("-dynamic-linker");
      CmdArgs.push_back(Args.MakeArgString("/lib/ld.so.1"));
    }
  }

  if (ToolChain.getArch() == llvm::Triple::riscv64)
    CmdArgs.push_back("-X");

  CmdArgs.push_back("-o");
  CmdArgs.push_back(Output.getFilename());

  // C runtime files
  // musl startfiles:
  //   crt1.o  [exe] position-dependent _start
  //   rcrt1.o [exe] position-independent _start, static libc
  //   Scrt1.o [exe] position-independent _start, shared libc
  //   crti.o  [exe, shlib] function prologs for the .init and .fini sections
  //   crtn.o  [exe, shlib] function epilogs for the .init/.fini sections
  //   note: musl has no crt0
  //   linking order: crt1 crti [-L paths] [objects] [C libs] crtn
  //   See https://www.openwall.com/lists/musl/2015/06/01/12 (re. rcrt1.o)
  //   See https://dev.gentoo.org/~vapier/crt.txt
  bool hasCRTFiles =
    !Args.hasArg(options::OPT_nostdlib, options::OPT_nostartfiles, options::OPT_r);
  if (hasCRTFiles) {
    if (!Args.hasArg(options::OPT_shared)) {
      const char* crt1;
      if (Args.hasArg(options::OPT_static_pie)) crt1 = "rcrt1.o";
      else if (isPIE)                           crt1 = "Scrt1.o";
      else                                      crt1 = "crt1.o";
      CmdArgs.push_back(Args.MakeArgString(ToolChain.GetFilePath(crt1)));
    }
    CmdArgs.push_back(Args.MakeArgString(ToolChain.GetFilePath("crti.o")));
  }

  Args.AddAllArgs(CmdArgs, options::OPT_L);
  Args.AddAllArgs(CmdArgs, options::OPT_u);

  ToolChain.AddFilePathLibArgs(Args, CmdArgs);

  if (D.isUsingLTO()) {
    assert(!Inputs.empty() && "Must have at least one input.");
    addLTOOptions(ToolChain, Args, CmdArgs, Output, Inputs[0],
                  D.getLTOMode() == LTOK_Thin);
  }

  addLinkerCompressDebugSectionsOption(ToolChain, Args, CmdArgs);
  AddLinkerInputs(ToolChain, Inputs, Args, CmdArgs, JA);

  if (!Args.hasArg(options::OPT_nostdlib, options::OPT_nodefaultlibs, options::OPT_r)) {
    if (D.CCCIsCXX()) {
      if (ToolChain.ShouldLinkCXXStdlib(Args)) {
        bool OnlyLibstdcxxStatic = Args.hasArg(options::OPT_static_libstdcxx) &&
                                   !Args.hasArg(options::OPT_static);
        CmdArgs.push_back("--push-state");
        CmdArgs.push_back("--as-needed");
        if (OnlyLibstdcxxStatic)
          CmdArgs.push_back("-Bstatic");
        ToolChain.AddCXXStdlibLibArgs(Args, CmdArgs);
        if (OnlyLibstdcxxStatic)
          CmdArgs.push_back("-Bdynamic");
        CmdArgs.push_back("-lm");
        CmdArgs.push_back("--pop-state");
      }
    }

    bool NeedsSanitizerDeps = addSanitizerRuntimes(ToolChain, Args, CmdArgs);
    if (NeedsSanitizerDeps)
      linkSanitizerRuntimeDeps(ToolChain, CmdArgs);

    bool NeedsXRayDeps = addXRayRuntime(ToolChain, Args, CmdArgs);
    if (NeedsXRayDeps)
      linkXRayRuntimeDeps(ToolChain, CmdArgs);

    ToolChain.addProfileRTLibs(Args, CmdArgs);

    AddRunTimeLibs(ToolChain, D, CmdArgs, Args);

    if (Args.hasArg(options::OPT_pthread) ||
        Args.hasArg(options::OPT_pthreads))
      CmdArgs.push_back("-lpthread");

    if (Args.hasArg(options::OPT_fblocks) && !Args.hasArg(options::OPT_fno_blocks))
      CmdArgs.push_back("-lBlocksRuntime");

    if (Args.hasArg(options::OPT_fsplit_stack))
      CmdArgs.push_back("--wrap=pthread_create");

    if (!Args.hasArg(options::OPT_nolibc))
      CmdArgs.push_back("-lc");
  }

  if (hasCRTFiles)
    CmdArgs.push_back(Args.MakeArgString(ToolChain.GetFilePath("crtn.o")));

  Args.AddAllArgs(CmdArgs, options::OPT_T);

  const char *Exec = Args.MakeArgString(ToolChain.GetLinkerPath());
  C.addCommand(std::make_unique<Command>(JA, *this,
                                         ResponseFileSupport::AtFileCurCP(),
                                         Exec, CmdArgs, Inputs, Output));
}


// based on fuchsia::StaticLibTool::ConstructJob
void playbit::StaticLibTool::ConstructJob(Compilation &C, const JobAction &JA,
                                          const InputInfo &Output,
                                          const InputInfoList &Inputs,
                                          const ArgList &Args,
                                          const char *LinkingOutput) const {
  const Driver &D = getToolChain().getDriver();

  // Silence warning for "clang -g foo.o -o foo"
  Args.ClaimAllArgs(options::OPT_g_Group);
  // and "clang -emit-llvm foo.o -o foo"
  Args.ClaimAllArgs(options::OPT_emit_llvm);
  // and for "clang -w foo.o -o foo". Other warning options are already
  // handled somewhere else.
  Args.ClaimAllArgs(options::OPT_w);
  // Silence warnings when linking C code with a C++ '-stdlib' argument.
  Args.ClaimAllArgs(options::OPT_stdlib_EQ);

  // ar tool command "llvm-ar <options> <output_file> <input_files>".
  ArgStringList CmdArgs;
  // Create and insert file members with a deterministic index.
  CmdArgs.push_back("rcsD");
  CmdArgs.push_back(Output.getFilename());

  for (const auto &II : Inputs) {
    if (II.isFilename())
      CmdArgs.push_back(II.getFilename());
  }

  // Delete old output archive file if it already exists before generating a new
  // archive file.
  const char *OutputFileName = Output.getFilename();
  if (Output.isFilename() && llvm::sys::fs::exists(OutputFileName)) {
    if (std::error_code EC = llvm::sys::fs::remove(OutputFileName)) {
      D.Diag(diag::err_drv_unable_to_remove_file) << EC.message();
      return;
    }
  }

  const char *Exec = Args.MakeArgString(getToolChain().GetStaticLibToolPath());
  C.addCommand(std::make_unique<Command>(JA, *this,
                                         ResponseFileSupport::AtFileCurCP(),
                                         Exec, CmdArgs, Inputs, Output));
}


/// Playbit Toolchain
Playbit::Playbit(const Driver &D, const llvm::Triple &targetTriple, const ArgList &Args)
    : ToolChain(D, targetTriple, Args) {

  // Note: D.getInstalledDir() returns logical path; it does not resolve symlinks.
  // I.e. with clang installed at /foo/bin/clang and symlinked at /cat/clang,
  // D.getInstalledDir() == /cat, D.getClangProgramPath() == /foo/bin/clang
  std::string exedir = std::string(parent_path(D.getClangProgramPath()));
  std::string sdkDir = std::string(parent_path(exedir));
  #if 0
    std::cout << "[pb] exedir: " << exedir << std::endl;
    std::cout << "[pb] sdkDir: " << sdkDir << std::endl;
    std::cout << "[pb] D.Dir: " << std::string(D.Dir) << std::endl;
    std::cout << "[pb] driver.SysRoot: " << D.SysRoot << std::endl;
    std::cout << "[pb] triple: " << getTriple().str() << std::endl;
  #endif

  // select sysroot dir
  if (D.SysRoot.empty()) {
    SysRoot = fspath({ sdkDir, "sysroot/" + getTriple().getArchName().str() });
    if (!getVFS().exists(SysRoot))
      SysRoot = fspath({ sdkDir, "sysroot/playbit/" + getTriple().getArchName().str() });
  } else {
    // user provided explicit --sysroot=
    SysRoot = D.SysRoot;
  }
  // std::cout << "[pb] effective sysroot: \"" << SysRoot << "\"" << std::endl;

  // when searching for tools like ld.lld, look in these directories
  getProgramPaths().push_back(exedir);
  // D.Dir: path the driver executable was in, as invoked from the command line
  if (D.getInstalledDir() != D.Dir)
    getProgramPaths().push_back(D.Dir);


  // setup search paths
  getFilePaths().clear(); // always empty; just in case it changes in future llvm
  getLibraryPaths().clear(); // always empty; just in case it changes in future llvm

  std::string compiler_rt_lib_path = fspath({ SysRoot, "lib", "clang", "lib" });
  // std::cout << "[pb] compiler_rt_lib_path: " << compiler_rt_lib_path << std::endl;
  if (getVFS().exists(compiler_rt_lib_path)) {
    getFilePaths().push_back(compiler_rt_lib_path);
    getLibraryPaths().push_back(compiler_rt_lib_path);
  }

  LibClangDir = fspath({
    sdkDir,
    "lib/clang-" + getTriple().getArchName().str() + "-" + getTriple().getOSName().str()
  });
  std::string lib_clang_lib = LibClangDir + "/lib";
  // std::cout << "[pb] lib_clang_lib: " << lib_clang_lib << std::endl;
  if (getVFS().exists(lib_clang_lib)) {
    getFilePaths().push_back(lib_clang_lib);
    getLibraryPaths().push_back(lib_clang_lib);
  }

  getFilePaths().push_back(fspath({ SysRoot, "lib" }));

  std::string libdir = fspath({ sdkDir, "lib" });
  if (getVFS().exists(libdir))
    getFilePaths().push_back(libdir);

  // Default linker. Can be overridden with --ld-path= or -fuse-ld=
  // Use absolute path for ld.lld to reduce I/O from ToolChain::GetLinkerPath
  // and Driver::GetProgramPath.
  DefaultLinker = exedir + (getTriple().isWasm() ? "/wasm-ld" : "/ld.lld");
  // DefaultLinker = getTriple().isWasm() ? "wasm-ld" : exedir + "/ld.lld";
  // std::cout << "[pb] DefaultLinker: " << DefaultLinker << std::endl;
}


/// Following the conventions in https://wiki.debian.org/Multiarch/Tuples,
/// we remove the vendor field to form the multiarch triple.
std::string Playbit::getMultiarchTriple(const llvm::Triple &T) const {
  // printf("[pb] trace %s:%d\n", __FILE__, __LINE__);
  return (T.getArchName() + "-" + T.getOSAndEnvironmentName()).str();
}


std::string Playbit::getMultiarchTriple(const Driver &D,
                                        const llvm::Triple &TargetTriple,
                                        StringRef SysRoot) const {
  return getMultiarchTriple(TargetTriple);
}


bool Playbit::isPIEDefault(const llvm::opt::ArgList &Args) const {
  // true for native targets, false for wasm
  return !getTriple().isWasm();
}


bool Playbit::hasBlocksRuntime() const {
  return true;
}


Tool *Playbit::buildAssembler() const {
  return new tools::gnutools::Assembler(*this);
}


Tool* Playbit::buildLinker() const {
  if (getTriple().isWasm())
    return new tools::wasm::Linker(*this);

  // Note: gnutools::Linker requires the driver to be a subclass of Generic_ELF.
  // This is not conveyed in the type signature (it can't; it's complicated.)
  // Internally, gnutools::Linker::ConstructJob performs a cast to Generic_ELF.
  // We will get hard-to-debug crash from vtable dispatch if this is not Generic_ELF.
  //return new tools::gnutools::Linker(*this);

  return new tools::playbit::Linker(*this);
}


Tool *Playbit::buildStaticLibTool() const {
  assert(!getTriple().isWasm());
  return new tools::playbit::StaticLibTool(*this);
}


void Playbit::addClangTargetOptions(const ArgList &DriverArgs,
                                    ArgStringList &CC1Args,
                                    Action::OffloadKind) const {
  // based on Generic_ELF::addClangTargetOptions
  if (!DriverArgs.hasFlag(options::OPT_fuse_init_array,
                          options::OPT_fno_use_init_array, true))
    CC1Args.push_back("-fno-use-init-array");
}


void Playbit::AddClangSystemIncludeArgs(const ArgList &DriverArgs,
                                        ArgStringList &CC1Args) const {
  const Driver &D = getDriver();

  // don't add any search paths if -nostdinc is set
  if (DriverArgs.hasArg(options::OPT_nostdinc))
    return;

  // add -isystem<sdkDir>/lib/clang/include (unless -nobuiltininc is set)
  if (!DriverArgs.hasArg(options::OPT_nobuiltininc)) {
    SmallString<128> P(D.ResourceDir);
    llvm::sys::path::append(P, "include");
    addSystemInclude(DriverArgs, CC1Args, P);
  }

  // don't add standard-library search paths if -nostdlibinc is set
  if (DriverArgs.hasArg(options::OPT_nostdlibinc))
    return;

  // // Check for configure-time C include directories.
  // // std::cout << "[pb] C_INCLUDE_DIRS: \"" << C_INCLUDE_DIRS << "\"" << std::endl;
  // StringRef CIncludeDirs(C_INCLUDE_DIRS);
  // if (CIncludeDirs != "") {
  //   SmallVector<StringRef, 5> dirs;
  //   CIncludeDirs.split(dirs, ":");
  //   for (StringRef dir : dirs) {
  //     if (llvm::sys::path::is_absolute(dir)) {
  //       addExternCSystemInclude(DriverArgs, CC1Args, dir);
  //     } else {
  //       addExternCSystemInclude(
  //         DriverArgs, CC1Args, fspath({ SysRoot, std::string(dir) }));
  //     }
  //   }
  //   return;
  // }

  std::string incPath = fspath({SysRoot, "usr/include"});
  // std::cout << "[pb] incPath: " << incPath << std::endl;
  if (getVFS().exists(incPath)) {
    addExternCSystemInclude(DriverArgs, CC1Args, incPath);
  } else {
    incPath = fspath({SysRoot, "include"});
    if (getVFS().exists(incPath))
      addExternCSystemInclude(DriverArgs, CC1Args, incPath);
  }

  std::string sdkDir = std::string(parent_path(parent_path(D.getClangProgramPath())));
  incPath = fspath({sdkDir, "/usr/include"});
  if (getVFS().exists(incPath))
    addExternCSystemInclude(DriverArgs, CC1Args, incPath);
}


void Playbit::AddClangCXXStdlibIncludeArgs(const ArgList &DriverArgs,
                                        ArgStringList &CC1Args) const {
  if (DriverArgs.hasArg(options::OPT_nostdlibinc) ||
      DriverArgs.hasArg(options::OPT_nostdincxx))
    return;

  std::string incPath = fspath({SysRoot, "usr/include/c++/v1"});
  if (getVFS().exists(incPath)) {
    // SDK headers
    addSystemInclude(DriverArgs, CC1Args, incPath);
  } else {
    incPath = fspath({SysRoot, "include/c++/v1"});
    if (getVFS().exists(incPath))
      addSystemInclude(DriverArgs, CC1Args, incPath);
  }

  const Driver &D = getDriver();
  std::string sdkDir = std::string(parent_path(parent_path(D.getClangProgramPath())));
  incPath = fspath({sdkDir, "/usr/include/c++/v1"});
  if (getVFS().exists(incPath))
    addSystemInclude(DriverArgs, CC1Args, incPath);
}


void Playbit::AddCXXStdlibLibArgs(const ArgList &DriverArgs,
                                  ArgStringList &CmdArgs) const {
  if (DriverArgs.hasArg(options::OPT_nostdlib) ||
      DriverArgs.hasArg(options::OPT_nostdlibxx))
    return;
  CmdArgs.push_back("-lc++");
  CmdArgs.push_back("-lc++abi");
  if (!getTriple().isWasm())
    CmdArgs.push_back("-lunwind");
}


std::string Playbit::getCompilerRT(const ArgList &Args, StringRef Component,
                                   FileType Type) const {
  // printf("[pb] trace %s:%d\n", __FILE__, __LINE__);
  SmallString<128> Path(SysRoot);
  llvm::sys::path::append(Path, "lib/clang/lib");
  for (int retried = 0;;) {
    const char *Prefix = (Type == ToolChain::FT_Object) ? "" : "lib";
    const char *Suffix;
    switch (Type) {
    case ToolChain::FT_Object:
      Suffix = ".o";
      break;
    case ToolChain::FT_Static:
      Suffix = ".a";
      break;
    case ToolChain::FT_Shared:
      Suffix = ".so";
      break;
    }
    llvm::sys::path::append(Path, Prefix + Twine("clang_rt.") + Component + Suffix);
    // std::cout << "[pb] getCompilerRT: " << std::string(Path.str()) << std::endl;
    if (getVFS().exists(Path) || retried++)
      break;
    Path.assign(LibClangDir + "/lib");
  }
  return static_cast<std::string>(Path.str());
}


SanitizerMask Playbit::getSupportedSanitizers() const {
  // printf("[pb] trace %s:%d\n", __FILE__, __LINE__);
  SanitizerMask Res = ToolChain::getSupportedSanitizers();
  if (getTriple().isWasm()) {
    // -fsanitize=function places two words before the function label (unsupported)
    Res &= ~SanitizerKind::Function;
  } else {
    // x86_64 or aarch64 (based on Linux::getSupportedSanitizers)
    Res |= SanitizerKind::Address;
    Res |= SanitizerKind::PointerCompare;
    Res |= SanitizerKind::PointerSubtract;
    Res |= SanitizerKind::Fuzzer;
    Res |= SanitizerKind::FuzzerNoLink;
    Res |= SanitizerKind::KernelAddress;
    Res |= SanitizerKind::Memory;
    Res |= SanitizerKind::Vptr;
    Res |= SanitizerKind::SafeStack;
    Res |= SanitizerKind::DataFlow;
    Res |= SanitizerKind::Leak;
    Res |= SanitizerKind::Thread;
    if (getTriple().getArch() == llvm::Triple::x86_64)
      Res |= SanitizerKind::KernelMemory;
    // Res |= SanitizerKind::Scudo;
    Res |= SanitizerKind::HWAddress;
    Res |= SanitizerKind::KernelHWAddress;
  }
  return Res;
}


// TODO: Make a base class for Linux and Playbit and move this there.
void Playbit::addProfileRTLibs(const llvm::opt::ArgList &Args,
                             llvm::opt::ArgStringList &CmdArgs) const {
  // printf("[pb] trace %s:%d\n", __FILE__, __LINE__);
  // Add linker option -u__llvm_profile_runtime to cause runtime
  // initialization module to be linked in.
  if (needsProfileRT(Args)) {
    CmdArgs.push_back(Args.MakeArgString(
      Twine("-u", llvm::getInstrProfRuntimeHookVarName())));
  }
  ToolChain::addProfileRTLibs(Args, CmdArgs);
}


ToolChain::UnwindLibType Playbit::GetUnwindLibType(
    const llvm::opt::ArgList &Args) const {
  // printf("[pb] trace %s:%d\n", __FILE__, __LINE__);
  if (Args.getLastArg(options::OPT_unwindlib_EQ))
    return ToolChain::GetUnwindLibType(Args);
  return getTriple().isWasm() ? ToolChain::UNW_None : ToolChain::UNW_CompilerRT;
}
