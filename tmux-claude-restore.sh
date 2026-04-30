#!/bin/zsh
# Post-restore hook for tmux-resurrect: resume each saved Claude conversation
# in its mapped pane. Reads ~/.tmux-claude-session (written by
# tmux-claude-save.sh) and runs `claude --resume <sessionId>` in each pane.

SESSION_FILE="$HOME/.tmux-claude-session"
[[ -f "$SESSION_FILE" ]] || exit 0

# Give resurrect and shell rc files a moment to finish initializing.
sleep 2

restored=0
skipped=0

# Snapshot current panes once so we can check existence cheaply.
existing_panes=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null)

while IFS='|' read -r pane_id cwd sid; do
  [[ -z "$pane_id" || -z "$sid" ]] && continue

  if ! print -- "$existing_panes" | grep -Fxq "$pane_id"; then
    skipped=$((skipped + 1))
    continue
  fi

  # Only send keys if the pane is at a shell prompt; otherwise we might
  # clobber whatever the user has running there.
  cur_cmd=$(tmux display-message -p -t "$pane_id" '#{pane_current_command}' 2>/dev/null)
  case "$cur_cmd" in
    zsh|bash|fish|sh|-zsh|-bash)
      tmux send-keys -t "$pane_id" "claude --resume $sid" Enter
      restored=$((restored + 1))
      ;;
    *)
      skipped=$((skipped + 1))
      ;;
  esac
done < "$SESSION_FILE"

echo "Claude restore: resumed=$restored skipped=$skipped"
