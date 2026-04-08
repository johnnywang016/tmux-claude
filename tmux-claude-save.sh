#!/bin/zsh
# Save all active tmux panes running claude to ~/.tmux-claude-session
# Maps each pane's working directory to its most recent Claude conversation ID

CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
SESSION_FILE="$HOME/.tmux-claude-session"

# Convert a directory path to claude's project dir name
# /home/johnny/projects/dyna -> -home-johnny-projects-dyna
path_to_project_dir() {
  echo "$1" | sed 's|[/.]|-|g'
}

# Find the most recent conversation ID for a given working directory
find_conversation_id() {
  local dir="$1"
  local project_dir_name
  project_dir_name=$(path_to_project_dir "$dir")
  local project_path="$CLAUDE_PROJECTS_DIR/$project_dir_name"

  if [[ -d "$project_path" ]]; then
    local latest
    latest=$(ls -t "$project_path"/*.jsonl 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
      basename "$latest" .jsonl
    fi
  fi
}

# Find all tmux panes running claude (any directory)
entries=()
while IFS=$'\t' read -r session_name window_index pane_index pane_cwd pane_cmd; do
  [[ -z "$pane_cwd" ]] && continue
  # Match panes where the running command looks like claude
  if [[ "$pane_cmd" =~ (^|/)claude || "$pane_cmd" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    conv_id=$(find_conversation_id "$pane_cwd")
    if [[ -n "$conv_id" ]]; then
      key="${session_name}:${window_index}.${pane_index}"
      entries+=("${key}|${pane_cwd}|${conv_id}")
    fi
  fi
done < <(tmux list-panes -a -F '#{session_name}	#{window_index}	#{pane_index}	#{pane_current_path}	#{pane_current_command}' 2>/dev/null)

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "No active claude panes found."
  rm -f "$SESSION_FILE"
  exit 0
fi

printf '%s\n' "${entries[@]}" > "$SESSION_FILE"
echo "Saved ${#entries[@]} claude panes to $SESSION_FILE:"
cat "$SESSION_FILE"
