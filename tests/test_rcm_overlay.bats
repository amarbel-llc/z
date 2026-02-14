#!/usr/bin/env bats

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  export output
  setup_test_home
  setup_mock_path
  source "$BIN_DIR/z"
}

function overlay_copies_files_as_dotfiles { # @test
  local rcm="$HOME/eng/rcm-worktrees"
  mkdir -p "$rcm/config/git"
  echo "some-config" >"$rcm/config/git/ignore"

  local worktree="$HOME/eng/worktrees/myrepo/feature-x"
  mkdir -p "$worktree"

  z_apply_rcm_worktrees_overlay "eng" "$worktree"

  [[ -f "$worktree/.config/git/ignore" ]]
  [[ "$(cat "$worktree/.config/git/ignore")" == "some-config" ]]
}

function overlay_does_not_overwrite_existing_files { # @test
  local rcm="$HOME/eng/rcm-worktrees"
  mkdir -p "$rcm"
  echo "overlay-content" >"$rcm/gitignore"

  local worktree="$HOME/eng/worktrees/myrepo/feature-x"
  mkdir -p "$worktree"
  echo "existing-content" >"$worktree/.gitignore"

  z_apply_rcm_worktrees_overlay "eng" "$worktree"

  [[ "$(cat "$worktree/.gitignore")" == "existing-content" ]]
}

function overlay_skips_when_rcm_worktrees_missing { # @test
  local worktree="$HOME/eng/worktrees/myrepo/feature-x"
  mkdir -p "$worktree"

  # Should not error when rcm-worktrees doesn't exist
  run z_apply_rcm_worktrees_overlay "eng" "$worktree"
  [[ "$status" -eq 0 ]]
}

function overlay_handles_multiple_files { # @test
  local rcm="$HOME/eng/rcm-worktrees"
  mkdir -p "$rcm/config"
  echo "a" >"$rcm/gitignore"
  echo "b" >"$rcm/config/foo"

  local worktree="$HOME/eng/worktrees/myrepo/feature-x"
  mkdir -p "$worktree"

  z_apply_rcm_worktrees_overlay "eng" "$worktree"

  [[ -f "$worktree/.gitignore" ]]
  [[ -f "$worktree/.config/foo" ]]
  [[ "$(cat "$worktree/.gitignore")" == "a" ]]
  [[ "$(cat "$worktree/.config/foo")" == "b" ]]
}
