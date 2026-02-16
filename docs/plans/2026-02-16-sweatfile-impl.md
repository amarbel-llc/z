# Sweatfile Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the rcm-worktrees overlay and hardcoded git excludes with a layered TOML-based `sweatfile` config that each repo can check in.

**Architecture:** New `internal/sweatfile` package handles parsing, merging, and applying. `worktree.Create` delegates to it instead of `ApplyRcmOverlay` and `applyGitExcludes`. The attach flow snapshots/diffs `.sweatshop-env` alongside the existing permission snapshot.

**Tech Stack:** Go, `github.com/BurntSushi/toml` for parsing, existing `internal/git` helpers.

---

### Task 1: Add TOML dependency

**Files:**
- Modify: `go.mod`
- Modify: `go.sum`

**Step 1: Add the dependency**

Run: `nix develop --command go get github.com/BurntSushi/toml`

**Step 2: Tidy**

Run: `nix develop --command go mod tidy`

**Step 3: Regenerate gomod2nix.toml**

Run: `just build-gomod2nix` (or `nix develop --command gomod2nix`)

**Step 4: Commit**

```
git add go.mod go.sum gomod2nix.toml
git commit -m "deps: add BurntSushi/toml for sweatfile parsing"
```

---

### Task 2: Sweatfile struct and TOML parsing

**Files:**
- Create: `internal/sweatfile/sweatfile.go`
- Create: `internal/sweatfile/sweatfile_test.go`

**Step 1: Write the failing test**

```go
package sweatfile

import (
	"testing"
)

func TestParseMinimal(t *testing.T) {
	input := `
git_excludes = [".claude/"]

[env]
EDITOR = "nvim"

[files.envrc]
source = "~/eng/rcm-worktrees/envrc"

setup = ["direnv allow"]
`
	sf, err := Parse([]byte(input))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(sf.GitExcludes) != 1 || sf.GitExcludes[0] != ".claude/" {
		t.Errorf("git_excludes: got %v", sf.GitExcludes)
	}
	if sf.Env["EDITOR"] != "nvim" {
		t.Errorf("env EDITOR: got %q", sf.Env["EDITOR"])
	}
	if sf.Files["envrc"].Source != "~/eng/rcm-worktrees/envrc" {
		t.Errorf("files.envrc.source: got %q", sf.Files["envrc"].Source)
	}
	if len(sf.Setup) != 1 || sf.Setup[0] != "direnv allow" {
		t.Errorf("setup: got %v", sf.Setup)
	}
}

func TestParseFileContent(t *testing.T) {
	input := `
[files.envrc]
content = "use flake ."
`
	sf, err := Parse([]byte(input))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if sf.Files["envrc"].Content != "use flake ." {
		t.Errorf("files.envrc.content: got %q", sf.Files["envrc"].Content)
	}
}

func TestParseEmpty(t *testing.T) {
	sf, err := Parse([]byte(""))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if sf.GitExcludes != nil {
		t.Errorf("expected nil git_excludes, got %v", sf.GitExcludes)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `nix develop --command go test ./internal/sweatfile/ -v`
Expected: FAIL — package does not exist

**Step 3: Write minimal implementation**

```go
package sweatfile

import (
	"github.com/BurntSushi/toml"
)

type FileEntry struct {
	Source  string `toml:"source"`
	Content string `toml:"content"`
}

type Sweatfile struct {
	GitExcludes []string             `toml:"git_excludes"`
	Env         map[string]string    `toml:"env"`
	Files       map[string]FileEntry `toml:"files"`
	Setup       []string             `toml:"setup"`
}

