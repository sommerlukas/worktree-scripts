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

  # Read projects file and check if current directory is within any project
  while IFS=: read -r project_path project_name; do
    # Resolve the project path in case it contains symlinks
    local resolved_project_path
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
  local hook_script="$WORKTREE_SCRIPTS_DIR/projects/${project_name}.sh"

  if [[ -f "$hook_script" ]]; then
    # Source the hook script
    source "$hook_script"

    # Check if the hook function exists
    local hook_function="${hook_name}_hook"
    if typeset -f "$hook_function" > /dev/null; then
      echo "Running ${hook_name} hook for ${project_name}..."
      "$hook_function"
    fi
  fi
}

# Check if a worktree is valid
is_valid_worktree() {
  local project_root="$1"
  local worktree_name="$2"
  local worktree_path="$project_root/$worktree_name"

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
  if git worktree list | grep -q "$worktree_path/src"; then
    return 0
  else
    return 1
  fi
}

# ============================================================================
# Command Implementations
# ============================================================================

# Initialize a new project
cmd_init() {
  if [[ $# -ne 2 ]]; then
    error "Usage: wt init <project-name> <url>" 2
  fi

  local project_name="$1"
  local repo_url="$2"

  # Check if project directory already exists
  if [[ -d "$project_name" ]]; then
    error "Project directory '$project_name' already exists in current directory."
  fi

  # Create directory structure
  echo "Creating project structure for '$project_name'..."
  mkdir -p "$project_name/main" || error "Failed to create project directory"

  cd "$project_name/main" || error "Failed to enter project directory"

  # Clone repository
  echo "Cloning repository from $repo_url..."
  if ! git clone "$repo_url" src; then
    cd ../..
    rm -rf "$project_name"
    error "Failed to clone repository"
  fi

  # Get absolute path of project root
  local project_path
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
  if [[ $# -ne 1 ]]; then
    error "Usage: wt create <worktree-name>" 2
  fi

  local worktree_name="$1"

  # Find project root
  local result
  result=$(find_project_root)
  local project_path
  local project_name
  project_path=$(echo "$result" | sed -n '1p')
  project_name=$(echo "$result" | sed -n '2p')

  local worktree_path="$project_path/$worktree_name"

  # Check if worktree already exists
  if [[ -d "$worktree_path" ]]; then
    error "Worktree directory '$worktree_name' already exists at $worktree_path"
  fi

  local main_src="$project_path/main/src"
  if [[ ! -d "$main_src" ]]; then
    error "Main worktree not found at $main_src"
  fi

  # Get main branch
  local main_branch
  main_branch=$(get_main_branch "$main_src")

  # Create worktree directory
  mkdir -p "$worktree_path" || error "Failed to create worktree directory"

  # Check if branch exists and create worktree
  cd "$main_src" || error "Cannot access main worktree"

  echo "Creating worktree '$worktree_name'..."
  if git show-ref --verify --quiet "refs/heads/$worktree_name"; then
    echo "Branch '$worktree_name' exists, checking it out..."
    if ! git worktree add "$worktree_path/src" "$worktree_name"; then
      rmdir "$worktree_path" 2>/dev/null
      error "Failed to create worktree"
    fi
  else
    echo "Creating new branch '$worktree_name' from '$main_branch'..."
    if ! git worktree add -b "$worktree_name" "$worktree_path/src" "$main_branch"; then
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

  local worktree_path="$project_path/$worktree_name"

  # Ask for confirmation
  echo "Are you sure you want to remove worktree '$worktree_name'? (y/N)"
  read -r response

  if [[ "$response" != "y" && "$response" != "Y" ]]; then
    echo "Removal cancelled."
    exit 4
  fi

  # Run remove hook
  cd "$worktree_path/src" || warn "Cannot access worktree src directory for hook"
  run_hook "$project_name" "remove"

  # Remove git worktree
  local main_src="$project_path/main/src"
  cd "$main_src" || error "Cannot access main worktree"

  echo "Removing git worktree..."
  if ! git worktree remove "$worktree_path/src"; then
    warn "Failed to remove git worktree, trying with --force"
    git worktree remove --force "$worktree_path/src" || error "Failed to remove git worktree"
  fi

  # Delete worktree directory
  echo "Deleting worktree directory..."
  rm -rf "$worktree_path"

  success "Worktree '$worktree_name' removed successfully!"
}

# Setup a worktree
cmd_setup() {
  if [[ $# -ne 1 ]]; then
    error "Usage: wt setup <worktree-name>" 2
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

  local worktree_path="$project_path/$worktree_name"

  # Run setup hook
  cd "$worktree_path/src" || error "Cannot access worktree src directory"
  run_hook "$project_name" "setup"

  success "Setup complete for worktree '$worktree_name'!"
}

# Show usage information
cmd_help() {
  cat << EOF
Worktree Management Tool

Usage: wt <command> [arguments]

Commands:
  init <project-name> <url>    Initialize a new project
  delete                       Delete the current project
  projects                     List all registered projects
  list                         List worktrees in current project
  create <worktree-name>       Create a new worktree
  remove <worktree-name>       Remove a worktree
  setup <worktree-name>        Run setup hooks for a worktree
  help                         Show this help message

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
    remove)
      cmd_remove "$@"
      ;;
    setup)
      cmd_setup "$@"
      ;;
    help|--help|-h)
      cmd_help
      ;;
    *)
      error "Unknown command: $cmd\n\nRun 'wt help' for usage information." 2
      ;;
  esac
}

main "$@"
