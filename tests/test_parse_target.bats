#!/usr/bin/env bats

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  export output
  setup_test_home
  setup_mock_path
  source "$BIN_DIR/z"
}

function parse_local_path { # @test
  local result
  result="$(z_parse_target "eng/worktrees/myrepo/mybranch")"
  local host path
  host="$(sed -n '1p' <<<"$result")"
  path="$(sed -n '2p' <<<"$result")"

  [[ -z "$host" ]]
  [[ "$path" == "eng/worktrees/myrepo/mybranch" ]]
}

function parse_remote_target { # @test
  local result
  result="$(z_parse_target "vm-host:eng/worktrees/myrepo/mybranch")"
  local host path
  host="$(sed -n '1p' <<<"$result")"
  path="$(sed -n '2p' <<<"$result")"

  [[ "$host" == "vm-host" ]]
  [[ "$path" == "eng/worktrees/myrepo/mybranch" ]]
}

function parse_target_without_colon_returns_empty_host { # @test
  local result
  result="$(z_parse_target "simple/path")"
  local host path
  host="$(sed -n '1p' <<<"$result")"
  path="$(sed -n '2p' <<<"$result")"

  [[ -z "$host" ]]
  [[ "$path" == "simple/path" ]]
}

function parse_target_preserves_remote_path { # @test
  local result
  result="$(z_parse_target "myhost:eng2/worktrees/dodder/feature-x")"
  local host path
  host="$(sed -n '1p' <<<"$result")"
  path="$(sed -n '2p' <<<"$result")"

  [[ "$host" == "myhost" ]]
  [[ "$path" == "eng2/worktrees/dodder/feature-x" ]]
}
