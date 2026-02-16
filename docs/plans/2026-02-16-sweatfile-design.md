# Sweatfile Design

Declarative, repo-contained format for configuring how sweatshop sets up worktrees. Replaces the `rcm-worktrees/` overlay and hardcoded `gitExcludes` slice with a layered TOML config.

## File Locations

- **Eng-area default:** `~/<eng_area>/sweatfile`
- **Repo-level override:** `<repo_root>/sweatfile`

TOML format, no extension (like `justfile`). The repo-level file is read from the bare repo root, not the worktree — so it's checked in and shared across all worktrees.

## Format

```toml
# Git patterns written to .git/info/exclude on worktree creation.
git_excludes = [".claude/", ".direnv/"]

# Environment variables written to .sweatshop-env in the worktree.
[env]
EDITOR = "nvim"

# Files placed into the worktree as dotfiles (dest gets "." prepended).
# Specify either "source" (symlinked) or "content" (written), not both.
[files.envrc]
source = "~/eng/rcm-worktrees/envrc"

[files."claude/settings.local.json"]
source = "~/eng/rcm-worktrees/claude/settings.local.json"

[files.tool-versions]
content = """
golang 1.23.0
"""

# Shell commands run after worktree creation, in order.
setup = [
  "direnv allow",
]
```

## Sections

### `git_excludes`

String array of patterns appended to `.git/info/exclude`. `.sweatshop-env` is always excluded regardless of config.

### `[env]`

Flat key-value map. Merged env vars are written to `.sweatshop-env` in the worktree. This file is:
- Always added to git excludes (hardcoded, not user-configurable)
- Sourced by direnv via `dotenv_if_exists .sweatshop-env` in the default `.envrc`
- Forbidden from modification by Claude and other agents
- Diffed on shop close to offer integration into the repo sweatfile

### `[files]`

Each key is a destination path relative to the worktree root. A `.` is prepended to the destination (`envrc` becomes `.envrc`, `claude/settings.local.json` becomes `.claude/settings.local.json`).

- `source`: path to symlink from. Supports `~` expansion.
- `content`: string written as a regular file.
- Exactly one of `source` or `content` must be specified.
- Existing files in the worktree are not overwritten.

### `setup`

String array of shell commands run in order after worktree creation. Eng-area commands run first, repo commands appended after.

## Merge Semantics

When both eng-area and repo sweatfiles exist:

| Field | Merge strategy | How to clear inherited |
|-------|---------------|----------------------|
| `git_excludes` | Concatenate (eng first, repo appended) | `git_excludes = []` |
| `env` | Shallow merge (repo overrides per-key) | `KEY = ""` |
| `files` | Shallow merge (repo overrides per-key) | `source = ""` |
| `setup` | Concatenate (eng first, repo appended) | `setup = []` |

Arrays concatenate; maps merge. Explicit empty array `[]` is the clear sentinel.

If only one sweatfile exists, it's used as-is. If neither exists, sweatshop falls back to current behavior.

## Integration with Sweatshop

### Replaces

1. **`ApplyRcmOverlay`** — replaced by `[files]` section. The `rcm-worktrees/` directory becomes unnecessary.
2. **`applyGitExcludes`** (hardcoded slice) — replaced by `git_excludes` field.

### Unchanged

- **`flake.HasDevShell` detection** — attach-time decision about session wrapping, not a worktree-creation concern.

### Worktree Creation Flow

```
Create(engArea, repoPath, worktreePath)
  -> git worktree add
  -> load & merge sweatfiles (eng-area + repo)
  -> apply git_excludes (+ hardcoded .sweatshop-env)
  -> apply files (symlink or write)
  -> write .sweatshop-env from env
  -> run setup commands
```

### Shop Close Flow (env review)

1. Snapshot `.sweatshop-env` before zmx attach.
2. After shop close, diff against snapshot.
3. If new/changed env vars, present interactively (like permission review): promote to repo sweatfile, keep local, or discard.
4. Clean up snapshot.

## Examples

### Eng-area default (`~/eng/sweatfile`)

```toml
git_excludes = [".claude/", ".direnv/", ".sweatshop-env"]

[env]
EDITOR = "nvim"

[files.envrc]
source = "~/eng/rcm-worktrees/envrc"

[files."claude/settings.local.json"]
source = "~/eng/rcm-worktrees/claude/settings.local.json"

setup = [
  "direnv allow",
]
```

### Go project (`~/eng/repos/dodder/sweatfile`)

```toml
setup = [
  "go mod download",
]
```

Inherits all eng-area defaults, appends `go mod download`.

### Rust project with custom envrc (`~/eng/repos/ssh-agent-mux/sweatfile`)

```toml
[files.envrc]
content = """
source_env "$HOME"
use flake "$HOME/eng/devenvs/rust"
"""

setup = [
  "cargo fetch",
]
```

Overrides `.envrc`, appends `cargo fetch`. Inherits git_excludes, env, claude settings.

### Project that clears inherited setup (`~/eng/repos/nix-mcp-server/sweatfile`)

```toml
setup = []
```

Inherits everything except setup commands.

## Future Work

- Private zmx server/session group for sweatshop
- Rename "zmx detach" to "shop close" in user-facing UX
