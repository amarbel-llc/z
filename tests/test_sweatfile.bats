#!/usr/bin/env bats

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  export output
  setup_test_home
  setup_mock_path

  # Mock zmx to exit immediately
  cat > "$MOCK_BIN/zmx" <<'MOCKEOF'
#!/bin/bash
exit 0
MOCKEOF
  chmod +x "$MOCK_BIN/zmx"

  # Create a real git repo as the "main repo"
  mkdir -p "$HOME/eng/repos/testrepo"
  git init -q "$HOME/eng/repos/testrepo"
  git -C "$HOME/eng/repos/testrepo" commit --allow-empty -m "init" -q

  # Create eng-area sweatfile with only git_excludes
  cat > "$HOME/eng/sweatfile" <<'EOF'
git_excludes = [".claude/", ".direnv/"]
EOF
}

function sweatfile_applies_git_excludes { # @test
  run sweatshop open "eng/worktrees/testrepo/feature-exc" --format tap
  [[ "$status" -eq 0 ]]
  local wt="$HOME/eng/worktrees/testrepo/feature-exc"
  local exclude_path
  exclude_path="$(git -C "$wt" rev-parse --git-path info/exclude)"
  if [[ ! "$exclude_path" = /* ]]; then
    exclude_path="$wt/$exclude_path"
  fi
  grep -q ".claude/" "$exclude_path"
  grep -q ".direnv/" "$exclude_path"
}

function sweatfile_repo_sweatfile_merges_with_eng_area { # @test
  cat > "$HOME/eng/repos/testrepo/sweatfile" <<'EOF'
git_excludes = [".envrc"]
EOF

  run sweatshop open "eng/worktrees/testrepo/feature-merge" --format tap
  [[ "$status" -eq 0 ]]
  local wt="$HOME/eng/worktrees/testrepo/feature-merge"
  local exclude_path
  exclude_path="$(git -C "$wt" rev-parse --git-path info/exclude)"
  if [[ ! "$exclude_path" = /* ]]; then
    exclude_path="$wt/$exclude_path"
  fi
  # Should have both eng-area and repo excludes
  grep -q ".claude/" "$exclude_path"
  grep -q ".direnv/" "$exclude_path"
  grep -q ".envrc" "$exclude_path"
}

function no_attach_creates_worktree_without_calling_zmx { # @test
  # Make zmx create a marker file so we can detect if it ran
  cat > "$MOCK_BIN/zmx" <<'MOCKEOF'
#!/bin/bash
touch "$HOME/.zmx-was-called"
exit 0
MOCKEOF
  chmod +x "$MOCK_BIN/zmx"

  run sweatshop open "eng/worktrees/testrepo/feature-noattach" --no-attach --format tap
  [[ "$status" -eq 0 ]]
  # Worktree should be created
  [[ -d "$HOME/eng/worktrees/testrepo/feature-noattach" ]]
  # zmx should NOT have been called
  [[ ! -f "$HOME/.zmx-was-called" ]]
}

function sweatfile_empty_sections_produce_clean_worktree { # @test
  # Replace eng-area sweatfile with minimal content
  cat > "$HOME/eng/sweatfile" <<'EOF'
git_excludes = [".claude/"]
EOF

  run sweatshop open "eng/worktrees/testrepo/feature-empty" --format tap
  [[ "$status" -eq 0 ]]
  # Worktree should still be created
  [[ -d "$HOME/eng/worktrees/testrepo/feature-empty" ]]
}
