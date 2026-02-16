#!/usr/bin/env bats

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  export output
  setup_test_home
  setup_mock_path
  export PERMS_DIR="$HOME/.config/sweatshop/permissions"
}

create_global_tier() {
  mkdir -p "$PERMS_DIR"
  cat >"$PERMS_DIR/global.json" <<'EOF'
{
  "allow": [
    "Bash(git *)",
    "Bash(go test:*)"
  ]
}
EOF
}

create_repo_tier() {
  local repo="$1"
  shift
  mkdir -p "$PERMS_DIR/repos"
  local rules
  rules=$(printf '"%s"' "$1")
  shift
  for r in "$@"; do
    rules="$rules, \"$r\""
  done
  cat >"$PERMS_DIR/repos/${repo}.json" <<EOF
{
  "allow": [
    $rules
  ]
}
EOF
}

function perms_check_approves_matching_global_rule { # @test
  create_global_tier

  local result
  result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"'"$HOME"'/eng/worktrees/myrepo/feature"}' \
    | SWEATSHOP_PERMS_DIR="$PERMS_DIR" sweatshop perms check)

  [[ "$result" == *'"behavior":"allow"'* ]]
  [[ "$result" == *"global tier"* ]]
}

function perms_check_passes_through_non_matching { # @test
  create_global_tier

  local result
  result=$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"cwd":"'"$HOME"'/eng/worktrees/myrepo/feature"}' \
    | SWEATSHOP_PERMS_DIR="$PERMS_DIR" sweatshop perms check)

  [[ -z "$result" ]]
}

function perms_check_uses_repo_tier { # @test
  create_global_tier
  create_repo_tier "myrepo" "Bash(cargo test:*)"

  local result
  result=$(echo '{"tool_name":"Bash","tool_input":{"command":"cargo test --release"},"cwd":"'"$HOME"'/eng/worktrees/myrepo/feature"}' \
    | SWEATSHOP_PERMS_DIR="$PERMS_DIR" sweatshop perms check)

  [[ "$result" == *'"behavior":"allow"'* ]]
  [[ "$result" == *"myrepo tier"* ]]
}

function perms_list_shows_tiers { # @test
  create_global_tier
  create_repo_tier "myrepo" "Bash(cargo test:*)" "Read"

  run env SWEATSHOP_PERMS_DIR="$PERMS_DIR" sweatshop perms list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Global tier"* ]]
  [[ "$output" == *"Bash(git *)"* ]]
  [[ "$output" == *"Bash(go test:*)"* ]]
  [[ "$output" == *"Repo tier (myrepo)"* ]]
  [[ "$output" == *"Bash(cargo test:*)"* ]]
  [[ "$output" == *"Read"* ]]
}

function perms_check_handles_empty_tiers_dir { # @test
  mkdir -p "$PERMS_DIR"

  local result
  result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"'"$HOME"'/eng/worktrees/myrepo/feature"}' \
    | SWEATSHOP_PERMS_DIR="$PERMS_DIR" sweatshop perms check)

  [[ -z "$result" ]]
}
