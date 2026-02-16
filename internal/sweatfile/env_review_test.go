package sweatfile

import (
	"os"
	"path/filepath"
	"strings"
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

func TestRouteEnvDecisionsPromote(t *testing.T) {
	dir := t.TempDir()
	sweatfilePath := filepath.Join(dir, "sweatfile")
	envPath := filepath.Join(dir, ".sweatshop-env")
	os.WriteFile(envPath, []byte("EDITOR=nvim\nPAGER=less\n"), 0o644)

	decisions := []EnvDecision{
		{Key: "EDITOR", Value: "nvim", Action: EnvPromoteRepo},
		{Key: "PAGER", Value: "less", Action: EnvKeep},
	}

	err := RouteEnvDecisions(sweatfilePath, envPath, decisions)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Promoted key should be in repo sweatfile
	sf, _ := Load(sweatfilePath)
	if sf.Env["EDITOR"] != "nvim" {
		t.Errorf("expected EDITOR=nvim in sweatfile, got %v", sf.Env)
	}

	// Promoted key removed from env file, kept key stays
	data, _ := os.ReadFile(envPath)
	if strings.Contains(string(data), "EDITOR") {
		t.Errorf("expected EDITOR removed from env file, got %q", string(data))
	}
	if !strings.Contains(string(data), "PAGER=less") {
		t.Errorf("expected PAGER=less kept in env file, got %q", string(data))
	}
}

func TestRouteEnvDecisionsDiscard(t *testing.T) {
	dir := t.TempDir()
	sweatfilePath := filepath.Join(dir, "sweatfile")
	envPath := filepath.Join(dir, ".sweatshop-env")
	os.WriteFile(envPath, []byte("FOO=bar\n"), 0o644)

	decisions := []EnvDecision{
		{Key: "FOO", Value: "bar", Action: EnvDiscard},
	}

	err := RouteEnvDecisions(sweatfilePath, envPath, decisions)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Discarded -- env file should be removed (was the only key)
	if _, err := os.Stat(envPath); err == nil {
		t.Error("expected env file removed after discarding only key")
	}
}
