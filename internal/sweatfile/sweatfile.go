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
