#!/usr/bin/env zsh

# Worktree Management Script
# Main command for managing git worktrees across multiple projects

set -o pipefail

# Color codes for output
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

# ============================================================================
# Helper Functions
# ============================================================================

# Print error message and exit
error() {
  echo "${RED}Error:${NC} $1" >&2
  exit "${2:-1}"
}

# Print warning message
warn() {
  echo "${YELLOW}Warning:${NC} $1" >&2
}

# Print success message
success() {
  echo "${GREEN}$1${NC}"
}

# Get the projects file path
get_projects_file() {
  local projects_dir="$HOME/.local/share/worktree-scripts"
  mkdir -p "$projects_dir"
  echo "$projects_dir/projects"
}

# Add project to the projects list
add_project_to_list() {
  local project_path="$1"
  local project_name="$2"
  local projects_file
  projects_file=$(get_projects_file)

  echo "$project_path:$project_name" >> "$projects_file"
}

# Remove project from the projects list
remove_project_from_list() {
  local project_path="$1"
  local projects_file
  projects_file=$(get_projects_file)

  if [[ -f "$projects_file" ]]; then
    # Create a temporary file without the project
    local temp_file="${projects_file}.tmp"
    grep -v "^${project_path}:" "$projects_file" > "$temp_file" || true
    mv "$temp_file" "$projects_file"
  fi
}

# Find the project root directory from current working directory
# Returns project_path and project_name via echo
find_project_root() {
  local projects_file
  projects_file=$(get_projects_file)

  if [[ ! -f "$projects_file" ]]; then
    error "Not in a project directory. No projects registered." 3
  fi

  local current_dir
  current_dir=$(realpath "$PWD")

  local resolved_project_path

  # Read projects file and check if current directory is within any project
  while IFS=: read -r project_path project_name; do
    # Resolve the project path in case it contains symlinks
    resolved_project_path=$(realpath "$project_path" 2>/dev/null || echo "$project_path")

    # Check if current directory starts with project path
    if [[ "$current_dir" == "$resolved_project_path"* ]]; then
      echo "$resolved_project_path"
      echo "$project_name"
      return 0
    fi
  done < "$projects_file"

  error "Not in a project directory. Current directory is not within any registered project." 3
}

# Get the main branch name (main or master)
get_main_branch() {
  local src_dir="$1"
  local main_branch

  cd "$src_dir" || error "Cannot access src directory: $src_dir"

  # Try to get the default branch from origin
  main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

  if [[ -z "$main_branch" ]]; then
    # Fallback: check if 'main' or 'master' exists
    if git show-ref --verify --quiet refs/heads/main; then
      main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
      main_branch="master"
    else
      error "Cannot determine main branch. Neither 'main' nor 'master' exists."
    fi
  fi

  echo "$main_branch"
}

# Run project-specific hook if it exists
run_hook() {
  local project_name="$1"
  local hook_name="$2"
  shift 2
  local hook_script="$WORKTREE_SCRIPTS_DIR/projects/${project_name}.sh"

  if [[ -f "$hook_script" ]]; then
    # Source the hook script
    source "$hook_script"

    # Check if the hook function exists
    local hook_function="${hook_name}_hook"
    if typeset -f "$hook_function" > /dev/null; then
      echo "Running ${hook_name} hook for ${project_name}..."
      "$hook_function" "$@"
    fi
  fi
}

tmux_session_exists() {
  local session_name="$1"

  command -v tmux > /dev/null 2>&1 || return 1
  tmux has-session -t "=${session_name}" 2>/dev/null
}

attach_or_switch_tmux_session() {
  local session_name="$1"

  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "=${session_name}" || error "Failed to switch to tmux session '$session_name'"
  else
    exec tmux attach-session -t "=${session_name}"
  fi
}

kill_tmux_session_for_worktree() {
  local worktree_name="$1"
  local session_name
  session_name=$(get_worktree_directory_name "$worktree_name")

  if tmux_session_exists "$session_name"; then
    echo "Killing tmux session '$session_name'..."
    tmux kill-session -t "=${session_name}" || warn "Failed to kill tmux session '$session_name'"
  fi
}

