#!/usr/bin/env bats

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  export output
  setup_test_home
  setup_mock_path
}

create_mock_repo() {
  local repo_path="$1"
  mkdir -p "$repo_path"
  git -C "$repo_path" init -q
  git -C "$repo_path" commit --allow-empty -m "init" -q
}

add_worktree() {
  local repo_path="$1"
  local branch="$2"
  local wt_path="$repo_path/.worktrees/$branch"
  git -C "$repo_path" worktree add -q "$wt_path" -b "$branch"
  # Exclude .worktrees from git status (matches real Create behavior)
  local exclude="$repo_path/.git/info/exclude"
  mkdir -p "$(dirname "$exclude")"
  if ! grep -qF ".worktrees" "$exclude" 2>/dev/null; then
    echo ".worktrees" >> "$exclude"
  fi
}

function status_discovers_multiple_repos { # @test
  create_mock_repo "$HOME/eng/repos/repo-a"
  add_worktree "$HOME/eng/repos/repo-a" "wt-a"
  create_mock_repo "$HOME/eng/repos/repo-b"
  add_worktree "$HOME/eng/repos/repo-b" "wt-b"

  cd "$HOME/eng/repos"
  run sweatshop status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"repo-a"* ]]
  [[ "$output" == *"repo-b"* ]]
}

function status_handles_repos_with_worktrees { # @test
  create_mock_repo "$HOME/eng/repos/myrepo"
  add_worktree "$HOME/eng/repos/myrepo" "feature-x"

  cd "$HOME/eng/repos"
  run sweatshop status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"myrepo"* ]]
  [[ "$output" == *"feature-x"* ]]
}

function status_shows_clean_for_clean_repo { # @test
  create_mock_repo "$HOME/eng/repos/clean-repo"
  add_worktree "$HOME/eng/repos/clean-repo" "wt"

  cd "$HOME/eng/repos"
  run sweatshop status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"clean"* ]]
}

function status_shows_dirty_count { # @test
  create_mock_repo "$HOME/eng/repos/dirty-repo"
  add_worktree "$HOME/eng/repos/dirty-repo" "wt"
  echo "change" >"$HOME/eng/repos/dirty-repo/file.txt"

  cd "$HOME/eng/repos"
  run sweatshop status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"1?"* ]]
}

function status_shows_no_repos_message { # @test
  local empty_dir="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$empty_dir"
  cd "$empty_dir"
  run sweatshop status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"no repos found"* ]]
}

function status_skips_non_git_directories { # @test
  mkdir -p "$HOME/eng/repos/not-a-repo"

  cd "$HOME/eng/repos"
  run sweatshop status
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"not-a-repo"* ]]
}

function status_tap_format_outputs_tap { # @test
  create_mock_repo "$HOME/eng/repos/repo-a"
  add_worktree "$HOME/eng/repos/repo-a" "wt"

  cd "$HOME/eng/repos"
  run sweatshop status --format tap
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"TAP version 14"* ]]
  [[ "$output" == *"ok"*"repo-a"* ]]
  [[ "$output" == *"1.."* ]]
}
