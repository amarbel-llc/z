package sweatfile

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

type Sweatfile struct {
	GitExcludes []string `toml:"git_excludes"`
	ClaudeAllow []string `toml:"claude_allow"`
}

func Parse(data []byte) (Sweatfile, error) {
	var sf Sweatfile
	if err := toml.Unmarshal(data, &sf); err != nil {
		return Sweatfile{}, err
	}
	return sf, nil
}

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
	if repo.ClaudeAllow != nil {
		if len(repo.ClaudeAllow) == 0 {
			merged.ClaudeAllow = []string{}
		} else {
			merged.ClaudeAllow = append(base.ClaudeAllow, repo.ClaudeAllow...)
		}
	}

	return merged
}

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

type LoadSource struct {
	Path  string
	Found bool
	File  Sweatfile
}

type LoadResult struct {
	Sources []LoadSource
	Merged  Sweatfile
}

func LoadMerged(engAreaDir, repoDir string) (LoadResult, error) {
	basePath := filepath.Join(engAreaDir, "sweatfile")
	base, err := Load(basePath)
	if err != nil {
		return LoadResult{}, err
	}

	repoPath := filepath.Join(repoDir, "sweatfile")
	repo, err := Load(repoPath)
	if err != nil {
		return LoadResult{}, err
	}

	_, baseFound := fileExists(basePath)
	_, repoFound := fileExists(repoPath)

	merged := Merge(base, repo)

	return LoadResult{
		Sources: []LoadSource{
			{Path: basePath, Found: baseFound, File: base},
			{Path: repoPath, Found: repoFound, File: repo},
		},
		Merged: merged,
	}, nil
}

func fileExists(path string) (os.FileInfo, bool) {
	info, err := os.Stat(path)
	return info, err == nil
}

func LoadSingle(path string) (LoadResult, error) {
	sf, err := Load(path)
	if err != nil {
		return LoadResult{}, err
	}
	_, found := fileExists(path)
	return LoadResult{
		Sources: []LoadSource{
			{Path: path, Found: found, File: sf},
		},
		Merged: sf,
	}, nil
}
