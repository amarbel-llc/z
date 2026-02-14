# z - git worktree session manager

default:
    @just --list

# Build the package
build:
    nix build

# Run the script
run *ARGS:
    nix run . -- {{ARGS}}

# Run tests
test:
    nix develop --command bats tests/

# Check with shellcheck
check:
    nix develop --command shellcheck bin/z bin/z-merge bin/z-completions

# Format with shfmt
fmt:
    nix develop --command shfmt -w -i 2 -ci bin/z bin/z-merge bin/z-completions

# Clean build artifacts
clean:
    rm -rf result
