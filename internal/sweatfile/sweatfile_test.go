package sweatfile

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseMinimal(t *testing.T) {
	input := `
git_excludes = [".claude/"]
`
	sf, err := Parse([]byte(input))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(sf.GitExcludes) != 1 || sf.GitExcludes[0] != ".claude/" {
		t.Errorf("git_excludes: got %v", sf.GitExcludes)
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

func TestMergeConcatenatesArrays(t *testing.T) {
	base := Sweatfile{
		GitExcludes: []string{".claude/"},
	}
	repo := Sweatfile{
		GitExcludes: []string{".direnv/"},
	}
	merged := Merge(base, repo)
	if len(merged.GitExcludes) != 2 {
		t.Fatalf("expected 2 git_excludes, got %v", merged.GitExcludes)
	}
	if merged.GitExcludes[0] != ".claude/" || merged.GitExcludes[1] != ".direnv/" {
		t.Errorf("git_excludes: got %v", merged.GitExcludes)
	}
}

func TestMergeClearSentinel(t *testing.T) {
	base := Sweatfile{
		GitExcludes: []string{".claude/"},
	}
	repo := Sweatfile{
		GitExcludes: []string{},
	}
	merged := Merge(base, repo)
	if len(merged.GitExcludes) != 0 {
		t.Errorf("expected cleared git_excludes, got %v", merged.GitExcludes)
	}
}

func TestMergeBaseOnly(t *testing.T) {
	base := Sweatfile{GitExcludes: []string{".claude/"}}
	merged := Merge(base, Sweatfile{})
	if len(merged.GitExcludes) != 1 || merged.GitExcludes[0] != ".claude/" {
		t.Errorf("expected inherited git_excludes, got %v", merged.GitExcludes)
	}
}

func TestLoadMerged(t *testing.T) {
	dir := t.TempDir()
	engDir := filepath.Join(dir, "eng")
	repoDir := filepath.Join(dir, "eng", "repos", "myrepo")
	os.MkdirAll(repoDir, 0o755)

	os.WriteFile(filepath.Join(engDir, "sweatfile"), []byte(`
git_excludes = [".claude/"]
`), 0o644)

	os.WriteFile(filepath.Join(repoDir, "sweatfile"), []byte(`
git_excludes = [".direnv/"]
`), 0o644)

	result, err := LoadMerged(engDir, repoDir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	sf := result.Merged
	if len(sf.GitExcludes) != 2 || sf.GitExcludes[0] != ".claude/" || sf.GitExcludes[1] != ".direnv/" {
		t.Errorf("git_excludes: got %v", sf.GitExcludes)
	}
	if len(result.Sources) != 2 {
		t.Fatalf("expected 2 sources, got %d", len(result.Sources))
	}
	if !result.Sources[0].Found || !result.Sources[1].Found {
		t.Errorf("expected both sources found, got %v %v", result.Sources[0].Found, result.Sources[1].Found)
	}
}

func TestSaveRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sweatfile")

	sf := Sweatfile{
		GitExcludes: []string{".claude/"},
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
}

func TestParseClaudeAllow(t *testing.T) {
	input := `
claude_allow = ["Read", "Bash(git *)"]
`
	sf, err := Parse([]byte(input))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(sf.ClaudeAllow) != 2 {
		t.Fatalf("expected 2 claude_allow rules, got %v", sf.ClaudeAllow)
	}
	if sf.ClaudeAllow[0] != "Read" || sf.ClaudeAllow[1] != "Bash(git *)" {
		t.Errorf("claude_allow: got %v", sf.ClaudeAllow)
	}
}

func TestMergeClaudeAllowAppends(t *testing.T) {
	base := Sweatfile{ClaudeAllow: []string{"Read", "Glob"}}
	repo := Sweatfile{ClaudeAllow: []string{"Bash(go test:*)"}}
	merged := Merge(base, repo)
	if len(merged.ClaudeAllow) != 3 {
		t.Fatalf("expected 3 claude_allow rules, got %v", merged.ClaudeAllow)
	}
	if merged.ClaudeAllow[2] != "Bash(go test:*)" {
		t.Errorf("expected appended rule, got %v", merged.ClaudeAllow)
	}
}

func TestMergeClaudeAllowClear(t *testing.T) {
	base := Sweatfile{ClaudeAllow: []string{"Read", "Glob"}}
	repo := Sweatfile{ClaudeAllow: []string{}}
	merged := Merge(base, repo)
	if len(merged.ClaudeAllow) != 0 {
		t.Errorf("expected cleared claude_allow, got %v", merged.ClaudeAllow)
	}
}

func TestLoadMergedNoFiles(t *testing.T) {
	dir := t.TempDir()
	result, err := LoadMerged(filepath.Join(dir, "eng"), filepath.Join(dir, "repo"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Merged.GitExcludes != nil {
		t.Errorf("expected zero-value sweatfile, got %+v", result.Merged)
	}
	if result.Sources[0].Found || result.Sources[1].Found {
		t.Errorf("expected neither source found")
	}
}
