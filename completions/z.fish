complete \
  --command z \
  --no-files \
  --condition __fish_use_subcommand \
  --arguments "attach" \
  --description "attach to a worktree session"

complete \
  --command z \
  --no-files \
  --keep-order \
  --condition "__fish_seen_subcommand_from attach" \
  --arguments "(z-completions)"
