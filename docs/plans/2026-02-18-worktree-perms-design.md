# Worktree Directory Permissions for Claude Sessions

## Problem

When sweatshop creates a worktree and launches a Claude session, Claude has no
pre-approved Read, Write, or Edit permissions scoped to the worktree directory.
The user must manually approve each file operation.

## Solution

Automatically inject path-scoped Read, Write, and Edit permissions into
`.claude/settings.local.json` when creating a worktree, and extend sweatshop's
permission matching to support path-prefix wildcards.

## Changes

### 1. Add `/*` wildcard to matchPattern (`internal/perms/match.go`)

Add a third wildcard form: if the pattern ends with `/*`, trim the `*` and
match via `HasPrefix`. Example: pattern `/home/user/wt/*` matches
`/home/user/wt/file.go` and `/home/user/wt/sub/dir/file.go`.

### 2. Inject permissions during worktree creation (`internal/worktree/worktree.go`)

After `git worktree add` and sweatfile application, write
`.claude/settings.local.json` with:

- `Read(<worktreePath>/*)`
- `Write(<worktreePath>/*)`
- `Edit(<worktreePath>/*)`

Uses `perms.SaveClaudeSettings` which preserves existing keys.

### 3. Git-exclude `.claude` (`internal/sweatfile/apply.go`)

Add `.claude` to `HardcodedExcludes` so the generated settings file is not
tracked by git.

### 4. Tests

- `match_test.go`: `/*` wildcard cases (match, no-match, nested paths)
- Verify `BuildPermissionString` covers Edit with file_path (already does)
