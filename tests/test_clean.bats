#!/usr/bin/env bats

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  export output
  setup_test_home
  setup_mock_path
}

create_repo_with_commit() {
  local repo_path="$1"
  mkdir -p "$repo_path"
  git -C "$repo_path" init -q
  git -C "$repo_path" commit --allow-empty -m "init" -q
}

create_merged_worktree() {
  local repo_path="$1"
  local branch="$2"
  local worktree_path="$repo_path/.worktrees/$branch"

  mkdir -p "$(dirname "$worktree_path")"
  git -C "$repo_path" worktree add -q "$worktree_path" -b "$branch"
  # Make a commit so the branch exists, then merge it back
  git -C "$worktree_path" commit --allow-empty -m "worktree commit" -q
  git -C "$repo_path" merge "$branch" --ff-only -q
}

create_unmerged_worktree() {
  local repo_path="$1"
  local branch="$2"
  local worktree_path="$repo_path/.worktrees/$branch"

  mkdir -p "$(dirname "$worktree_path")"
  git -C "$repo_path" worktree add -q "$worktree_path" -b "$branch"
  # Make a commit that is NOT merged back
  git -C "$worktree_path" commit --allow-empty -m "unmerged commit" -q
}

function clean_removes_merged_clean_worktrees { # @test
  create_repo_with_commit "$HOME/eng/repos/myrepo"
  create_merged_worktree "$HOME/eng/repos/myrepo" "done-branch"

  cd "$HOME/eng/repos"
  run sweatshop clean
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"TAP version 14"* ]]
  [[ "$output" == *"ok"*"remove myrepo/.worktrees/"*"done-branch"* ]]
  [[ ! -d "$HOME/eng/repos/myrepo/.worktrees/done-branch" ]]
}

function clean_skips_unmerged_worktrees { # @test
  create_repo_with_commit "$HOME/eng/repos/myrepo"
  create_unmerged_worktree "$HOME/eng/repos/myrepo" "wip-branch"

  cd "$HOME/eng/repos"
  run sweatshop clean
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"remove"*"wip-branch"* ]]
  [[ -d "$HOME/eng/repos/myrepo/.worktrees/wip-branch" ]]
}

function clean_skips_dirty_worktrees_without_interactive { # @test
  create_repo_with_commit "$HOME/eng/repos/myrepo"
  create_merged_worktree "$HOME/eng/repos/myrepo" "dirty-branch"
  echo "uncommitted" >"$HOME/eng/repos/myrepo/.worktrees/dirty-branch/dirty.txt"

  cd "$HOME/eng/repos"
  run sweatshop clean
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"# SKIP dirty worktree"* ]]
  [[ -d "$HOME/eng/repos/myrepo/.worktrees/dirty-branch" ]]
}

function clean_reports_plan_line { # @test
  create_repo_with_commit "$HOME/eng/repos/myrepo"
  create_merged_worktree "$HOME/eng/repos/myrepo" "merged-a"
  create_merged_worktree "$HOME/eng/repos/myrepo" "merged-b"

  cd "$HOME/eng/repos"
  run sweatshop clean
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"1..2"* ]]
}

function clean_shows_message_when_no_worktrees { # @test
  local empty_dir="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$empty_dir"
  cd "$empty_dir"
  run sweatshop clean
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"# SKIP no worktrees found"* ]]
}

function clean_handles_mixed_merged_and_unmerged { # @test
  create_repo_with_commit "$HOME/eng/repos/myrepo"
  create_merged_worktree "$HOME/eng/repos/myrepo" "merged"
  create_unmerged_worktree "$HOME/eng/repos/myrepo" "unmerged"

  cd "$HOME/eng/repos"
  run sweatshop clean
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"1..1"* ]]
  [[ ! -d "$HOME/eng/repos/myrepo/.worktrees/merged" ]]
  [[ -d "$HOME/eng/repos/myrepo/.worktrees/unmerged" ]]
}

function clean_works_across_repos { # @test
  create_repo_with_commit "$HOME/eng/repos/repo-a"
  create_repo_with_commit "$HOME/eng/repos/repo-b"
  create_merged_worktree "$HOME/eng/repos/repo-a" "done-a"
  create_merged_worktree "$HOME/eng/repos/repo-b" "done-b"

  cd "$HOME/eng/repos"
  run sweatshop clean
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"1..2"* ]]
  [[ ! -d "$HOME/eng/repos/repo-a/.worktrees/done-a" ]]
  [[ ! -d "$HOME/eng/repos/repo-b/.worktrees/done-b" ]]
}

function clean_table_format_uses_log_output { # @test
  create_repo_with_commit "$HOME/eng/repos/myrepo"
  create_merged_worktree "$HOME/eng/repos/myrepo" "done-branch"

  cd "$HOME/eng/repos"
  run sweatshop clean --format table
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"removed"* ]]
  [[ "$output" == *"done-branch"* ]]
  [[ "$output" != *"TAP version"* ]]
}
