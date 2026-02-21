#!/usr/bin/env bats

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  export output
  setup_test_home
  setup_mock_path

  # Mock SHELL to exit immediately (ShellExecutor runs $SHELL when no command given)
  cat > "$MOCK_BIN/mock-shell" <<'MOCKEOF'
#!/bin/bash
exit 0
MOCKEOF
  chmod +x "$MOCK_BIN/mock-shell"
  export SHELL="$MOCK_BIN/mock-shell"

  # Create a real git repo as the "main repo"
  mkdir -p "$HOME/eng/repos/testrepo"
  git init -q "$HOME/eng/repos/testrepo"
  git -C "$HOME/eng/repos/testrepo" commit --allow-empty -m "init" -q

  # Create parent-directory sweatfile (LoadHierarchy walks parents from home to repo)
  cat > "$HOME/eng/sweatfile" <<'EOF'
git_excludes = [".claude/", ".direnv/"]
EOF
}

function sweatfile_applies_git_excludes { # @test
  cd "$HOME/eng/repos/testrepo"
  run sweatshop attach "feature-exc" --format tap
  [[ "$status" -eq 0 ]]
  local wt="$HOME/eng/repos/testrepo/.worktrees/feature-exc"
  local exclude_path
  exclude_path="$(git -C "$wt" rev-parse --git-path info/exclude)"
  if [[ ! "$exclude_path" = /* ]]; then
    exclude_path="$wt/$exclude_path"
  fi
  grep -q ".claude/" "$exclude_path"
  grep -q ".direnv/" "$exclude_path"
}

function sweatfile_repo_sweatfile_merges_with_parent_dir { # @test
  cat > "$HOME/eng/repos/testrepo/sweatfile" <<'EOF'
git_excludes = [".envrc"]
EOF

  cd "$HOME/eng/repos/testrepo"
  run sweatshop attach "feature-merge" --format tap
  [[ "$status" -eq 0 ]]
  local wt="$HOME/eng/repos/testrepo/.worktrees/feature-merge"
  local exclude_path
  exclude_path="$(git -C "$wt" rev-parse --git-path info/exclude)"
  if [[ ! "$exclude_path" = /* ]]; then
    exclude_path="$wt/$exclude_path"
  fi
  # Should have both parent-dir and repo excludes
  grep -q ".claude/" "$exclude_path"
  grep -q ".direnv/" "$exclude_path"
  grep -q ".envrc" "$exclude_path"
}

function create_makes_worktree_without_running_shell { # @test
  # Make mock shell create a marker file so we can detect if it ran
  cat > "$MOCK_BIN/mock-shell" <<'MOCKEOF'
#!/bin/bash
touch "$HOME/.shell-was-called"
exit 0
MOCKEOF
  chmod +x "$MOCK_BIN/mock-shell"

  cd "$HOME/eng/repos/testrepo"
  run sweatshop create "feature-create"
  [[ "$status" -eq 0 ]]
  # Worktree should be created
  [[ -d "$HOME/eng/repos/testrepo/.worktrees/feature-create" ]]
  # Shell should NOT have been called
  [[ ! -f "$HOME/.shell-was-called" ]]

  # Claude settings should be generated
  local wt="$HOME/eng/repos/testrepo/.worktrees/feature-create"
  local settings="$wt/.claude/settings.local.json"
  [[ -f "$settings" ]]

  # defaultMode should be acceptEdits
  local mode
  mode="$(jq -r '.permissions.defaultMode' "$settings")"
  [[ "$mode" = "acceptEdits" ]]

  # Scoped Edit and Write rules should be present
  jq -e ".permissions.allow | map(select(startswith(\"Edit(\"))) | length > 0" "$settings" >/dev/null
  jq -e ".permissions.allow | map(select(startswith(\"Write(\"))) | length > 0" "$settings" >/dev/null
}

function create_from_custom_repo { # @test
  # Create a repo in a non-standard location
  mkdir -p "$HOME/custom/location/myrepo"
  git init -q "$HOME/custom/location/myrepo"
  git -C "$HOME/custom/location/myrepo" commit --allow-empty -m "custom init" -q

  cd "$HOME/custom/location/myrepo"
  run sweatshop create "feature-custom"
  [[ "$status" -eq 0 ]]

  # Worktree should be created
  local wt="$HOME/custom/location/myrepo/.worktrees/feature-custom"
  [[ -d "$wt" ]]

  # Verify the worktree was created from the custom repo
  git -C "$wt" log --oneline | grep -q "custom init"
}

function sweatfile_empty_sections_produce_clean_worktree { # @test
  # Replace parent-dir sweatfile with minimal content
  cat > "$HOME/eng/sweatfile" <<'EOF'
git_excludes = [".claude/"]
EOF

  cd "$HOME/eng/repos/testrepo"
  run sweatshop attach "feature-empty" --format tap
  [[ "$status" -eq 0 ]]
  # Worktree should still be created
  [[ -d "$HOME/eng/repos/testrepo/.worktrees/feature-empty" ]]
}

function create_with_arbitrary_absolute_path { # @test
  local wt="$BATS_TEST_TMPDIR/arbitrary-wt"
  cd "$HOME/eng/repos/testrepo"
  run sweatshop create "$wt"
  [[ "$status" -eq 0 ]]
  # Worktree should be created at the arbitrary path
  [[ -d "$wt" ]]
  # Verify it was created from the correct repo
  git -C "$wt" log --oneline | grep -q "init"
}

function create_trusts_worktree_in_claude_json { # @test
  cd "$HOME/eng/repos/testrepo"
  run sweatshop create "feature-trust"
  [[ "$status" -eq 0 ]]

  local wt="$HOME/eng/repos/testrepo/.worktrees/feature-trust"
  local claude_json="$HOME/.claude.json"
  [[ -f "$claude_json" ]]

  # The worktree path should be trusted
  local accepted
  accepted="$(jq -r --arg p "$wt" '.projects[$p].hasTrustDialogAccepted' "$claude_json")"
  [[ "$accepted" = "true" ]]
}

function create_trust_preserves_existing_claude_json { # @test
  # Pre-populate ~/.claude.json with existing data
  cat > "$HOME/.claude.json" <<JSONEOF
{
  "numStartups": 42,
  "projects": {
    "/some/other/project": {
      "hasTrustDialogAccepted": true
    }
  }
}
JSONEOF

  cd "$HOME/eng/repos/testrepo"
  run sweatshop create "feature-trust-preserve"
  [[ "$status" -eq 0 ]]

  local wt="$HOME/eng/repos/testrepo/.worktrees/feature-trust-preserve"
  local claude_json="$HOME/.claude.json"

  # New worktree should be trusted
  local accepted
  accepted="$(jq -r --arg p "$wt" '.projects[$p].hasTrustDialogAccepted' "$claude_json")"
  [[ "$accepted" = "true" ]]

  # Existing project entry should be preserved
  local other
  other="$(jq -r '.projects["/some/other/project"].hasTrustDialogAccepted' "$claude_json")"
  [[ "$other" = "true" ]]

  # Top-level keys should be preserved
  local startups
  startups="$(jq -r '.numStartups' "$claude_json")"
  [[ "$startups" = "42" ]]
}

function create_outside_git_repo_fails { # @test
  local non_repo="$BATS_TEST_TMPDIR/not-a-repo"
  mkdir -p "$non_repo"
  cd "$non_repo"
  run sweatshop create "some-branch"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no git repository"* ]]
}

function attach_with_arbitrary_path { # @test
  local wt="$BATS_TEST_TMPDIR/arbitrary-attach"
  cd "$HOME/eng/repos/testrepo"
  run sweatshop attach "$wt" --format tap
  [[ "$status" -eq 0 ]]
  # Worktree should be created
  [[ -d "$wt" ]]
}
