#!/usr/bin/env zsh

# Bootstrap script for Worktree Scripts
# This script installs the worktree management tools

set -e

# Color codes for output
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# Print error message and exit
error() {
  echo "${RED}Error:${NC} $1" >&2
  exit 1
}

# Print success message
success() {
  echo "${GREEN}$1${NC}"
}

# Print info message
info() {
  echo "${BLUE}$1${NC}"
}

# Installation directory
INSTALL_DIR="$HOME/.worktree-scripts"
ZSHRC="$HOME/.zshrc"
DEFAULT_REPO_URL="https://github.com/sommerlukas/worktree-scripts.git"

main() {
  echo "Worktree Scripts Bootstrap"
  echo "=========================="
  echo

  # Check if already installed
  if [[ -d "$INSTALL_DIR" ]]; then
    error "Installation directory $INSTALL_DIR already exists.\nPlease remove it first or use a different location."
  fi

  # Get repository URL (use default if not provided)
  local repo_url="${1:-$DEFAULT_REPO_URL}"

  if [[ "$repo_url" == "$DEFAULT_REPO_URL" ]]; then
    info "Using default repository: $repo_url"
  fi

  # Clone repository
  info "Cloning repository from $repo_url..."
  if ! git clone "$repo_url" "$INSTALL_DIR"; then
    error "Failed to clone repository"
  fi

  # Create projects directory for hooks
  info "Creating projects directory..."
  mkdir -p "$INSTALL_DIR/projects"

  # Make main script executable
  info "Making scripts executable..."
  chmod +x "$INSTALL_DIR/wt.sh"
  chmod +x "$INSTALL_DIR/bootstrap.sh"

  # Check if .zshrc exists
  if [[ ! -f "$ZSHRC" ]]; then
    warn "~/.zshrc does not exist. Creating it..."
    touch "$ZSHRC"
  fi

  # Check if already configured
  if grep -q "WORKTREE_SCRIPTS_DIR" "$ZSHRC"; then
    info "Configuration already exists in ~/.zshrc, skipping..."
  else
    info "Adding configuration to ~/.zshrc..."
    cat >> "$ZSHRC" << 'EOF'

# Worktree Scripts
export WORKTREE_SCRIPTS_DIR="$HOME/.worktree-scripts"
alias wt="$WORKTREE_SCRIPTS_DIR/wt.sh"
EOF
  fi

  # Print success message
  echo
  success "✓ Worktree scripts installed successfully!"
  echo
  echo "Next steps:"
  echo "  1. Run: ${BLUE}source ~/.zshrc${NC}"
  echo "     or restart your terminal"
  echo
  echo "  2. Use: ${BLUE}wt <command>${NC}"
  echo "     Run '${BLUE}wt help${NC}' for available commands"
  echo
  echo "  3. Place project-specific hooks in:"
  echo "     ${BLUE}~/.worktree-scripts/projects/<project-name>.sh${NC}"
  echo
}

main "$@"
