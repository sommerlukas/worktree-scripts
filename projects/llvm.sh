#!/usr/bin/env zsh

# Project hooks for upstream LLVM.
#
# Hook functions are called at specific points in the worktree lifecycle:
# - init_hook: Called after 'wt init' in the main/src directory
# - create_hook: Called after 'wt create' in the new worktree's src directory
# - remove_hook: Called before 'wt remove' in the worktree's src directory
# - setup_hook: Called by 'wt setup' in the worktree's src directory
# - rebase_hook: Called after 'wt rebase' (only on success) in the worktree's src directory

# Called when setting up a worktree
# Working directory: <project-root>/<worktree-name>/src
setup_hook() {
  echo "LLVM: Running setup hook"
  
  local src_dir=${PWD}
  local root_dir=${PWD:A:h}
  local build_dir="$src_dir/build"

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
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DLLVM_ENABLE_LLD=ON \
    -DLLVM_CCACHE_BUILD=ON \
    -DCLANG_DEFAULT_LINKER=lld \
    -DLLVM_BUILD_TESTS=ON \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DLLVM_USE_SPLIT_DWARF=ON \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt" \
    -DLLVM_OPTIMIZED_TABLEGEN=ON

  echo "Finished LLVM setup hook"
}
