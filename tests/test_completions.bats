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

function completions_lists_repos_as_new_worktree { # @test
  create_mock_repo "$HOME/eng/repos/myrepo"

  cd "$HOME/eng/repos"
  run sweatshop completions
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"myrepo/"*"new worktree"* ]]
}

function completions_lists_existing_worktrees { # @test
  create_mock_repo "$HOME/eng/repos/myrepo"
  local wt_path="$HOME/eng/repos/myrepo/.worktrees/feature-x"
  git -C "$HOME/eng/repos/myrepo" worktree add -q "$wt_path" -b "feature-x"

  cd "$HOME/eng/repos"
  run sweatshop completions
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"myrepo/.worktrees/feature-x"*"existing worktree"* ]]
}

function completions_handles_multiple_repos { # @test
  create_mock_repo "$HOME/eng/repos/repo-a"
  create_mock_repo "$HOME/eng/repos/repo-b"

  cd "$HOME/eng/repos"
  run sweatshop completions
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"repo-a/"* ]]
  [[ "$output" == *"repo-b/"* ]]
}

function completions_output_is_tab_separated { # @test
  create_mock_repo "$HOME/eng/repos/myrepo"

  cd "$HOME/eng/repos"
  run sweatshop completions
  [[ "$status" -eq 0 ]]
  local line
  line="$(echo "$output" | head -1)"
  [[ "$line" == *$'\t'* ]]
}

function completions_handles_no_repos { # @test
  local empty_dir="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$empty_dir"
  cd "$empty_dir"
  run sweatshop completions
  [[ "$status" -eq 0 ]]
}
