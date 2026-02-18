# Worktree Directory Permissions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-inject path-scoped Read, Write, and Edit permissions into `.claude/settings.local.json` when creating a worktree, so Claude sessions can operate on files without manual approval.

**Architecture:** Extend `matchPattern` in `internal/perms/match.go` with a `/*` (slash-star) wildcard for path-prefix matching. During `worktree.Create`, call `perms.SaveClaudeSettings` to write the three scoped rules. Add `.claude` to hardcoded git excludes.

**Tech Stack:** Go, cobra CLI, Claude Code settings.local.json

---

### Task 1: Add `/*` wildcard matching to matchPattern

**Files:**
- Modify: `internal/perms/match.go:86-98` (matchPattern function)
- Test: `internal/perms/match_test.go`

**Step 1: Write failing tests for `/*` wildcard**

Add to `internal/perms/match_test.go`:

```go
func TestMatchSlashStarWildcard(t *testing.T) {
	rules := []string{"Read(/home/user/eng/worktrees/repo/branch/*)"}

	if !MatchesAnyRule(rules, "Read", map[string]any{"file_path": "/home/user/eng/worktrees/repo/branch/file.go"}) {
		t.Error("expected file in worktree to match")
	}

	if !MatchesAnyRule(rules, "Read", map[string]any{"file_path": "/home/user/eng/worktrees/repo/branch/sub/dir/file.go"}) {
		t.Error("expected nested file in worktree to match")
	}

	if MatchesAnyRule(rules, "Read", map[string]any{"file_path": "/home/user/eng/worktrees/repo/other/file.go"}) {
		t.Error("expected file outside worktree not to match")
	}

	if MatchesAnyRule(rules, "Write", map[string]any{"file_path": "/home/user/eng/worktrees/repo/branch/file.go"}) {
		t.Error("expected wrong tool not to match")
	}
}

func TestMatchSlashStarEdit(t *testing.T) {
	rules := []string{"Edit(/tmp/wt/*)"}

	if !MatchesAnyRule(rules, "Edit", map[string]any{"file_path": "/tmp/wt/main.go"}) {
		t.Error("expected Edit in dir to match")
	}

	if MatchesAnyRule(rules, "Edit", map[string]any{"file_path": "/tmp/other/main.go"}) {
		t.Error("expected Edit outside dir not to match")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `nix develop --command go test ./internal/perms/ -run 'TestMatchSlashStar' -v`
Expected: FAIL

**Step 3: Implement `/*` wildcard in matchPattern**

In `internal/perms/match.go`, add a new condition at the top of `matchPattern`:

```go
func matchPattern(pattern string, command string) bool {
	if strings.HasSuffix(pattern, "/*") {
		prefix := strings.TrimSuffix(pattern, "*")
		return strings.HasPrefix(command, prefix)
	}

	if strings.HasSuffix(pattern, ":*") {
		// ... existing code
```

**Step 4: Run tests to verify they pass**

Run: `nix develop --command go test ./internal/perms/ -v`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add internal/perms/match.go internal/perms/match_test.go
git commit -m "feat(perms): add /* wildcard for path-prefix matching"
```

---

### Task 2: Add `.claude` to hardcoded git excludes

**Files:**
- Modify: `internal/sweatfile/apply.go:15-17` (HardcodedExcludes)

**Step 1: Add `.claude` to HardcodedExcludes**

In `internal/sweatfile/apply.go`, change:

```go
var HardcodedExcludes = []string{
	".sweatshop-env",
}
```

to:

```go
var HardcodedExcludes = []string{
	".sweatshop-env",
	".claude",
}
```

**Step 2: Run existing tests**

Run: `nix develop --command go test ./internal/sweatfile/ -v`
Expected: ALL PASS

**Step 3: Commit**

```bash
git add internal/sweatfile/apply.go
git commit -m "feat(sweatfile): git-exclude .claude directory in worktrees"
```

---

### Task 3: Inject permissions during worktree creation

**Files:**
- Modify: `internal/worktree/worktree.go:54-71` (Create function)

**Step 1: Add perms import and inject permissions after sweatfile application**

In `internal/worktree/worktree.go`, add `"github.com/amarbel-llc/sweatshop/internal/perms"` to imports, then after the `sweatfile.Apply` call:

```go
func Create(engArea, repoPath, worktreePath string) error {
	if err := os.MkdirAll(worktreePath, 0o755); err != nil {
		return fmt.Errorf("creating worktree directory: %w", err)
	}
	if err := git.RunPassthrough(repoPath, "worktree", "add", worktreePath); err != nil {
		return fmt.Errorf("git worktree add: %w", err)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("getting home directory: %w", err)
	}
	engAreaDir := filepath.Join(home, engArea)
	sf, err := sweatfile.LoadMerged(engAreaDir, repoPath)
	if err != nil {
		return fmt.Errorf("loading sweatfile: %w", err)
	}
	if err := sweatfile.Apply(worktreePath, sf); err != nil {
		return err
	}

	settingsPath := filepath.Join(worktreePath, ".claude", "settings.local.json")
	existing, _ := perms.LoadClaudeSettings(settingsPath)
	rules := appendUnique(existing,
		"Read("+worktreePath+"/*)",
		"Write("+worktreePath+"/*)",
		"Edit("+worktreePath+"/*)",
	)
	return perms.SaveClaudeSettings(settingsPath, rules)
}

func appendUnique(existing []string, rules ...string) []string {
	set := make(map[string]bool, len(existing))
	for _, r := range existing {
		set[r] = true
	}
	result := append([]string{}, existing...)
	for _, r := range rules {
		if !set[r] {
			result = append(result, r)
		}
	}
	return result
}
```

Note: the original `Create` returned `sweatfile.Apply(...)` directly. Now it checks the error explicitly and continues to inject permissions.

**Step 2: Run all tests**

Run: `nix develop --command go test ./... -v`
Expected: ALL PASS

**Step 3: Commit**

```bash
git add internal/worktree/worktree.go
git commit -m "feat(worktree): inject Read/Write/Edit permissions on create"
```

---

### Task 4: Verify full build

**Step 1: Run nix build**

Run: `just build`
Expected: SUCCESS

**Step 2: Run all unit tests**

Run: `just test`
Expected: ALL PASS

**Step 3: Run bats integration tests**

Run: `just test-bats`
Expected: ALL PASS
