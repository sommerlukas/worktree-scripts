#!/usr/bin/env zsh

# Example project hooks for worktree management
#
# This file demonstrates how to create project-specific hooks.
# Copy this file and rename it to match your project name.
# For example, if your project is named "myapp", create "myapp.sh"
#
# Hook functions are called at specific points in the worktree lifecycle:
# - init_hook: Called after 'wt init' in the main/src directory
# - create_hook: Called after 'wt create' in the new worktree's src directory
# - remove_hook: Called before 'wt remove' in the worktree's src directory
# - setup_hook: Called by 'wt setup' in the worktree's src directory

# Called after initializing a new project
# Working directory: <project-root>/main/src
init_hook() {
  echo "Example: Running init hook"

  # Common init tasks:
  # - Install dependencies
  # - Set up virtual environments
  # - Initialize databases
  # - Copy configuration files

  # Example for Node.js:
  # if [[ -f "package.json" ]]; then
  #   echo "Installing npm dependencies..."
  #   npm install
  # fi

  # Example for Python:
  # if [[ -f "requirements.txt" ]]; then
  #   echo "Creating virtual environment..."
  #   python3 -m venv ../venv
  #   source ../venv/bin/activate
  #   pip install -r requirements.txt
  # fi

  # Example for Rust:
  # if [[ -f "Cargo.toml" ]]; then
  #   echo "Building project..."
  #   cargo build
  # fi
}

# Called after creating a new worktree
# Working directory: <project-root>/<worktree-name>/src
create_hook() {
  echo "Example: Running create hook"

  # Common create tasks:
  # - Install dependencies (similar to init)
  # - Link to shared build artifacts
  # - Copy configuration from main worktree
  # - Set up worktree-specific configuration

  # Example: Copy config from main worktree
  # local main_config="../../main/src/.env.local"
  # if [[ -f "$main_config" ]]; then
  #   echo "Copying configuration from main worktree..."
  #   cp "$main_config" .env.local
  # fi

  # Example for Node.js: Link node_modules from main
  # if [[ -d "../../main/src/node_modules" ]]; then
  #   echo "Linking node_modules from main worktree..."
  #   ln -s ../../main/src/node_modules node_modules
  # else
  #   echo "Installing npm dependencies..."
  #   npm install
  # fi

  # Example: Use shared build directory
  # if [[ -d "../build" ]]; then
  #   echo "Build directory available at: ../build"
  # fi
}

# Called before removing a worktree
# Working directory: <project-root>/<worktree-name>/src
remove_hook() {
  echo "Example: Running remove hook"

  # Common remove tasks:
  # - Clean up build artifacts
  # - Back up important data
  # - Close database connections
  # - Clean up temporary files

  # Example: Clean build directory
  # if [[ -d "../build" ]]; then
  #   echo "Cleaning build directory..."
  #   rm -rf ../build/*
  # fi

  # Example: Back up local config
  # if [[ -f ".env.local" ]]; then
  #   echo "Backing up local configuration..."
  #   cp .env.local "$HOME/.worktree-backups/$(basename $PWD).env.local"
  # fi
}

# Called when setting up a worktree
# Working directory: <project-root>/<worktree-name>/src
setup_hook() {
  echo "Example: Running setup hook"

  # Common setup tasks:
  # - Rebuild dependencies
  # - Update configurations
  # - Reinitialize databases
  # - Clean and rebuild

  # Example for Node.js:
  # if [[ -f "package.json" ]]; then
  #   echo "Reinstalling npm dependencies..."
  #   rm -rf node_modules
  #   npm install
  # fi

  # Example for Python:
  # if [[ -f "requirements.txt" ]]; then
  #   echo "Updating virtual environment..."
  #   source ../venv/bin/activate
  #   pip install -r requirements.txt
  # fi

  # Example: Clean and rebuild
  # if [[ -d "../build" ]]; then
  #   echo "Cleaning build directory..."
  #   rm -rf ../build/*
  #   echo "Rebuilding..."
  #   make build
  # fi
}
