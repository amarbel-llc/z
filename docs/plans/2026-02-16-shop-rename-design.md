# Shop Open / Close Shop Rename

**Goal:** Replace zmx/attach terminology with "shop open" and "close shop" in all user-facing strings, CLI commands, and internal naming.

## Rename Mapping

### CLI Command

| Current | New |
|---------|-----|
| `sweatshop attach [target]` | `sweatshop open [target]` (alias: `attach`) |
| Short: "Attach to a worktree session" | Short: "Open a worktree shop" |
| Long: "Attach to an existing or new worktree session..." | Long: "Open an existing or new worktree shop..." |

### Package Rename

`internal/attach/` -> `internal/shop/`

| Current Function | New Function |
|-----------------|-------------|
| `attach.Remote` | `shop.OpenRemote` |
| `attach.Existing` | `shop.OpenExisting` |
| `attach.ToPath` | `shop.OpenNew` |
| `attach.PostZmx` | `shop.CloseShop` |

### User-Facing Strings

| Current | New |
|---------|-----|
| "connecting to remote session" | "opening remote shop" |
| "Post-zmx actions for X:" | "Close shop actions for X:" |
| "Post-zmx actions for X (uncommitted...)" | "Close shop actions for X (uncommitted changes, will not remove worktree):" |
| TAP: "post-zmx <branch>" | TAP: "close-shop <branch>" |
| "reattaching to session to resolve" | "reopening shop to resolve" |

### Not Renamed

- `zmx` binary invocations (it's the actual tool)
- `merge` subcommand
- Internal git/worktree/sweatfile packages
