#!/bin/zsh
# Save each tmux pane running Claude Code to ~/.tmux-claude-session.
#
# Claude Code writes a state file at ~/.claude/sessions/<pid>.json containing
# its sessionId. We use the live process table to map each running claude pid
# to its controlling tty, then match those tties to tmux panes via
# `#{pane_tty}`. This gives an exact per-pane conversation mapping that
# `claude --resume <id>` can replay.

setopt NULL_GLOB
CLAUDE_SESSIONS_DIR="$HOME/.claude/sessions"
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
OUT_FILE="$HOME/.tmux-claude-session"

# Convert a directory path to Claude's project-dir name format.
# /Users/me/projects/foo -> -Users-me-projects-foo
path_to_project_dir() {
  echo "$1" | sed 's|[/.]|-|g'
}

# Return 0 if the conversation .jsonl for ($cwd, $sid) has at least one real
# user/assistant message. Some claude sessions create a stub .jsonl with only
# a "last-prompt" entry (e.g. transient/sub-agent invocations); `claude
# --resume` rejects those with "No conversation found".
is_resumable() {
  local cwd="$1" sid="$2"
  local pdir
  pdir=$(path_to_project_dir "$cwd")
  local jsonl="$CLAUDE_PROJECTS_DIR/$pdir/$sid.jsonl"
  [[ -f "$jsonl" ]] || return 1
  grep -q '"type":"user"\|"type":"assistant"' "$jsonl" 2>/dev/null
}

# Build tty -> sessionId map from live claude state files.
typeset -A tty_to_sid
typeset -A tty_to_cwd
for f in "$CLAUDE_SESSIONS_DIR"/*.json; do
  pid=${f:t:r}
  [[ "$pid" == *[!0-9]* ]] && continue
  tty=$(ps -p "$pid" -o tty= 2>/dev/null | tr -d ' ')
  [[ -z "$tty" || "$tty" == "?" ]] && continue
  sid=$(sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p' "$f" | head -1)
  cwd=$(sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p' "$f" | head -1)
  [[ -z "$sid" || -z "$cwd" ]] && continue
  is_resumable "$cwd" "$sid" || continue
  tty_to_sid[$tty]=$sid
  tty_to_cwd[$tty]=$cwd
done

entries=()
while IFS=$'\t' read -r session window pane tty cwd; do
  [[ -z "$tty" ]] && continue
  short_tty=${tty#/dev/}
  sid=${tty_to_sid[$short_tty]}
  [[ -z "$sid" ]] && continue
  entries+=("${session}:${window}.${pane}|${cwd}|${sid}")
done < <(tmux list-panes -a -F '#{session_name}	#{window_index}	#{pane_index}	#{pane_tty}	#{pane_current_path}' 2>/dev/null)

if (( ${#entries} == 0 )); then
  rm -f "$OUT_FILE"
  echo "No active claude panes found."
  exit 0
fi

printf '%s\n' "${entries[@]}" > "$OUT_FILE"
echo "Saved ${#entries} claude panes to $OUT_FILE"
