package worktree

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/amarbel-llc/sweatshop/internal/claude"
	"github.com/amarbel-llc/sweatshop/internal/git"
	"github.com/amarbel-llc/sweatshop/internal/sweatfile"
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

func (c PathComponents) ShopKey() string {
	return c.EngArea + "/" + c.Repo + "/" + c.Worktree
}

func RepoPath(home string, comp PathComponents) string {
	return filepath.Join(home, comp.EngArea, "repos", comp.Repo)
}

func WorktreePath(home string, sweatshopPath string) string {
	return filepath.Join(home, sweatshopPath)
}

func Create(engAreaDir, repoPath, worktreePath string) (sweatfile.LoadResult, error) {
	if err := os.MkdirAll(worktreePath, 0o755); err != nil {
		return sweatfile.LoadResult{}, fmt.Errorf("creating worktree directory: %w", err)
	}
	if err := git.RunPassthrough(repoPath, "worktree", "add", worktreePath); err != nil {
		return sweatfile.LoadResult{}, fmt.Errorf("git worktree add: %w", err)
	}
	var result sweatfile.LoadResult
	var err error
	if engAreaDir != "" {
		result, err = sweatfile.LoadMerged(engAreaDir, repoPath)
	} else {
		result, err = sweatfile.LoadSingle(filepath.Join(repoPath, "sweatfile"))
	}
	if err != nil {
		return sweatfile.LoadResult{}, fmt.Errorf("loading sweatfile: %w", err)
	}
	if err := sweatfile.Apply(worktreePath, result.Merged); err != nil {
		return sweatfile.LoadResult{}, err
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return sweatfile.LoadResult{}, fmt.Errorf("getting home directory: %w", err)
	}
	claudeJSONPath := filepath.Join(home, ".claude.json")
	if err := claude.TrustWorkspace(claudeJSONPath, worktreePath); err != nil {
		return sweatfile.LoadResult{}, fmt.Errorf("trusting workspace in claude: %w", err)
	}

	return result, nil
}

func IsWorktree(path string) bool {
	info, err := os.Lstat(filepath.Join(path, ".git"))
	if err != nil {
		return false
	}
	return !info.IsDir()
}

type ResolvedPath struct {
	AbsPath    string // absolute filesystem path to the worktree
	RepoPath   string // absolute path to the parent git repo
	SessionKey string // key for zmx/executor sessions
	Branch     string // branch name
	EngAreaDir string // absolute path to eng area dir (for sweatfile), or ""
	Convention bool   // true if path matches convention
}

func ResolvePath(home, rawPath, repoFlag string) (ResolvedPath, error) {
	comp, err := ParsePath(rawPath)
	if err == nil {
		absPath := filepath.Join(home, rawPath)
		repoPath := repoFlag
		if repoPath == "" {
			repoPath = RepoPath(home, comp)
		}
		engAreaDir := filepath.Join(home, comp.EngArea)
		return ResolvedPath{
			AbsPath:    absPath,
			RepoPath:   repoPath,
			SessionKey: comp.ShopKey(),
			Branch:     comp.Worktree,
			EngAreaDir: engAreaDir,
			Convention: true,
		}, nil
	}

	absPath := rawPath
	if !filepath.IsAbs(absPath) {
		cwd, err := os.Getwd()
		if err != nil {
			return ResolvedPath{}, fmt.Errorf("getting working directory: %w", err)
		}
		absPath = filepath.Join(cwd, absPath)
	}
	absPath = filepath.Clean(absPath)

	var repoPath string
	var branch string

	if _, statErr := os.Stat(absPath); statErr == nil && IsWorktree(absPath) {
		repoPath, err = git.CommonDir(absPath)
		if err != nil {
			return ResolvedPath{}, fmt.Errorf("detecting repo for existing worktree: %w", err)
		}
		branch, _ = git.BranchCurrent(absPath)
	} else if repoFlag != "" {
		repoPath = repoFlag
		branch = filepath.Base(absPath)
	} else {
		return ResolvedPath{}, fmt.Errorf("path %q does not match convention and --repo is required for new non-convention paths", rawPath)
	}

	sessionKey := absPath
	if strings.HasPrefix(sessionKey, home+"/") {
		sessionKey = sessionKey[len(home)+1:]
	}

	engAreaDir := findEngAreaDir(absPath, home)

	return ResolvedPath{
		AbsPath:    absPath,
		RepoPath:   repoPath,
		SessionKey: sessionKey,
		Branch:     branch,
		EngAreaDir: engAreaDir,
		Convention: false,
	}, nil
}

func findEngAreaDir(path, home string) string {
	dir := filepath.Dir(path)
	for dir != home && dir != "/" && dir != "." {
		if _, err := os.Stat(filepath.Join(dir, "sweatfile")); err == nil {
			return dir
		}
		dir = filepath.Dir(dir)
	}
	// Check home itself
	if _, err := os.Stat(filepath.Join(home, "sweatfile")); err == nil {
		return home
	}
	return ""
}

func (rp *ResolvedPath) FillBranchFromGit() error {
	branch, err := git.BranchCurrent(rp.AbsPath)
	if err != nil {
		return err
	}
	rp.Branch = branch
	return nil
}
