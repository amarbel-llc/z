#!/bin/bash -e

if [[ -z $BATS_TEST_TMPDIR ]]; then
  echo 'common.bash loaded before $BATS_TEST_TMPDIR set. aborting.' >&2
  exit 1
fi

pushd "$BATS_TEST_TMPDIR" >/dev/null || exit 1

# Directory containing the scripts under test
BIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../bin" && pwd)"

# Create a fake HOME for test isolation
setup_test_home() {
  export REAL_HOME="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

# Create mock commands in a temp bin directory on PATH
setup_mock_path() {
  export MOCK_BIN="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$BIN_DIR:$PATH"
}
