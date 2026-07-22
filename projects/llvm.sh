#!/usr/bin/env zsh

# Project hooks for upstream LLVM.
#
# Hook functions are called at specific points in the worktree lifecycle:
# - init_hook: Called after 'wt init' in the main/src directory
# - create_hook: Called after 'wt create' in the new worktree's src directory
# - remove_hook: Called before 'wt remove' in the worktree's src directory
# - setup_hook: Called by 'wt setup' in the worktree's src directory
# - rebase_hook: Called after 'wt rebase' (only on success) in the worktree's src directory

tmux_windows() {
  echo "source:src"
  echo "build:src/build"
  echo "local:local"
  echo "agent:."
}

help_hook() {
  cat << EOF
LLVM project help

Usage:
  wt setup <worktree-name>             Configure LLVM with clang/clang++ and LLD
  wt setup <worktree-name> --use-gcc   Configure LLVM with gcc/g++

Setup options:
  --use-gcc   Use gcc and g++ instead of clang and clang++.

By default, LLVM setup resolves clang and clang++ from PATH before updating the
worktree environment, then passes those absolute paths to CMake. It also enables
LLD with LLVM_ENABLE_LLD=ON and CLANG_DEFAULT_LINKER=lld.

With --use-gcc, LLVM setup resolves gcc and g++ from PATH and passes those
absolute paths to CMake. The clang/LLD-specific linker options are omitted.
EOF
}

resolve_compiler() {
  local compiler="$1"
  local compiler_path

  compiler_path=$(which "$compiler" 2>/dev/null) || {
    echo "Error: required compiler '$compiler' was not found in PATH" >&2
    return 1
  }

  if [[ -z "$compiler_path" ]]; then
    echo "Error: required compiler '$compiler' was not found in PATH" >&2
    return 1
  fi

  echo "$compiler_path"
}

# Called when setting up a worktree
# Working directory: <project-root>/<worktree-name>/src
setup_hook() {
  echo "LLVM: Running setup hook"

  local use_gcc=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --use-gcc)
        use_gcc=1
        ;;
      --help|-h)
        help_hook
        return 0
        ;;
      *)
        echo "Error: unknown LLVM setup option '$1'" >&2
        echo "Run 'wt help llvm' for usage information." >&2
        return 2
        ;;
    esac
    shift
  done
  
  local src_dir=${PWD}
  local root_dir=${PWD:A:h}
  local build_dir="$src_dir/build"
  local c_compiler="clang"
  local cxx_compiler="clang++"
  local -a linker_args

  if [[ "$use_gcc" -eq 1 ]]; then
    c_compiler="gcc"
    cxx_compiler="g++"
  else
    linker_args=(
      -DLLVM_ENABLE_LLD=ON
      -DCLANG_DEFAULT_LINKER=lld
    )
  fi

  local c_compiler_path
  local cxx_compiler_path
  c_compiler_path=$(resolve_compiler "$c_compiler") || return 1
  cxx_compiler_path=$(resolve_compiler "$cxx_compiler") || return 1

  pushd $root_dir
  echo "PATH_add \"$build_dir/bin\"" >> .envrc
  direnv allow "$root_dir"
  eval "$(direnv export zsh)"
  popd

  cmake -G Ninja -B $build_dir -S $src_dir/llvm \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DBUILD_SHARED_LIBS=ON \
    -DLLVM_ENABLE_PROJECTS="llvm;clang;lld" \
    -DLLVM_BUILD_EXAMPLES=ON \
    -DLLVM_TARGETS_TO_BUILD="X86;NVPTX;AMDGPU" \
    -DCMAKE_C_COMPILER="$c_compiler_path" \
    -DCMAKE_CXX_COMPILER="$cxx_compiler_path" \
    -DLLVM_CCACHE_BUILD=ON \
    "${linker_args[@]}" \
    -DLLVM_BUILD_TESTS=ON \
    -DLLVM_LIT_ARGS="-j32 -sv" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DLLVM_USE_SPLIT_DWARF=ON \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt" \
    -DLLVM_OPTIMIZED_TABLEGEN=ON

  echo "Finished LLVM setup hook"
}
