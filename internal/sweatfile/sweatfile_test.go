package sweatfile

import (
	"testing"
)

func TestParseMinimal(t *testing.T) {
	input := `
git_excludes = [".claude/"]
setup = ["direnv allow"]

[env]
EDITOR = "nvim"

[files.envrc]
source = "~/eng/rcm-worktrees/envrc"
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