func Parse(data []byte) (Sweatfile, error) {
	var sf Sweatfile
	if err := toml.Unmarshal(data, &sf); err != nil {
		return Sweatfile{}, err
	}
	return sf, nil
}
```

**Step 4: Run test to verify it passes**

Run: `nix develop --command go test ./internal/sweatfile/ -v`
Expected: PASS

**Step 5: Commit**

```
git add internal/sweatfile/
git commit -m "feat(sweatfile): add TOML struct and parser"
```

---

### Task 3: Sweatfile loading from disk

**Files:**
- Modify: `internal/sweatfile/sweatfile.go`
- Modify: `internal/sweatfile/sweatfile_test.go`

**Step 1: Write the failing test**

```go
func TestLoadFromPath(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sweatfile")
	os.WriteFile(path, []byte(`git_excludes = [".direnv/"]`), 0o644)

	sf, err := Load(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(sf.GitExcludes) != 1 || sf.GitExcludes[0] != ".direnv/" {
		t.Errorf("git_excludes: got %v", sf.GitExcludes)
	}
}

func TestLoadMissing(t *testing.T) {
	sf, err := Load("/nonexistent/sweatfile")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if sf.GitExcludes != nil {
		t.Errorf("expected nil git_excludes, got %v", sf.GitExcludes)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `nix develop --command go test ./internal/sweatfile/ -v -run TestLoad`
Expected: FAIL — `Load` undefined

**Step 3: Write minimal implementation**

```go
func Load(path string) (Sweatfile, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return Sweatfile{}, nil
		}
		return Sweatfile{}, err
	}
	return Parse(data)
}
```

Add `"errors"`, `"io/fs"`, `"os"` to imports.

**Step 4: Run test to verify it passes**

Run: `nix develop --command go test ./internal/sweatfile/ -v -run TestLoad`
Expected: PASS

**Step 5: Commit**

```
git add internal/sweatfile/
git commit -m "feat(sweatfile): add Load from disk with missing-file fallback"
```

---

### Task 4: Sweatfile merging

**Files:**
- Modify: `internal/sweatfile/sweatfile.go`
- Modify: `internal/sweatfile/sweatfile_test.go`

**Step 1: Write the failing tests**

```go
func TestMergeConcatenatesArrays(t *testing.T) {
	base := Sweatfile{
		GitExcludes: []string{".claude/"},
		Setup:       []string{"direnv allow"},
	}
	repo := Sweatfile{
		GitExcludes: []string{".direnv/"},
		Setup:       []string{"go mod download"},
	}
	merged := Merge(base, repo)
	if len(merged.GitExcludes) != 2 {
		t.Fatalf("expected 2 git_excludes, got %v", merged.GitExcludes)
	}
	if merged.GitExcludes[0] != ".claude/" || merged.GitExcludes[1] != ".direnv/" {
		t.Errorf("git_excludes: got %v", merged.GitExcludes)
	}
	if len(merged.Setup) != 2 {
		t.Fatalf("expected 2 setup, got %v", merged.Setup)
	}
}

func TestMergeClearSentinel(t *testing.T) {
	base := Sweatfile{
		GitExcludes: []string{".claude/"},
		Setup:       []string{"direnv allow"},
	}
	repo := Sweatfile{
		GitExcludes: []string{},
		Setup:       []string{},
	}
	merged := Merge(base, repo)
	if len(merged.GitExcludes) != 0 {
		t.Errorf("expected cleared git_excludes, got %v", merged.GitExcludes)
	}
	if len(merged.Setup) != 0 {
		t.Errorf("expected cleared setup, got %v", merged.Setup)
	}
}

func TestMergeEnvOverride(t *testing.T) {
	base := Sweatfile{Env: map[string]string{"EDITOR": "vim", "PAGER": "less"}}
	repo := Sweatfile{Env: map[string]string{"EDITOR": "nvim"}}
	merged := Merge(base, repo)
	if merged.Env["EDITOR"] != "nvim" {
		t.Errorf("expected nvim, got %q", merged.Env["EDITOR"])
	}
	if merged.Env["PAGER"] != "less" {
		t.Errorf("expected less, got %q", merged.Env["PAGER"])
	}
}

func TestMergeFilesOverride(t *testing.T) {
	base := Sweatfile{
		Files: map[string]FileEntry{
			"envrc":      {Source: "~/eng/rcm-worktrees/envrc"},
			"gitconfig":  {Source: "~/eng/rcm-worktrees/gitconfig"},
		},
	}
	repo := Sweatfile{
		Files: map[string]FileEntry{
			"envrc": {Content: "use flake ."},
		},
	}
	merged := Merge(base, repo)
	if merged.Files["envrc"].Content != "use flake ." {
		t.Errorf("expected inline content, got %+v", merged.Files["envrc"])
	}
	if merged.Files["gitconfig"].Source != "~/eng/rcm-worktrees/gitconfig" {
		t.Errorf("expected inherited gitconfig, got %+v", merged.Files["gitconfig"])
	}
}

func TestMergeBaseOnly(t *testing.T) {
	base := Sweatfile{GitExcludes: []string{".claude/"}}
	merged := Merge(base, Sweatfile{})
	if len(merged.GitExcludes) != 1 || merged.GitExcludes[0] != ".claude/" {
		t.Errorf("expected inherited git_excludes, got %v", merged.GitExcludes)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `nix develop --command go test ./internal/sweatfile/ -v -run TestMerge`
Expected: FAIL — `Merge` undefined

**Step 3: Write minimal implementation**

The key subtlety: distinguish "field not present in TOML" (nil slice) from "field explicitly set to empty" (non-nil zero-length slice). A nil slice means "inherit", `[]` means "clear".

```go
func Merge(base, repo Sweatfile) Sweatfile {
	merged := base

	// Arrays: nil = inherit, empty = clear, non-empty = append
	if repo.GitExcludes != nil {
		if len(repo.GitExcludes) == 0 {
			merged.GitExcludes = []string{}
		} else {
			merged.GitExcludes = append(base.GitExcludes, repo.GitExcludes...)
		}
	}
	if repo.Setup != nil {
		if len(repo.Setup) == 0 {
			merged.Setup = []string{}
		} else {
			merged.Setup = append(base.Setup, repo.Setup...)
		}
	}

	// Maps: shallow merge, repo overrides per-key
	if repo.Env != nil {
		if merged.Env == nil {
			merged.Env = make(map[string]string)
		}
		for k, v := range repo.Env {
			merged.Env[k] = v
		}
	}

	if repo.Files != nil {
		if merged.Files == nil {
			merged.Files = make(map[string]FileEntry)
		}
		for k, v := range repo.Files {
			merged.Files[k] = v
		}
	}

	return merged
}
```

**Step 4: Run test to verify it passes**

Run: `nix develop --command go test ./internal/sweatfile/ -v -run TestMerge`
Expected: PASS

**Step 5: Commit**

```
git add internal/sweatfile/
git commit -m "feat(sweatfile): add Merge with layered semantics"
```

---

### Task 5: LoadMerged — resolve eng-area + repo sweatfiles

**Files:**
- Modify: `internal/sweatfile/sweatfile.go`
- Modify: `internal/sweatfile/sweatfile_test.go`

**Step 1: Write the failing test**

```go
func TestLoadMerged(t *testing.T) {
	dir := t.TempDir()
	engDir := filepath.Join(dir, "eng")
	repoDir := filepath.Join(dir, "eng", "repos", "myrepo")
	os.MkdirAll(repoDir, 0o755)

	os.WriteFile(filepath.Join(engDir, "sweatfile"), []byte(`
git_excludes = [".claude/"]
setup = ["direnv allow"]
`), 0o644)

	os.WriteFile(filepath.Join(repoDir, "sweatfile"), []byte(`
setup = ["go mod download"]
`), 0o644)

	sf, err := LoadMerged(engDir, repoDir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(sf.GitExcludes) != 1 || sf.GitExcludes[0] != ".claude/" {
		t.Errorf("git_excludes: got %v", sf.GitExcludes)
	}
	if len(sf.Setup) != 2 || sf.Setup[0] != "direnv allow" || sf.Setup[1] != "go mod download" {
		t.Errorf("setup: got %v", sf.Setup)
	}
}

func TestLoadMergedNoFiles(t *testing.T) {
	dir := t.TempDir()
	sf, err := LoadMerged(filepath.Join(dir, "eng"), filepath.Join(dir, "repo"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if sf.GitExcludes != nil || sf.Setup != nil {
		t.Errorf("expected zero-value sweatfile, got %+v", sf)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `nix develop --command go test ./internal/sweatfile/ -v -run TestLoadMerged`
Expected: FAIL — `LoadMerged` undefined

**Step 3: Write minimal implementation**

```go
func LoadMerged(engAreaDir, repoDir string) (Sweatfile, error) {
	base, err := Load(filepath.Join(engAreaDir, "sweatfile"))
	if err != nil {
		return Sweatfile{}, err
	}
	repo, err := Load(filepath.Join(repoDir, "sweatfile"))
	if err != nil {
		return Sweatfile{}, err
	}
	return Merge(base, repo), nil
}
```

Add `"path/filepath"` to imports.

**Step 4: Run test to verify it passes**

Run: `nix develop --command go test ./internal/sweatfile/ -v -run TestLoadMerged`
Expected: PASS

**Step 5: Commit**

```
git add internal/sweatfile/
git commit -m "feat(sweatfile): add LoadMerged for layered eng-area + repo resolution"
```

---

### Task 6: Apply functions — git excludes, files, env, setup

**Files:**
- Create: `internal/sweatfile/apply.go`
- Create: `internal/sweatfile/apply_test.go`

**Step 1: Write the failing tests**

```go
package sweatfile

import (
	"os"
	"path/filepath"
	"testing"
)

func TestApplyGitExcludes(t *testing.T) {
	dir := t.TempDir()
	gitDir := filepath.Join(dir, ".git", "info")
	os.MkdirAll(gitDir, 0o755)
	// Simulate git rev-parse --git-path info/exclude returning a relative path
	excludePath := filepath.Join(gitDir, "exclude")

	err := applyGitExcludes(excludePath, []string{".claude/", ".direnv/"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	data, _ := os.ReadFile(excludePath)
	if string(data) != ".claude/\n.direnv/\n" {
		t.Errorf("exclude content: got %q", string(data))
	}
}

func TestApplyFilesSymlink(t *testing.T) {
	dir := t.TempDir()
	srcFile := filepath.Join(dir, "source-envrc")
	os.WriteFile(srcFile, []byte("use flake ."), 0o644)

	worktreeDir := filepath.Join(dir, "worktree")
	os.MkdirAll(worktreeDir, 0o755)

	files := map[string]FileEntry{
		"envrc": {Source: srcFile},
	}
	err := ApplyFiles(worktreeDir, files)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	dest := filepath.Join(worktreeDir, ".envrc")
	target, err := os.Readlink(dest)
	if err != nil {
		t.Fatalf("expected symlink: %v", err)
	}
	if target != srcFile {
		t.Errorf("symlink target: got %q", target)
	}
}

func TestApplyFilesContent(t *testing.T) {
	dir := t.TempDir()
	worktreeDir := filepath.Join(dir, "worktree")
	os.MkdirAll(worktreeDir, 0o755)

	files := map[string]FileEntry{
		"tool-versions": {Content: "golang 1.23.0\n"},
	}
	err := ApplyFiles(worktreeDir, files)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	data, _ := os.ReadFile(filepath.Join(worktreeDir, ".tool-versions"))
	if string(data) != "golang 1.23.0\n" {
		t.Errorf("content: got %q", string(data))
	}
}

func TestApplyFilesNoOverwrite(t *testing.T) {
	dir := t.TempDir()
	worktreeDir := filepath.Join(dir, "worktree")
	os.MkdirAll(worktreeDir, 0o755)
	os.WriteFile(filepath.Join(worktreeDir, ".envrc"), []byte("existing"), 0o644)

	files := map[string]FileEntry{
		"envrc": {Content: "new content"},
	}
	ApplyFiles(worktreeDir, files)
	data, _ := os.ReadFile(filepath.Join(worktreeDir, ".envrc"))
	if string(data) != "existing" {
		t.Errorf("expected existing content preserved, got %q", string(data))
	}
}

func TestApplyFilesNestedPath(t *testing.T) {
	dir := t.TempDir()
	worktreeDir := filepath.Join(dir, "worktree")
	os.MkdirAll(worktreeDir, 0o755)

	files := map[string]FileEntry{
		"claude/settings.local.json": {Content: `{"permissions":{}}`},
	}
	err := ApplyFiles(worktreeDir, files)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	data, _ := os.ReadFile(filepath.Join(worktreeDir, ".claude", "settings.local.json"))
	if string(data) != `{"permissions":{}}` {
		t.Errorf("content: got %q", string(data))
	}
}

func TestApplyEnv(t *testing.T) {
	dir := t.TempDir()
	err := ApplyEnv(dir, map[string]string{"EDITOR": "nvim", "PAGER": "less"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	data, _ := os.ReadFile(filepath.Join(dir, ".sweatshop-env"))
	content := string(data)
	if !containsLine(content, "EDITOR=nvim") || !containsLine(content, "PAGER=less") {
		t.Errorf("env content: got %q", content)
	}
}

func TestApplyEnvEmpty(t *testing.T) {
	dir := t.TempDir()
	err := ApplyEnv(dir, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	_, err = os.Stat(filepath.Join(dir, ".sweatshop-env"))
	if err == nil {
		t.Error("expected no .sweatshop-env for empty env")
	}
}

func containsLine(s, line string) bool {
	for _, l := range splitLines(s) {
		if l == line {
			return true
		}
	}
	return false
}

func splitLines(s string) []string {
	var lines []string
	for _, l := range filepath.SplitList(s) {
		lines = append(lines, l)
	}
	// Actually just split on newlines
	return strings.Split(strings.TrimRight(s, "\n"), "\n")
}
```

Note: add `"strings"` to imports in the test file.

**Step 2: Run test to verify it fails**

Run: `nix develop --command go test ./internal/sweatfile/ -v -run "TestApply"`
Expected: FAIL — functions undefined

**Step 3: Write minimal implementation**

`internal/sweatfile/apply.go`:

```go
package sweatfile

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/amarbel-llc/sweatshop/internal/git"
)

// HardcodedExcludes are always written to .git/info/exclude regardless of sweatfile config.
var HardcodedExcludes = []string{
	".sweatshop-env",
}

func Apply(worktreePath string, sf Sweatfile) error {
	// Git excludes
	allExcludes := append(sf.GitExcludes, HardcodedExcludes...)
	if len(allExcludes) > 0 {
		excludePath, err := resolveExcludePath(worktreePath)
		if err != nil {
			return fmt.Errorf("resolving git exclude path: %w", err)
		}
		if err := applyGitExcludes(excludePath, allExcludes); err != nil {
			return fmt.Errorf("applying git excludes: %w", err)
		}
	}

	// Files
	if err := ApplyFiles(worktreePath, sf.Files); err != nil {
		return fmt.Errorf("applying files: %w", err)
	}

	// Env
	if err := ApplyEnv(worktreePath, sf.Env); err != nil {
		return fmt.Errorf("applying env: %w", err)
	}

	// Setup commands
	if err := RunSetup(worktreePath, sf.Setup); err != nil {
		return fmt.Errorf("running setup: %w", err)
	}

	return nil
}

func resolveExcludePath(worktreePath string) (string, error) {
	rel, err := git.Run(worktreePath, "rev-parse", "--git-path", "info/exclude")
	if err != nil {
		return "", err
	}
	if !filepath.IsAbs(rel) {
		rel = filepath.Join(worktreePath, rel)
	}
	return rel, nil
}

func applyGitExcludes(excludePath string, patterns []string) error {
	if err := os.MkdirAll(filepath.Dir(excludePath), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(excludePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	for _, p := range patterns {
		if _, err := fmt.Fprintln(f, p); err != nil {
			return err
		}
	}
	return nil
}

func ApplyFiles(worktreePath string, files map[string]FileEntry) error {
	for name, entry := range files {
		dest := filepath.Join(worktreePath, "."+name)

		// Don't overwrite existing
		if _, err := os.Stat(dest); err == nil {
			continue
		}

		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			return err
		}

		if entry.Source != "" {
			src := expandHome(entry.Source)
			if err := os.Symlink(src, dest); err != nil {
				return err
			}
		} else if entry.Content != "" {
			if err := os.WriteFile(dest, []byte(entry.Content), 0o644); err != nil {
				return err
			}
		}
	}
	return nil
}

func ApplyEnv(worktreePath string, env map[string]string) error {
	if len(env) == 0 {
		return nil
	}

	// Sort keys for deterministic output
	keys := make([]string, 0, len(env))
	for k := range env {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var lines []string
	for _, k := range keys {
		v := env[k]
		if v == "" {
			continue // cleared key
		}
		lines = append(lines, k+"="+v)
	}

	if len(lines) == 0 {
		return nil
	}

	path := filepath.Join(worktreePath, ".sweatshop-env")
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}

func RunSetup(worktreePath string, commands []string) error {
	for _, cmdStr := range commands {
		cmd := exec.Command("sh", "-c", cmdStr)
		cmd.Dir = worktreePath
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("setup command %q: %w", cmdStr, err)
		}
	}
	return nil
}

func expandHome(path string) string {
	if strings.HasPrefix(path, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return path
		}
		return filepath.Join(home, path[2:])
	}
	return path
}
```

**Step 4: Run test to verify it passes**

Run: `nix develop --command go test ./internal/sweatfile/ -v`
Expected: PASS

**Step 5: Commit**

```
git add internal/sweatfile/
git commit -m "feat(sweatfile): add Apply functions for git excludes, files, env, setup"
```

---

### Task 7: Wire sweatfile into worktree.Create

**Files:**
- Modify: `internal/worktree/worktree.go`

**Step 1: Update Create to use sweatfile.Apply**

Replace the body of `Create` to load and apply the sweatfile instead of calling `applyGitExcludes` and `ApplyRcmOverlay`:

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
		return fmt.Errorf("getting home dir: %w", err)
	}

	engAreaDir := filepath.Join(home, engArea)
	sf, err := sweatfile.LoadMerged(engAreaDir, repoPath)
	if err != nil {
		return fmt.Errorf("loading sweatfile: %w", err)
	}

	return sweatfile.Apply(worktreePath, sf)
}
```

Add `"github.com/amarbel-llc/sweatshop/internal/sweatfile"` to imports. Remove the `applyGitExcludes` function, the `gitExcludes` var, and the `ApplyRcmOverlay` function. Remove the `git` import if no longer needed (it likely is still needed — check).

**Step 2: Update worktree_test.go**

Remove `TestApplyRcmOverlay*` tests (3 tests). They're replaced by the sweatfile apply tests. Keep all `TestParsePath*` and `TestParseTarget*` tests.

**Step 3: Build to verify**

Run: `nix develop --command go build ./...`
Expected: success

**Step 4: Run all tests**

Run: `nix develop --command go test ./... -v`
Expected: PASS

**Step 5: Commit**

```
git add internal/worktree/ internal/sweatfile/
git commit -m "refactor(worktree): replace rcm overlay and hardcoded excludes with sweatfile"
```

---

### Task 8: Env snapshot and diff on shop close

**Files:**
- Create: `internal/sweatfile/env_review.go`
- Create: `internal/sweatfile/env_review_test.go`
- Modify: `internal/attach/attach.go`

**Step 1: Write the failing tests**

```go
package sweatfile

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSnapshotEnv(t *testing.T) {
	dir := t.TempDir()
	envPath := filepath.Join(dir, ".sweatshop-env")
	os.WriteFile(envPath, []byte("EDITOR=nvim\n"), 0o644)

	err := SnapshotEnv(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	data, _ := os.ReadFile(filepath.Join(dir, ".sweatshop-env.snapshot"))
	if string(data) != "EDITOR=nvim\n" {
		t.Errorf("snapshot: got %q", string(data))
	}
}

func TestSnapshotEnvMissing(t *testing.T) {
	dir := t.TempDir()
	err := SnapshotEnv(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	_, err = os.Stat(filepath.Join(dir, ".sweatshop-env.snapshot"))
	if err == nil {
		t.Error("expected no snapshot for missing env file")
	}
}

func TestDiffEnv(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, ".sweatshop-env.snapshot"), []byte("EDITOR=nvim\n"), 0o644)
	os.WriteFile(filepath.Join(dir, ".sweatshop-env"), []byte("EDITOR=nvim\nPAGER=less\n"), 0o644)

	added, changed, err := DiffEnv(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(added) != 1 || added["PAGER"] != "less" {
		t.Errorf("added: got %v", added)
	}
	if len(changed) != 0 {
		t.Errorf("changed: got %v", changed)
	}
}

func TestDiffEnvChanged(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, ".sweatshop-env.snapshot"), []byte("EDITOR=vim\n"), 0o644)
	os.WriteFile(filepath.Join(dir, ".sweatshop-env"), []byte("EDITOR=nvim\n"), 0o644)

	_, changed, err := DiffEnv(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(changed) != 1 || changed["EDITOR"] != "nvim" {
		t.Errorf("changed: got %v", changed)
	}
}

func TestCleanupEnvSnapshot(t *testing.T) {
	dir := t.TempDir()
	snap := filepath.Join(dir, ".sweatshop-env.snapshot")
	os.WriteFile(snap, []byte("x"), 0o644)
	CleanupEnvSnapshot(dir)
	if _, err := os.Stat(snap); err == nil {
		t.Error("expected snapshot removed")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `nix develop --command go test ./internal/sweatfile/ -v -run "TestSnapshot|TestDiffEnv|TestCleanup"`
Expected: FAIL — functions undefined

**Step 3: Write minimal implementation**

`internal/sweatfile/env_review.go`:

```go
package sweatfile

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

func SnapshotEnv(worktreePath string) error {
	envPath := filepath.Join(worktreePath, ".sweatshop-env")
	data, err := os.ReadFile(envPath)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil
		}
		return err
	}
	return os.WriteFile(filepath.Join(worktreePath, ".sweatshop-env.snapshot"), data, 0o644)
}

func DiffEnv(worktreePath string) (added, changed map[string]string, err error) {
	before := parseEnvFile(filepath.Join(worktreePath, ".sweatshop-env.snapshot"))
	after := parseEnvFile(filepath.Join(worktreePath, ".sweatshop-env"))

	added = make(map[string]string)
	changed = make(map[string]string)

	for k, v := range after {
		if oldV, ok := before[k]; !ok {
			added[k] = v
		} else if oldV != v {
			changed[k] = v
		}
	}
	return added, changed, nil
}

func CleanupEnvSnapshot(worktreePath string) {
	os.Remove(filepath.Join(worktreePath, ".sweatshop-env.snapshot"))
}

func parseEnvFile(path string) map[string]string {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	m := make(map[string]string)
	for _, line := range strings.Split(strings.TrimRight(string(data), "\n"), "\n") {
		if idx := strings.IndexByte(line, '='); idx > 0 {
			m[line[:idx]] = line[idx+1:]
		}
	}
	return m
}
```

**Step 4: Run test to verify it passes**

Run: `nix develop --command go test ./internal/sweatfile/ -v -run "TestSnapshot|TestDiffEnv|TestCleanup"`
Expected: PASS

**Step 5: Wire into attach.go**

In `attach.go`, add snapshot/diff/cleanup calls alongside the existing permission snapshot:

- In `Existing` and `ToPath`: call `sweatfile.SnapshotEnv(worktreePath)` before zmx attach.
- In `PostZmx`: after the permission review, call `sweatfile.DiffEnv(worktreePath)`, present results interactively if non-empty, then `sweatfile.CleanupEnvSnapshot(worktreePath)`.

The interactive review for env changes is deferred to Task 9.

**Step 6: Run all tests**

Run: `nix develop --command go test ./... -v`
Expected: PASS

**Step 7: Commit**

```
git add internal/sweatfile/ internal/attach/
git commit -m "feat(sweatfile): add env snapshot, diff, and cleanup for shop close"
```

---

### Task 9: Interactive env review on shop close

**Files:**
- Modify: `internal/sweatfile/env_review.go`
- Modify: `internal/attach/attach.go`

**Step 1: Add review function**

Add to `env_review.go`:

```go
const (
	EnvPromoteRepo = "repo"
	EnvKeep        = "keep"
	EnvDiscard     = "discard"
)

type EnvDecision struct {
	Key    string
	Value  string
	Action string
}
```

**Step 2: Add RouteEnvDecisions**

This writes promoted env vars into the repo's `sweatfile` TOML. For "discard", remove from `.sweatshop-env`. For "keep", leave as-is.

```go
func RouteEnvDecisions(repoSweatfilePath, envFilePath string, decisions []EnvDecision) error {
	// Load existing repo sweatfile (or empty)
	sf, err := Load(repoSweatfilePath)
	if err != nil {
		return err
	}

	var toDiscard []string

	for _, d := range decisions {
		switch d.Action {
		case EnvPromoteRepo:
			if sf.Env == nil {
				sf.Env = make(map[string]string)
			}
			sf.Env[d.Key] = d.Value
			toDiscard = append(toDiscard, d.Key)
		case EnvDiscard:
			toDiscard = append(toDiscard, d.Key)
		case EnvKeep:
			// leave in .sweatshop-env
		}
	}

	// Write updated repo sweatfile if any promotions
	if needsWrite(decisions) {
		if err := Save(repoSweatfilePath, sf); err != nil {
			return err
		}
	}

	// Remove discarded/promoted keys from .sweatshop-env
	if len(toDiscard) > 0 {
		return removeEnvKeys(envFilePath, toDiscard)
	}

	return nil
}
```

Note: `Save` (writing TOML back to disk) and `removeEnvKeys` are helpers to implement in this task.

**Step 3: Wire interactive prompts in attach.go PostZmx**

After the permission review block, add:

```go
added, changed, envErr := sweatfile.DiffEnv(worktreePath)
if envErr == nil && (len(added) > 0 || len(changed) > 0) {
	// present huh select for each new/changed key
	// options: promote to repo sweatfile, keep local, discard
}
sweatfile.CleanupEnvSnapshot(worktreePath)
```

**Step 4: Run all tests**

Run: `nix develop --command go test ./... -v`
Expected: PASS

**Step 5: Commit**

```
git add internal/sweatfile/ internal/attach/
git commit -m "feat(sweatfile): interactive env review on shop close"
```

---

### Task 10: Add Save (TOML serialization) for repo sweatfile updates

**Files:**
- Modify: `internal/sweatfile/sweatfile.go`
- Modify: `internal/sweatfile/sweatfile_test.go`

**Step 1: Write the failing test**

```go
func TestSaveRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sweatfile")

	sf := Sweatfile{
		GitExcludes: []string{".claude/"},
		Env:         map[string]string{"EDITOR": "nvim"},
		Setup:       []string{"direnv allow"},
	}

	err := Save(path, sf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	loaded, err := Load(path)
	if err != nil {
		t.Fatalf("unexpected error loading: %v", err)
	}
	if len(loaded.GitExcludes) != 1 || loaded.GitExcludes[0] != ".claude/" {
		t.Errorf("git_excludes roundtrip: got %v", loaded.GitExcludes)
	}
	if loaded.Env["EDITOR"] != "nvim" {
		t.Errorf("env roundtrip: got %v", loaded.Env)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `nix develop --command go test ./internal/sweatfile/ -v -run TestSave`
Expected: FAIL — `Save` undefined

**Step 3: Write minimal implementation**

```go
func Save(path string, sf Sweatfile) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return toml.NewEncoder(f).Encode(sf)
}
```

**Step 4: Run test to verify it passes**

Run: `nix develop --command go test ./internal/sweatfile/ -v -run TestSave`
Expected: PASS

**Step 5: Commit**

```
git add internal/sweatfile/
git commit -m "feat(sweatfile): add Save for TOML serialization"
```

---

### Task 11: Bats integration test

**Files:**
- Create: `tests/test_sweatfile.bats`

**Step 1: Write the integration test**

```bash
#!/usr/bin/env bats

load 'common.bash'

setup() {
  setup_test_home
  setup_mock_path

  # Create a bare repo to use as the "main repo"
  git init --bare "$HOME/eng/repos/testrepo" 2>/dev/null

  # Create eng-area sweatfile
  cat > "$HOME/eng/sweatfile" <<'EOF'
git_excludes = [".claude/", ".direnv/"]

[env]
EDITOR = "nvim"

[files.envrc]
content = "use flake ."

setup = []
EOF
}

@test "sweatfile: eng-area sweatfile creates dotfiles in worktree" {
  # Create worktree manually to test just the sweatfile apply
  mkdir -p "$HOME/eng/worktrees/testrepo/feature-x"
  cd "$HOME/eng/repos/testrepo"
  git worktree add "$HOME/eng/worktrees/testrepo/feature-x" -b feature-x 2>/dev/null

  # Run sweatshop attach (which triggers Create flow)
  # For now, verify the sweatfile parser works via a dedicated test command
  # or by checking that attach creates the expected files

  # Check .envrc was created
  [[ -f "$HOME/eng/worktrees/testrepo/feature-x/.envrc" ]]
  [[ "$(cat "$HOME/eng/worktrees/testrepo/feature-x/.envrc")" == "use flake ." ]]
}

@test "sweatfile: .sweatshop-env written from env section" {
  mkdir -p "$HOME/eng/worktrees/testrepo/feature-x"
  cd "$HOME/eng/repos/testrepo"
  git worktree add "$HOME/eng/worktrees/testrepo/feature-x" -b feature-x 2>/dev/null

  [[ -f "$HOME/eng/worktrees/testrepo/feature-x/.sweatshop-env" ]]
  grep -q "EDITOR=nvim" "$HOME/eng/worktrees/testrepo/feature-x/.sweatshop-env"
}

@test "sweatfile: repo sweatfile merges with eng-area" {
  cat > "$HOME/eng/repos/testrepo/sweatfile" <<'EOF'
[env]
PAGER = "less"

setup = ["echo hello"]
EOF

  mkdir -p "$HOME/eng/worktrees/testrepo/feature-y"
  cd "$HOME/eng/repos/testrepo"
  git worktree add "$HOME/eng/worktrees/testrepo/feature-y" -b feature-y 2>/dev/null

  # Should have both EDITOR (inherited) and PAGER (repo)
  grep -q "EDITOR=nvim" "$HOME/eng/worktrees/testrepo/feature-y/.sweatshop-env"
  grep -q "PAGER=less" "$HOME/eng/worktrees/testrepo/feature-y/.sweatshop-env"
}
```

Note: these tests may need adjustment depending on how `sweatshop attach` triggers `Create` in the test environment. The exact test approach will be refined during implementation — the key thing is testing the sweatfile apply behavior end-to-end.

**Step 2: Build and run**

Run: `just build && nix develop --command bats tests/test_sweatfile.bats`
Expected: PASS (or adjust test setup as needed)

**Step 3: Commit**

```
git add tests/test_sweatfile.bats
git commit -m "test: add bats integration tests for sweatfile"
```

---

### Task 12: Remove dead code

**Files:**
- Modify: `internal/worktree/worktree.go` — remove `ApplyRcmOverlay` if not already removed in Task 7
- Modify: `internal/worktree/worktree_test.go` — remove `TestApplyRcmOverlay*` tests if not already removed

**Step 1: Verify no remaining references to rcm overlay**

Run: `nix develop --command go build ./...` and `grep -r "RcmOverlay\|rcm-worktrees\|rcm_worktrees" internal/`

**Step 2: Remove any remaining dead code**

**Step 3: Run all tests**

Run: `nix develop --command go test ./... -v`
Expected: PASS

**Step 4: Commit**

```
git add internal/
git commit -m "refactor: remove rcm overlay dead code"
```
