#!/usr/bin/env zsh

# Project hooks for IREE. 
#
# Hook functions are called at specific points in the worktree lifecycle:
# - init_hook: Called after 'wt init' in the main/src directory
# - create_hook: Called after 'wt create' in the new worktree's src directory
# - remove_hook: Called before 'wt remove' in the worktree's src directory
# - setup_hook: Called by 'wt setup' in the worktree's src directory

# Called after initializing a new project
# Working directory: <project-root>/main/src
init_hook() {
  echo "IREE: Running init hook"

  git submodule update --init

  echo "Finished IREE init hook"
}

# Called after creating a new worktree
# Working directory: <project-root>/<worktree-name>/src
create_hook() {
  echo "IREE: Running create hook"
  git submodule --quiet init
  local parent2=${PWD:A:h:h}
  local MAIN_IREE="$parent2/main/src"

  for submodule in $(git config get --file=.gitmodules --all --regexp path); do
    echo "Creating quasi-worktree of $submodule"
    git submodule update --reference "$MAIN_IREE/$submodule" "$submodule"
  done

  echo "Finished IREE create hook"
}

# Called before removing a worktree
# Working directory: <project-root>/<worktree-name>/src
remove_hook() {
  echo "IREE: Running remove hook"

  git submodule deinit --all --force
  rm -rf "$(git rev-parse --git-dir)/modules" || true

  echo "Finished IREE remove hook"
}

# Called when setting up a worktree
# Working directory: <project-root>/<worktree-name>/src
setup_hook() {
  echo "IREE: Running setup hook"
  
  local src_dir=${PWD}
  local root_dir=${PWD:A:h}
  local tree_name=${PWD:h:h:t}
  local build_dir="$root_dir/build"

  python3 -m venv "$root_dir/venv" --prompt "$tree_name"
  source $root_dir/venv/bin/activate
  pip install -r "$src_dir/runtime/bindings/python/iree/runtime/build_requirements.txt"

  pushd $root_dir
  echo "export CCACHE_BASEDIR=\"$root_dir\"" > .envrc
  echo "export CCACHE_NOHASHDIR=1" >> .envrc
  echo "export CCACHE_SLOPPINESS=include_file_mtime,include_file_ctime" >> .envrc
  echo "source \"$root_dir/venv/bin/activate\"" >> .envrc
  echo "source \"$build_dir/.env\" && export PYTHONPATH" >> .envrc
  echo "PATH_add \"$build_dir/tools\"" >> .envrc

  direnv allow "$root_dir"

  eval "$(direnv export zsh)"

  popd

  cmake -G Ninja -B $build_dir -S $src_dir \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DIREE_ENABLE_ASSERTIONS=ON \
    -DIREE_ENABLE_SPLIT_DWARF=ON \
    -DIREE_ENABLE_THIN_ARCHIVES=ON \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DIREE_ENABLE_LLD=ON \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DIREE_TARGET_BACKEND_ROCM=ON \
    -DIREE_HAL_DRIVER_HIP=ON \
    -DIREE_HIP_TEST_TARGET_CHIP=gfx942 \
    -DIREE_BUILD_PYTHON_BINDINGS=ON

  ln -sf "$build_dir/compile_commands.json" "$src_dir/compile_commands.json"
  ln -sf "$build_dir/tablegen_compile_commands.yaml" "$src_dir/tablegen_compile_commands.yaml"

  echo "Finished IREE setup hook"
}
