package sweatfile

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

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

func RouteEnvDecisions(repoSweatfilePath, envFilePath string, decisions []EnvDecision) error {
	sf, err := Load(repoSweatfilePath)
	if err != nil {
		return err
	}

	var toRemove []string

	for _, d := range decisions {
		switch d.Action {
		case EnvPromoteRepo:
			if sf.Env == nil {
				sf.Env = make(map[string]string)
			}
			sf.Env[d.Key] = d.Value
			toRemove = append(toRemove, d.Key)
		case EnvDiscard:
			toRemove = append(toRemove, d.Key)
		case EnvKeep:
			// leave in .sweatshop-env
		}
	}

	// Write updated repo sweatfile if any promotions happened
	for _, d := range decisions {
		if d.Action == EnvPromoteRepo {
			if err := Save(repoSweatfilePath, sf); err != nil {
				return err
			}
			break
		}
	}

	if len(toRemove) > 0 {
		return removeEnvKeys(envFilePath, toRemove)
	}

	return nil
}

func removeEnvKeys(path string, keys []string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}

	keySet := make(map[string]bool, len(keys))
	for _, k := range keys {
		keySet[k] = true
	}

	var kept []string
	for _, line := range strings.Split(strings.TrimRight(string(data), "\n"), "\n") {
		if idx := strings.IndexByte(line, '='); idx > 0 {
			if keySet[line[:idx]] {
				continue
			}
		}
		kept = append(kept, line)
	}

	if len(kept) == 0 {
		return os.Remove(path)
	}

	return os.WriteFile(path, []byte(strings.Join(kept, "\n")+"\n"), 0o644)
}
