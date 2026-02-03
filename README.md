# Worktree Scripts

A set of zsh scripts to ease management of git worktrees across multiple projects.

## Overview

This tool provides a simple command-line interface (`wt`) for managing git worktrees with a standardized directory structure and support for project-specific hooks.

### Key Features

- **Project Management**: Initialize, track, and delete projects with ease
- **Worktree Management**: Create, list, remove, and setup worktrees within projects
- **Standardized Structure**: Consistent directory layout with `src`, `build`, and `local` directories
- **Hook System**: Run project-specific scripts at key lifecycle events
- **Multi-Project Support**: Track and work with multiple projects simultaneously

### Directory Structure

Each project follows this structure:

```
<project-name>/               # Project root
├── main/                     # Main worktree
│   ├── src/                 # Git repository (original clone)
│   ├── build/               # Build artifacts (created by hooks)
│   └── local/               # Local files (created by hooks)
├── feature-1/               # Additional worktrees
│   ├── src/                 # Git worktree (separate branch)
│   ├── build/               # Worktree-specific build artifacts
│   └── local/               # Worktree-specific local files
└── feature-2/
    └── ...
```

## Installation

### Quick Install

Install with a single command:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/sommerlukas/worktree-scripts/main/bootstrap.sh)"
```

After installation, reload your shell:

```bash
source ~/.zshrc
```

### Manual Install

1. Clone the repository and run the bootstrap script:

```bash
git clone https://github.com/sommerlukas/worktree-scripts.git
cd worktree-scripts
./bootstrap.sh
```

To use a different repository, provide the URL as an argument:

```bash
./bootstrap.sh https://github.com/yourusername/worktree-scripts.git
```

2. Reload your shell configuration:

```bash
source ~/.zshrc
```

3. Verify installation:

```bash
wt help
```

### What the bootstrap script does:
- Clone the repository to `~/.worktree-scripts`
- Create a `projects/` directory for hook scripts
- Add `WORKTREE_SCRIPTS_DIR` environment variable to `~/.zshrc`
- Create an alias `wt` for the main script

## Usage

### Initialize a New Project

Create a new project by cloning a repository:

```bash
wt init <project-name> <git-url>
```

Example:

```bash
wt init myapp https://github.com/user/myapp.git
```

This will:
- Create a directory structure: `myapp/main/src/`
- Clone the repository into `src`
- Register the project
- Run the `init_hook` if available

### List All Projects

View all registered projects:

```bash
wt projects
```

### Create a Worktree

From within a project directory, create a new worktree:

```bash
cd myapp
wt create feature-branch
```

To create a worktree based on a different branch instead of main:

```bash
wt create feature-branch develop
```

This will:
- Fetch latest refs from remote origin
- Create a new directory: `myapp/feature-branch/`
- Create a git worktree in `feature-branch/src/`
- Create `build/` and `local/` directories
- Run the `create_hook` if available

**Branch selection priority:**
1. If `feature-branch` exists locally, it will be checked out
2. If `feature-branch` exists on remote origin, it will be checked out from origin
3. If the branch doesn't exist anywhere, it will be created from the specified base branch (defaults to `main` or `master` if not specified)

**Note**: The base branch must exist locally or on remote, otherwise an error will be shown.

### List Worktrees

Show all worktrees in the current project:

```bash
wt list
```

### Setup a Worktree

Run setup hooks for a specific worktree:

```bash
wt setup feature-branch
```

This is useful for:
- Reinstalling dependencies
- Rebuilding the project
- Updating configurations

### Rebase a Worktree

Rebase a worktree on top of the latest `origin/main`:

```bash
wt rebase feature-branch
```

To rebase on a different branch instead of main:

```bash
wt rebase feature-branch develop
```

This will:
- Fetch the latest changes from `origin` (without updating the main worktree)
- Rebase the specified worktree on top of the specified base branch (defaults to `origin/main`)
- Run the `rebase_hook` if available (only on successful rebase)
- Leave the worktree in conflict state if conflicts occur (for manual resolution)

**Notes**:
- You cannot rebase the `main` worktree.
- The base branch must exist locally or on remote, otherwise an error will be shown.

If the rebase encounters conflicts, you'll need to resolve them manually:
```bash
cd feature-branch/src
# Resolve conflicts, then:
git rebase --continue
# Or abort the rebase:
git rebase --abort
```

### Remove a Worktree

Delete a worktree (requires confirmation):

```bash
wt remove feature-branch
```

This will:
- Run the `remove_hook` if available
- Remove the git worktree
- Delete the worktree directory

**Note**: You cannot remove the `main` worktree.

### Sweep Stale Worktrees

Identify and remove stale worktrees that are no longer needed:

```bash
wt sweep
```

This command finds worktrees that are no longer needed and asks for confirmation before removing each one.

A worktree is considered stale if:
1. **Merged PR**: The branch was pushed to remote, but the remote branch was deleted (typically after a PR was merged)
2. **Inactive local branch**: The branch is local-only (never pushed) and hasn't been modified in 4 weeks

The sweep command will:
- Fetch the latest refs from the remote
- Scan all worktrees in the current project
- Display all stale worktrees with reasons
- Ask for individual confirmation before removing each worktree
- Run the `remove_hook` for each removed worktree
- Show a summary of actions taken

**Example output:**
```
Fetching latest refs from remote...

Found 2 stale worktree(s):
  feature-old-ui: Remote branch deleted (likely merged PR)
  experiment-123: Local-only, inactive for 8 weeks

Remove worktree 'feature-old-ui'?
  Reason: Remote branch deleted (likely merged PR)
  (y/N): y
  Removing git worktree...
  Deleting worktree directory...
  Removed 'feature-old-ui'

