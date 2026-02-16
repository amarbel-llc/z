package worktree

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/amarbel-llc/sweatshop/internal/git"
)

type Target struct {
	Host string
	Path string
}

func ParseTarget(target string) Target {
	if idx := strings.IndexByte(target, ':'); idx >= 0 {
		return Target{
			Host: target[:idx],
			Path: target[idx+1:],
		}
	}
	return Target{Path: target}
}

type PathComponents struct {
	EngArea  string
	Repo     string
	Worktree string
}

func ParsePath(path string) (PathComponents, error) {
	parts := strings.Split(path, "/")
	if len(parts) < 4 || parts[1] != "worktrees" {
		return PathComponents{}, fmt.Errorf("invalid worktree path: %s (expected <eng_area>/worktrees/<repo>/<branch>)", path)
	}
	return PathComponents{
		EngArea:  parts[0],
		Repo:     parts[2],
		Worktree: parts[3],
	}, nil
}

func RepoPath(home string, comp PathComponents) string {
	return filepath.Join(home, comp.EngArea, "repos", comp.Repo)
}

func WorktreePath(home string, sweatshopPath string) string {
	return filepath.Join(home, sweatshopPath)
}

func Create(engArea, repoPath, worktreePath string) error {
	if err := os.MkdirAll(worktreePath, 0o755); err != nil {
		return fmt.Errorf("creating worktree directory: %w", err)
	}
	if err := git.RunPassthrough(repoPath, "worktree", "add", worktreePath); err != nil {
		return fmt.Errorf("git worktree add: %w", err)
	}
	if err := applyGitExcludes(worktreePath); err != nil {
		return fmt.Errorf("applying git excludes: %w", err)
	}
	return ApplyRcmOverlay(engArea, worktreePath)
}

var gitExcludes = []string{
	".claude/",
}

func applyGitExcludes(worktreePath string) error {
	excludePath, err := git.Run(worktreePath, "rev-parse", "--git-path", "info/exclude")
	if err != nil {
		return err
	}
	if !filepath.IsAbs(excludePath) {
		excludePath = filepath.Join(worktreePath, excludePath)
	}
	if err := os.MkdirAll(filepath.Dir(excludePath), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(excludePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	for _, pattern := range gitExcludes {
		if _, err := fmt.Fprintln(f, pattern); err != nil {
			return err
		}
	}
	return nil
}

func ApplyRcmOverlay(engArea, worktreePath string) error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	rcmDir := filepath.Join(home, engArea, "rcm-worktrees")
	info, err := os.Stat(rcmDir)
	if err != nil || !info.IsDir() {
		return nil
	}

	return filepath.Walk(rcmDir, func(src string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(rcmDir, src)
		dest := filepath.Join(worktreePath, "."+rel)
		if _, err := os.Stat(dest); err == nil {
			return nil // don't overwrite existing
		}
		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			return err
		}
		return os.Symlink(src, dest)
	})
}