# Convert a branch name into the directory name used for its worktree.
get_worktree_directory_name() {
  local worktree_name="$1"
  echo "${worktree_name//\//_}"
}

get_worktree_path() {
  local project_root="$1"
  local worktree_name="$2"
  local directory_name
  directory_name=$(get_worktree_directory_name "$worktree_name")
  echo "$project_root/$directory_name"
}

# Check that a requested name identifies the branch checked out in a worktree.
# A normalized directory name is accepted as an alias, but a branch name that
# contains '/' must match exactly so it cannot target an underscore-named branch.
worktree_name_matches_branch() {
  local requested_name="$1"
  local branch_name="$2"

  if [[ "$requested_name" == "$branch_name" ]]; then
    return 0
  fi

  if [[ "$requested_name" != */* ]] && \
     [[ "$requested_name" == "$(get_worktree_directory_name "$branch_name")" ]]; then
    return 0
  fi

  return 1
}

validate_tmux_window_dir() {
  local worktree_path="$1"
  local relative_dir="$2"

  if [[ -z "$relative_dir" ]]; then
    error "tmux window directory cannot be empty"
  fi

  if [[ "$relative_dir" = /* ]]; then
    error "tmux window directory '$relative_dir' must be relative to the worktree"
  fi

  local worktree_root
  local resolved_dir
  worktree_root=$(realpath "$worktree_path") || error "Cannot resolve worktree path: $worktree_path"
  resolved_dir=$(realpath "$worktree_path/$relative_dir" 2>/dev/null) || error "tmux window directory '$relative_dir' does not exist under $worktree_path"

  if [[ "$resolved_dir" != "$worktree_root" && "$resolved_dir" != "$worktree_root"/* ]]; then
    error "tmux window directory '$relative_dir' escapes the worktree"
  fi

  echo "$resolved_dir"
}

get_tmux_windows() {
  local project_name="$1"
  local worktree_path="$2"
  local hook_script="$WORKTREE_SCRIPTS_DIR/projects/${project_name}.sh"
  local -a windows

  if [[ -f "$hook_script" ]]; then
    source "$hook_script"

    if typeset -f tmux_windows > /dev/null; then
      local line
      local window_name
      local relative_dir
      local resolved_dir
      while IFS= read -r line; do
        if [[ -z "$line" ]]; then
          continue
        fi

        if [[ "$line" != *:* ]]; then
          error "Invalid tmux window entry '$line'. Expected 'name:relative-directory'."
        fi

        window_name="${line%%:*}"
        relative_dir="${line#*:}"

        if [[ -z "$window_name" ]]; then
          error "tmux window name cannot be empty"
        fi

        if [[ "$window_name" == *:* ]]; then
          error "tmux window name '$window_name' cannot contain ':'"
        fi

        resolved_dir=$(validate_tmux_window_dir "$worktree_path" "$relative_dir") || return 1
        windows+=("${window_name}"$'\t'"${resolved_dir}")
      done < <(cd "$worktree_path" && tmux_windows)
    fi
  fi

  if [[ ${#windows[@]} -eq 0 ]]; then
    local default_dir
    default_dir=$(validate_tmux_window_dir "$worktree_path" "src") || return 1
    windows+=("src"$'\t'"${default_dir}")
  fi

  printf '%s\n' "${windows[@]}"
}

# Check if a worktree is valid
is_valid_worktree() {
  local project_root="$1"
  local worktree_name="$2"
  local worktree_path
  worktree_path=$(get_worktree_path "$project_root" "$worktree_name")

  # Check if directory exists
  if [[ ! -d "$worktree_path/src" ]]; then
    return 1
  fi

  # Check if it's in the git worktree list
  local main_src="$project_root/main/src"
  if [[ ! -d "$main_src" ]]; then
    return 1
  fi

  cd "$main_src" || return 1
  if ! git worktree list --porcelain | grep -Fqx "worktree $worktree_path/src"; then
    return 1
  fi

  local branch_name
  branch_name=$(git -C "$worktree_path/src" symbolic-ref --quiet --short HEAD) || return 1
  worktree_name_matches_branch "$worktree_name" "$branch_name"
}

# ============================================================================
# Command Implementations
# ============================================================================

# Initialize a new project
cmd_init() {
  if [[ $# -lt 2 || $# -gt 3 ]]; then
    error "Usage: wt init <project-name> <url> [directory-name]" 2
  fi

  local project_name="$1"
  local repo_url="$2"
  local directory_name="${3:-$project_name}"
  local initial_dir="$PWD"
  local project_path="$initial_dir/$directory_name"

  # Check if project directory already exists
  if [[ -e "$project_path" ]]; then
    error "Project directory '$directory_name' already exists in current directory."
  fi

  # Create directory structure
  echo "Creating project structure for '$directory_name'..."
  mkdir -p "$project_path/main" || error "Failed to create project directory"

  cd "$project_path/main" || error "Failed to enter project directory"

  # Clone repository
  echo "Cloning repository from $repo_url..."
  if ! git clone "$repo_url" src; then
    cd "$initial_dir" || error "Failed to return to initial directory after clone failure"
    rm -rf -- "$project_path"
    error "Failed to clone repository"
  fi

  # Get absolute path of project root
  project_path=$(realpath "..")

  # Add to projects list
  add_project_to_list "$project_path" "$project_name"

  # Run init hook
  cd src || error "Failed to enter src directory"
  run_hook "$project_name" "init"

  success "Project '$project_name' initialized successfully!"
  echo "Project location: $project_path"
}

# Delete current project
cmd_delete() {
  if [[ $# -ne 0 ]]; then
    error "Usage: wt delete" 2
  fi

  # Find project root
  local result
  result=$(find_project_root)
  local project_path
  local project_name
  project_path=$(echo "$result" | sed -n '1p')
  project_name=$(echo "$result" | sed -n '2p')

  # Ask for confirmation
  echo "Are you sure you want to delete project '$project_name' at $project_path? (y/N)"
  read -r response

  if [[ "$response" != "y" && "$response" != "Y" ]]; then
    echo "Deletion cancelled."
    exit 4
  fi

  # Remove from projects list
  remove_project_from_list "$project_path"

  # Delete directory
  echo "Deleting project directory..."
  rm -rf "$project_path"

  success "Project '$project_name' deleted successfully!"
}

# List all known projects
cmd_projects() {
  if [[ $# -ne 0 ]]; then
    error "Usage: wt projects" 2
  fi

  local projects_file
  projects_file=$(get_projects_file)

  if [[ ! -f "$projects_file" ]] || [[ ! -s "$projects_file" ]]; then
    echo "No projects found."
    return 0
  fi

  echo "Registered projects:"
  while IFS=: read -r project_path project_name; do
    echo "  $project_name : $project_path"
  done < "$projects_file"
}

# List worktrees in current project
cmd_list() {
  if [[ $# -ne 0 ]]; then
    error "Usage: wt list" 2
  fi

  # Find project root
  local result
  result=$(find_project_root)
  local project_path
  local project_name
  project_path=$(echo "$result" | sed -n '1p')
  project_name=$(echo "$result" | sed -n '2p')

  local main_src="$project_path/main/src"
  if [[ ! -d "$main_src" ]]; then
    error "Main worktree not found at $main_src"
  fi

  cd "$main_src" || error "Cannot access main worktree"

  echo "Worktrees for project '$project_name':"
  git worktree list
}

# Create a new worktree
cmd_create() {
  if [[ $# -lt 1 || $# -gt 2 ]]; then
    error "Usage: wt create <worktree-name> [base-branch]" 2
  fi

  local worktree_name="$1"
  local base_branch="${2:-}"

  # Find project root
  local result
  result=$(find_project_root)
  local project_path
  local project_name
  project_path=$(echo "$result" | sed -n '1p')
  project_name=$(echo "$result" | sed -n '2p')

  local directory_name
  local worktree_path
  directory_name=$(get_worktree_directory_name "$worktree_name")
  worktree_path=$(get_worktree_path "$project_path" "$worktree_name")

  # Check if worktree already exists
  if [[ -e "$worktree_path" ]]; then
    error "Worktree directory '$directory_name' already exists at $worktree_path"
  fi

  local main_src="$project_path/main/src"
  if [[ ! -d "$main_src" ]]; then
    error "Main worktree not found at $main_src"
  fi

  # Get main branch if base branch not provided
  if [[ -z "$base_branch" ]]; then
    base_branch=$(get_main_branch "$main_src")
  fi

  # Verify base branch exists
  cd "$main_src" || error "Cannot access main worktree"
  if ! git show-ref --verify --quiet "refs/heads/$base_branch" && \
     ! git show-ref --verify --quiet "refs/remotes/origin/$base_branch"; then
    error "Base branch '$base_branch' does not exist locally or on remote"
  fi

  # Create worktree directory
  mkdir -p "$worktree_path" || error "Failed to create worktree directory"

  # Check if branch exists and create worktree
  cd "$main_src" || error "Cannot access main worktree"

  # Fetch latest refs from remote to ensure we have up-to-date branch information
  echo "Fetching from remote..."
  git fetch origin --quiet 2>/dev/null || warn "Failed to fetch from remote, continuing anyway..."

  echo "Creating worktree '$worktree_name'..."

  # Check if branch exists locally
  if git show-ref --verify --quiet "refs/heads/$worktree_name"; then
    echo "Local branch '$worktree_name' exists, checking it out..."
    if ! git worktree add "$worktree_path/src" "$worktree_name"; then
      rmdir "$worktree_path" 2>/dev/null
      error "Failed to create worktree"
    fi
  # Check if branch exists on remote origin
  elif git show-ref --verify --quiet "refs/remotes/origin/$worktree_name"; then
    echo "Remote branch 'origin/$worktree_name' exists, checking it out..."
    if ! git worktree add --track -b "$worktree_name" "$worktree_path/src" "origin/$worktree_name"; then
      rmdir "$worktree_path" 2>/dev/null
      error "Failed to create worktree"
    fi
  # Branch doesn't exist anywhere, create new from base branch
  else
    echo "Creating new branch '$worktree_name' from '$base_branch'..."
    if ! git worktree add -b "$worktree_name" "$worktree_path/src" "$base_branch"; then
      rmdir "$worktree_path" 2>/dev/null
      error "Failed to create worktree"
    fi
  fi

  # Create sibling directories
  mkdir -p "$worktree_path/build"
  mkdir -p "$worktree_path/local"

  # Run create hook
  cd "$worktree_path/src" || error "Cannot access worktree src directory"
  run_hook "$project_name" "create"

  success "Worktree '$worktree_name' created successfully!"
  echo "Worktree location: $worktree_path"
}

# Create, set up, and open a worktree in tmux
cmd_start() {
  if [[ $# -ne 1 ]]; then
    error "Usage: wt start <worktree-name>" 2
  fi

  local worktree_name="$1"

  cmd_create "$worktree_name"
  cmd_setup "$worktree_name"
  cmd_tmux "$worktree_name"
}

# Start or attach to a tmux session for a worktree
cmd_tmux() {
  if [[ $# -ne 1 ]]; then
    error "Usage: wt tmux <worktree-name>" 2
  fi

  if ! command -v tmux > /dev/null 2>&1; then
    error "tmux is required but not found in PATH"
  fi

  local worktree_name="$1"

  # Find project root
  local result
  result=$(find_project_root)
  local project_path
  local project_name
  project_path=$(echo "$result" | sed -n '1p')
  project_name=$(echo "$result" | sed -n '2p')

  # Validate worktree exists
  if ! is_valid_worktree "$project_path" "$worktree_name"; then
    error "Worktree '$worktree_name' does not exist or is not valid"
  fi

  local worktree_path
  local session_name
  worktree_path=$(get_worktree_path "$project_path" "$worktree_name")
  session_name=$(get_worktree_directory_name "$worktree_name")

  if tmux_session_exists "$session_name"; then
    echo "Attaching to existing tmux session '$session_name'..."
    attach_or_switch_tmux_session "$session_name"
    return 0
  fi

  local -a window_names
  local -a window_dirs
  local window_name
  local window_dir
  local tmux_window_output

  tmux_window_output=$(get_tmux_windows "$project_name" "$worktree_path") || error "Failed to get tmux window configuration for worktree '$worktree_name'"

  while IFS=$'\t' read -r window_name window_dir; do
    window_names+=("$window_name")
    window_dirs+=("$window_dir")
  done <<< "$tmux_window_output"

  if [[ ${#window_names[@]} -eq 0 ]]; then
    error "No tmux windows configured for worktree '$worktree_name'"
  fi

  echo "Creating tmux session '$session_name'..."

  local first_pane
  local first_window_dir
  first_window_dir=$(printf "%q" "${window_dirs[1]}")
  first_pane=$(tmux new-session -d -P -F '#{pane_id}' -s "$session_name" -c "$worktree_path" -n "${window_names[1]}") || error "Failed to create tmux session '$session_name'"
  tmux send-keys -t "$first_pane" "cd $first_window_dir" C-m || error "Failed to initialize first tmux window"

  local i
  for (( i = 2; i <= ${#window_names[@]}; i++ )); do
    tmux new-window -d -t "=${session_name}" -c "${window_dirs[$i]}" -n "${window_names[$i]}" || error "Failed to create tmux window '${window_names[$i]}'"
  done

  attach_or_switch_tmux_session "$session_name"
}

# Internal function to remove a worktree (no confirmation)
# Args: project_path, project_name, worktree_name
# Returns: 0 on success, 1 on failure
remove_worktree_impl() {
  local project_path="$1"
  local project_name="$2"
  local worktree_name="$3"
  local worktree_path
  worktree_path=$(get_worktree_path "$project_path" "$worktree_name")

  # Stop any tmux session before hooks or filesystem removal.
  kill_tmux_session_for_worktree "$worktree_name"

  # Run remove hook
  if [[ -d "$worktree_path/src" ]]; then
    cd "$worktree_path/src" || warn "Cannot access worktree src directory for hook"
    run_hook "$project_name" "remove"
  fi

  # Remove git worktree
  local main_src="$project_path/main/src"
  cd "$main_src" || return 1

  echo "Removing git worktree..."
  if ! git worktree remove "$worktree_path/src" 2>/dev/null; then
    warn "Failed to remove git worktree, trying with --force"
    git worktree remove --force "$worktree_path/src" 2>/dev/null || {
      warn "Failed to remove git worktree"
      return 1
    }
  fi

  # Delete worktree directory
  echo "Deleting worktree directory..."
  rm -rf "$worktree_path"

  return 0
}

# Remove a worktree
cmd_remove() {
  if [[ $# -ne 1 ]]; then
    error "Usage: wt remove <worktree-name>" 2
  fi

  local worktree_name="$1"

  # Cannot remove main
  if [[ "$worktree_name" == "main" ]]; then
    error "Cannot remove the 'main' worktree"
  fi

  # Find project root
  local result
  result=$(find_project_root)
  local project_path
  local project_name
  project_path=$(echo "$result" | sed -n '1p')
  project_name=$(echo "$result" | sed -n '2p')

  # Validate worktree exists
  if ! is_valid_worktree "$project_path" "$worktree_name"; then
    error "Worktree '$worktree_name' does not exist or is not valid"
  fi

  local worktree_path
  worktree_path=$(get_worktree_path "$project_path" "$worktree_name")

  # Ask for confirmation
  echo "Are you sure you want to remove worktree '$worktree_name'? (y/N)"
  read -r response

  if [[ "$response" != "y" && "$response" != "Y" ]]; then
    echo "Removal cancelled."
    exit 4
  fi

  # Call helper function
  if remove_worktree_impl "$project_path" "$project_name" "$worktree_name"; then
    success "Worktree '$worktree_name' removed successfully!"
  else
    error "Failed to remove worktree '$worktree_name'"
  fi
}

# Setup a worktree
cmd_setup() {
  if [[ $# -lt 1 ]]; then
    error "Usage: wt setup <worktree-name> [project-options...]" 2
  fi

  local worktree_name="$1"
  shift

  # Find project root
  local result
  result=$(find_project_root)
  local project_path
  local project_name
  project_path=$(echo "$result" | sed -n '1p')
  project_name=$(echo "$result" | sed -n '2p')

  # Validate worktree exists
  if ! is_valid_worktree "$project_path" "$worktree_name"; then
    error "Worktree '$worktree_name' does not exist or is not valid"
  fi

  local worktree_path
  worktree_path=$(get_worktree_path "$project_path" "$worktree_name")

  # Run setup hook
  cd "$worktree_path/src" || error "Cannot access worktree src directory"
  run_hook "$project_name" "setup" "$@" || error "Setup hook failed for worktree '$worktree_name'"

  success "Setup complete for worktree '$worktree_name'!"
}

# Rebase a worktree on origin/main
cmd_rebase() {
  if [[ $# -lt 1 || $# -gt 2 ]]; then
    error "Usage: wt rebase <worktree-name> [base-branch]" 2
  fi

  local worktree_name="$1"
  local base_branch="${2:-}"

  # Find project root
  local result
  result=$(find_project_root)
  local project_path
  local project_name
  project_path=$(echo "$result" | sed -n '1p')
  project_name=$(echo "$result" | sed -n '2p')

  local main_src="$project_path/main/src"

  # Get main branch name if base branch not provided
  if [[ -z "$base_branch" ]]; then
    base_branch=$(get_main_branch "$main_src")
  fi

  # Cannot rebase main
  if [[ "$worktree_name" == "main" ]]; then
    error "Cannot rebase the 'main' worktree (tracking branch: $base_branch)"
  fi

  # Validate worktree exists
  if ! is_valid_worktree "$project_path" "$worktree_name"; then
    error "Worktree '$worktree_name' does not exist or is not valid"
  fi

  local worktree_path
  worktree_path=$(get_worktree_path "$project_path" "$worktree_name")

  # Fetch from origin (without updating main worktree)
  echo "Fetching from origin..."
  cd "$main_src" || error "Cannot access main worktree"
  git fetch origin --quiet 2>/dev/null || warn "Failed to fetch from remote, continuing anyway..."

  # Verify base branch exists
  if ! git show-ref --verify --quiet "refs/heads/$base_branch" && \
     ! git show-ref --verify --quiet "refs/remotes/origin/$base_branch"; then
    error "Base branch '$base_branch' does not exist locally or on remote"
  fi

  # Rebase the worktree
  cd "$worktree_path/src" || error "Cannot access worktree src directory"

  echo "Rebasing '$worktree_name' on 'origin/$base_branch'..."
  if git rebase "origin/$base_branch"; then
    # Run rebase hook
    run_hook "$project_name" "rebase"

    success "Worktree '$worktree_name' successfully rebased on 'origin/$base_branch'!"
  else
    warn "Rebase encountered conflicts. Resolve them manually, then run:"
    warn "  git rebase --continue"
    warn "Or abort with:"
    warn "  git rebase --abort"
    exit 1
  fi
}

# Sweep and remove stale worktrees
cmd_sweep() {
  if [[ $# -ne 0 ]]; then
    error "Usage: wt sweep" 2
  fi

  # Find project root
  local result
  result=$(find_project_root)
  local project_path
  local project_name
  project_path=$(echo "$result" | sed -n '1p')
  project_name=$(echo "$result" | sed -n '2p')

  local main_src="$project_path/main/src"
  if [[ ! -d "$main_src" ]]; then
    error "Main worktree not found at $main_src"
  fi

  cd "$main_src" || error "Cannot access main worktree"

  # Fetch latest refs to ensure accurate remote branch checking
  echo "Fetching latest refs from remote..."
  git fetch origin --prune --quiet 2>/dev/null || warn "Failed to fetch from remote, continuing anyway..."

  # Collect stale worktrees
  local -a stale_worktrees
  local -A stale_reasons

  # Parse worktree list
  local current_worktree=""
  local current_branch=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
      current_worktree="${match[1]}"
    elif [[ "$line" =~ ^branch\ refs/heads/(.+)$ ]]; then
      current_branch="${match[1]}"

      local worktree_name="$current_branch"
      local worktree_path
      worktree_path=$(get_worktree_path "$project_path" "$worktree_name")

      # Skip main
      if [[ "$worktree_name" == "main" ]]; then
        continue
      fi

      local stale=false
      local reason=""

      # Check criterion 1: Remote branch deleted
      local upstream
      upstream=$(git -C "$current_worktree" rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null || echo "")

      if [[ -n "$upstream" ]]; then
        # Has upstream, check if remote branch still exists
        if ! git show-ref --verify --quiet "refs/remotes/origin/$current_branch"; then
          stale=true
          reason="Remote branch deleted (likely merged PR)"
        fi
      else
        # Check criterion 2: Local-only and inactive for 4 weeks
        local last_modified
        last_modified=$(find "$worktree_path" -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1)

        if [[ -n "$last_modified" ]]; then
          local current_time=$(date +%s)
          # Convert to integer (remove decimal part)
          last_modified=${last_modified%.*}
          local age=$((current_time - last_modified))
          local four_weeks=2419200

          if [[ $age -gt $four_weeks ]]; then
            stale=true
            local weeks=$((age / 604800))
            reason="Local-only, inactive for $weeks weeks"
          fi
        fi
      fi

      if [[ "$stale" == "true" ]]; then
        stale_worktrees+=("$worktree_name")
        stale_reasons[$worktree_name]="$reason"
      fi
    fi
  done < <(git worktree list --porcelain)

  # Check if any stale worktrees found
  if [[ ${#stale_worktrees[@]} -eq 0 ]]; then
    echo "No stale worktrees found."
    return 0
  fi

  # Display found stale worktrees
  echo ""
  echo "Found ${#stale_worktrees[@]} stale worktree(s):"
  for worktree in "${stale_worktrees[@]}"; do
    echo "  ${YELLOW}$worktree${NC}: ${stale_reasons[$worktree]}"
  done
  echo ""

  # Ask for confirmation for each worktree
  local removed_count=0
  local skipped_count=0

  for worktree_name in "${stale_worktrees[@]}"; do
    echo "Remove worktree '${YELLOW}$worktree_name${NC}'?"
    echo "  Reason: ${stale_reasons[$worktree_name]}"
    echo -n "  (y/N): "
    read -r response

    if [[ "$response" == "y" || "$response" == "Y" ]]; then
      # Call helper function
      if remove_worktree_impl "$project_path" "$project_name" "$worktree_name"; then
        success "  Removed '$worktree_name'"
        ((removed_count++))
      else
        warn "  Failed to remove '$worktree_name'"
        ((skipped_count++))
      fi
    else
      echo "  Skipped."
      ((skipped_count++))
    fi
    echo ""
  done

  # Summary
  echo ""
  success "Sweep complete: $removed_count removed, $skipped_count skipped"
}

# Update the worktree scripts installation
cmd_update() {
  if [[ $# -ne 0 ]]; then
    error "Usage: wt update" 2
  fi

  # Check if WORKTREE_SCRIPTS_DIR exists
  if [[ ! -d "$WORKTREE_SCRIPTS_DIR" ]]; then
    error "Installation directory not found at $WORKTREE_SCRIPTS_DIR"
  fi

  echo "Updating worktree scripts from $WORKTREE_SCRIPTS_DIR..."

  # Change to installation directory
  cd "$WORKTREE_SCRIPTS_DIR" || error "Cannot access installation directory"

  # Check if it's a git repository
  if [[ ! -d ".git" ]]; then
    error "Installation directory is not a git repository"
  fi

  # Check for local modifications
  if [[ -n "$(git status --porcelain)" ]]; then
    error "Local modifications detected. Please commit or stash your changes before updating."
  fi

  # Check for unpushed commits
  if git rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
    local unpushed
    unpushed=$(git rev-list @{u}..HEAD 2>/dev/null | wc -l)
    if [[ $unpushed -gt 0 ]]; then
      error "Local commits not pushed to remote. Please push or reset before updating."
    fi
  fi

  # Fetch from remote
  echo "Fetching from remote..."
  if ! git fetch origin --quiet; then
    error "Failed to fetch from remote"
  fi

  # Check if behind remote
  local behind
  if git rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
    behind=$(git rev-list HEAD..@{u} 2>/dev/null | wc -l)
  else
    error "No upstream tracking branch configured"
  fi

  if [[ $behind -eq 0 ]]; then
    success "Worktree scripts are already up-to-date!"
  else
    echo "Pulling $behind new commit(s)..."
    if git pull --quiet; then
      success "Worktree scripts updated successfully!"
      echo "The updated scripts are now available."
    else
      error "Failed to pull updates"
    fi
  fi
}

# Show usage information
cmd_help() {
  if [[ $# -gt 1 ]]; then
    error "Usage: wt help [project-name]" 2
  fi

  if [[ $# -eq 1 ]]; then
    local project_name="$1"
    local hook_script="$WORKTREE_SCRIPTS_DIR/projects/${project_name}.sh"

    if [[ ! -f "$hook_script" ]]; then
      error "No project help found for '$project_name'" 2
    fi

    source "$hook_script"

    if typeset -f help_hook > /dev/null; then
      help_hook
    else
      echo "No project-specific help is available for '$project_name'."
    fi
    return 0
  fi

  cat << EOF
Worktree Management Tool

Usage: wt <command> [arguments]

Commands:
  init <project-name> <url> [directory-name]
                                    Initialize a new project
  delete                            Delete the current project
  projects                          List all registered projects
  list                              List worktrees in current project
  create <worktree-name> [base]     Create a new worktree (optionally from base branch)
  start <worktree-name>             Create, set up, and open a worktree in tmux
  tmux <worktree-name>              Start or attach to a tmux session for a worktree
  remove <worktree-name>            Remove a worktree
  setup <worktree-name> [options]   Run setup hooks for a worktree
  rebase <worktree-name> [base]     Rebase a worktree (optionally on base branch)
  sweep                             Remove stale worktrees (merged or inactive)
  update                            Update the worktree scripts installation
  help [project-name]               Show this help message or project-specific help

For more information, see the README.
EOF
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
  # Check if git is available
  if ! command -v git &> /dev/null; then
    error "git is required but not found in PATH"
  fi

  # Check if WORKTREE_SCRIPTS_DIR is set
  if [[ -z "$WORKTREE_SCRIPTS_DIR" ]]; then
    error "WORKTREE_SCRIPTS_DIR environment variable is not set. Did you run bootstrap.sh?"
  fi

  # Parse command
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    init)
      cmd_init "$@"
      ;;
    delete)
      cmd_delete "$@"
      ;;
    projects)
      cmd_projects "$@"
      ;;
    list)
      cmd_list "$@"
      ;;
    create)
      cmd_create "$@"
      ;;
    start)
      cmd_start "$@"
      ;;
    tmux)
      cmd_tmux "$@"
      ;;
    remove)
      cmd_remove "$@"
      ;;
    setup)
      cmd_setup "$@"
      ;;
    rebase)
      cmd_rebase "$@"
      ;;
    sweep)
      cmd_sweep "$@"
      ;;
    update)
      cmd_update "$@"
      ;;
    help|--help|-h)
      cmd_help "$@"
      ;;
    *)
      error "Unknown command: $cmd\n\nRun 'wt help' for usage information." 2
      ;;
  esac
}

main "$@"