Remove worktree 'experiment-123'?
  Reason: Local-only, inactive for 8 weeks
  (y/N): n
  Skipped.

Sweep complete: 1 removed, 1 skipped
```

**Note**: This command only operates on worktrees in the current project.

### Update Worktree Scripts

Update the worktree scripts installation to the latest version:

```bash
wt update
```

This command will:
- Check for any local modifications or uncommitted changes (aborts if found)
- Check for unpushed commits (aborts if found)
- Fetch the latest changes from the remote repository
- Pull and update the scripts if updates are available
- Report if already up-to-date

**Safety checks:**
- The command will abort with an error if there are any local modifications
- The command will abort with an error if there are local commits not pushed to remote
- This ensures you don't accidentally lose any local customizations

The updated scripts will be available immediately for your next `wt` command.

### Delete a Project

Delete the entire project (requires confirmation):

```bash
cd myapp
wt delete
```

This will:
- Remove the project from the registry
- Delete the entire project directory

## Hook System

Hooks allow you to run project-specific commands at key points in the worktree lifecycle.

### Creating Hook Scripts

1. Create a script in `~/.worktree-scripts/projects/` named `<project-name>.sh`
2. Define hook functions: `init_hook`, `create_hook`, `remove_hook`, `setup_hook`
3. Make the script executable (optional)

Example hook script (`~/.worktree-scripts/projects/myapp.sh`):

```bash
#!/usr/bin/env zsh

# Called after 'wt init' in main/src
init_hook() {
  echo "Installing dependencies..."
  npm install
}

# Called after 'wt create' in the new worktree's src
create_hook() {
  echo "Linking node_modules from main..."
  ln -s ../../main/src/node_modules node_modules
}

# Called before 'wt remove' in the worktree's src
remove_hook() {
  echo "Cleaning up..."
  rm -rf node_modules
}

# Called by 'wt setup' in the worktree's src
setup_hook() {
  echo "Reinstalling dependencies..."
  rm -rf node_modules
  npm install
}

# Called after 'wt rebase' (only on success) in the worktree's src
rebase_hook() {
  echo "Updating dependencies after rebase..."
  npm install
}
```

### Available Hooks

| Hook | When Called | Working Directory |
|------|-------------|-------------------|
| `init_hook` | After `wt init` | `<project>/main/src` |
| `create_hook` | After `wt create` | `<project>/<worktree>/src` |
| `remove_hook` | Before `wt remove` | `<project>/<worktree>/src` |
| `setup_hook` | During `wt setup` | `<project>/<worktree>/src` |
| `rebase_hook` | After `wt rebase` (only on success) | `<project>/<worktree>/src` |

See `projects/example-project.sh` for more hook examples.

## Commands Reference

| Command | Description | Arguments |
|---------|-------------|-----------|
| `wt init` | Initialize a new project | `<project-name> <git-url>` |
| `wt delete` | Delete the current project | None |
| `wt projects` | List all registered projects | None |
| `wt list` | List worktrees in current project | None |
| `wt create` | Create a new worktree | `<worktree-name> [base-branch]` |
| `wt remove` | Remove a worktree | `<worktree-name>` |
| `wt setup` | Run setup hooks for a worktree | `<worktree-name>` |
| `wt rebase` | Rebase a worktree | `<worktree-name> [base-branch]` |
| `wt sweep` | Remove stale worktrees | None |
| `wt update` | Update the worktree scripts installation | None |
| `wt help` | Show help message | None |

## Configuration

### Projects List

Projects are tracked in: `~/.local/share/worktree-scripts/projects`

Format: `/absolute/path/to/project:project-name`

### Environment Variables

- `WORKTREE_SCRIPTS_DIR`: Path to the installation directory (set by bootstrap)

### Alias

- `wt`: Alias to `$WORKTREE_SCRIPTS_DIR/wt.sh`

## Examples

### Node.js Project Workflow

```bash
# Initialize project
wt init myapp https://github.com/user/myapp.git
cd myapp/main/src
npm install

# Create feature branch
cd ..
wt create feature/new-ui

# Work on feature
cd feature-new-ui/src
npm start

# Create another worktree for a different feature
cd ../..
wt create hotfix/bug-123

# List all worktrees
wt list

# Rebase a feature branch on latest main
wt rebase feature-new-ui

# Remove completed feature
wt remove feature-new-ui

# Delete entire project when done
wt delete
```

### Multiple Projects

```bash
# Initialize multiple projects
wt init frontend https://github.com/user/frontend.git
wt init backend https://github.com/user/backend.git
wt init docs https://github.com/user/docs.git

# See all projects
wt projects

# Work in different projects
cd frontend
wt create feature-1

cd ../backend
wt create feature-1
```

### Working with Different Base Branches

```bash
# Create a feature branch from the develop branch
wt create new-feature develop

# Create a hotfix from a release branch
wt create hotfix/critical-bug release-1.0

# Rebase feature on develop instead of main
wt rebase new-feature develop

# Rebase on a specific release branch
wt rebase hotfix/critical-bug release-1.0
```

## Troubleshooting

### "Not in a project directory" Error

This error occurs when you run a command that requires being inside a registered project directory.

Solution: Navigate to a project directory or check `wt projects` to see registered projects.

### "WORKTREE_SCRIPTS_DIR environment variable is not set" Error

The environment variable is not configured.

Solution: Run `source ~/.zshrc` or restart your terminal.

### Stale Project Paths

If you move or rename a project directory manually, the projects list will have stale paths.

Solution: Manually edit `~/.local/share/worktree-scripts/projects` to remove or update the path.

### Git Worktree Issues

If git worktree commands fail, you may need to clean up manually:

```bash
# List worktrees
git worktree list

# Force remove a worktree
git worktree remove --force path/to/worktree

# Prune stale worktrees
git worktree prune
```

