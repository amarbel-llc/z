#!/bin/bash -e

if [[ -z $BATS_TEST_TMPDIR ]]; then
  echo 'common.bash loaded before $BATS_TEST_TMPDIR set. aborting.' >&2
  exit 1
fi

pushd "$BATS_TEST_TMPDIR" >/dev/null || exit 1

# Directory containing the Go binary under test
# When built with nix, the binary is in result/bin/
# When built with go build, it's in the project root
PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
if [[ -x "$PROJECT_DIR/result/bin/sweatshop" ]]; then
  BIN_DIR="$PROJECT_DIR/result/bin"
elif [[ -x "$PROJECT_DIR/build/sweatshop" ]]; then
  BIN_DIR="$PROJECT_DIR/build"
else
  echo "sweatshop binary not found. Run 'just build' or 'just build-go' first." >&2
  exit 1
fi

# Route XDG directories into a test-local path
set_xdg() {
  loc="$(realpath "$1" 2>/dev/null)"
  export XDG_DATA_HOME="$loc/.xdg/data"
  export XDG_CONFIG_HOME="$loc/.xdg/config"
  export XDG_STATE_HOME="$loc/.xdg/state"
  export XDG_CACHE_HOME="$loc/.xdg/cache"
  export XDG_RUNTIME_HOME="$loc/.xdg/runtime"
  mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" \
    "$XDG_CACHE_HOME" "$XDG_RUNTIME_HOME"
}

# Create a fake HOME for test isolation
setup_test_home() {
  export REAL_HOME="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  set_xdg "$BATS_TEST_TMPDIR"
  # Override GIT_CONFIG_GLOBAL so git --global writes to the isolated XDG dir
  mkdir -p "$XDG_CONFIG_HOME/git"
  export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
  # Seed a test identity so git commit works in the sandbox
  git config --global user.name "Test User"
  git config --global user.email "test@example.com"
  git config --global init.defaultBranch main
}

# Create mock commands in a temp bin directory on PATH
setup_mock_path() {
  export MOCK_BIN="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$BIN_DIR:$MOCK_BIN:$PATH"
}
