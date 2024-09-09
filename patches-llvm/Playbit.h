//===--- Playbit.h - Playbit ToolChain Implementations --------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_Playbit_H
#define LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_Playbit_H

#include "clang/Driver/Tool.h"
#include "clang/Driver/ToolChain.h"

namespace clang {
namespace driver {

namespace tools {
namespace playbit {

class LLVM_LIBRARY_VISIBILITY StaticLibTool : public Tool {
public:
  StaticLibTool(const ToolChain &TC)
      : Tool("playbit::StaticLibTool", "llvm-ar", TC) {}

  bool hasIntegratedCPP() const override { return false; }
  bool isLinkJob() const override { return true; }

  void ConstructJob(Compilation &C, const JobAction &JA,
                    const InputInfo &Output, const InputInfoList &Inputs,
                    const llvm::opt::ArgList &TCArgs,
                    const char *LinkingOutput) const override;
};

class LLVM_LIBRARY_VISIBILITY Linker : public Tool {
public:
  Linker(const ToolChain &TC) : Tool("playbit::Linker", "ld.lld", TC) {}

  bool hasIntegratedCPP() const override { return false; }
  bool isLinkJob() const override { return true; }

  void ConstructJob(Compilation &C, const JobAction &JA,
                    const InputInfo &Output, const InputInfoList &Inputs,
                    const llvm::opt::ArgList &TCArgs,
                    const char *LinkingOutput) const override;
};

} // end namespace playbit
} // end namespace tools

namespace toolchains {

class LLVM_LIBRARY_VISIBILITY Playbit : public ToolChain {
  friend class clang::driver::tools::playbit::Linker;
  std::string SysRoot;
  std::string LibClangDir;
  std::string DefaultLinker;
public:
  Playbit(const Driver &D, const llvm::Triple &Triple,
          const llvm::opt::ArgList &Args);

  bool HasNativeLLVMSupport() const override { return true; }
  bool IsMathErrnoDefault() const override { return false; }
  //bool IsBlocksDefault() const override { return true; } // -fno-blocks to disable
  bool IsBlocksDefault() const override { return false; } // -fblocks to enable
  bool isPICDefault() const override { return false; }
  bool isPIEDefault(const llvm::opt::ArgList &Args) const override;
  bool isPICDefaultForced() const override { return false; }
  bool hasBlocksRuntime() const override;
  bool SupportsProfiling() const override { return !getTriple().isWasm(); }
  unsigned GetDefaultDwarfVersion() const override {
    return getTriple().isWasm() ? 4 : 5;
  }

  UnwindLibType GetUnwindLibType(const llvm::opt::ArgList &Args) const override;
  UnwindLibType GetDefaultUnwindLibType() const override { return UNW_CompilerRT; }

  RuntimeLibType GetDefaultRuntimeLibType() const override {
    return ToolChain::RLT_CompilerRT;
  }
  CXXStdlibType GetDefaultCXXStdlibType() const override {
    return ToolChain::CST_Libcxx;
  }
  RuntimeLibType GetRuntimeLibType(const llvm::opt::ArgList &Args) const override {
    return ToolChain::RLT_CompilerRT;
  }
  CXXStdlibType GetCXXStdlibType(const llvm::opt::ArgList &Args) const override {
    return ToolChain::CST_Libcxx;
  }
  bool IsAArch64OutlineAtomicsDefault(const llvm::opt::ArgList &Args) const override {
    // Outline atomics for AArch64 are supported by compiler-rt
    return true;
  }

  void addClangTargetOptions(const llvm::opt::ArgList &DriverArgs,
                             llvm::opt::ArgStringList &CC1Args,
                             Action::OffloadKind DeviceOffloadKind) const override;

  void AddClangSystemIncludeArgs(const llvm::opt::ArgList &DriverArgs,
                                 llvm::opt::ArgStringList &CC1Args) const override;
  void AddClangCXXStdlibIncludeArgs(const llvm::opt::ArgList &DriverArgs,
                                    llvm::opt::ArgStringList &CC1Args) const override;
  void AddCXXStdlibLibArgs(const llvm::opt::ArgList &Args,
                           llvm::opt::ArgStringList &CmdArgs) const override;

  std::string computeSysRoot() const override { return SysRoot; }
  std::string getCompilerRT(const llvm::opt::ArgList &Args, StringRef Component,
                            FileType Type = ToolChain::FT_Static) const override;
  SanitizerMask getSupportedSanitizers() const override;
  const char *getDefaultLinker() const override { return DefaultLinker.c_str(); }

  Tool *buildAssembler() const override;
  Tool *buildLinker() const override;
  Tool *buildStaticLibTool() const override;

protected:
  std::string getMultiarchTriple(const llvm::Triple &T) const;
  std::string getMultiarchTriple(const Driver &D,
                                 const llvm::Triple &TargetTriple,
                                 StringRef SysRoot) const override;
  void addProfileRTLibs(const llvm::opt::ArgList &Args,
                             llvm::opt::ArgStringList &CmdArgs) const override;
};

} // end namespace toolchains
} // end namespace driver
} // end namespace clang

#endif // LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_Playbit_H
