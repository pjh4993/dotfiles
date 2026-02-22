#!/bin/bash
INPUT=$(cat)

NTFY_TOPIC="pyler-claude-cozhqjel"

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
PROJECT=$(basename "$CWD")
HOSTNAME=$(hostname -s)

case "$EVENT" in
  Stop)
    MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')
    TITLE="Claude Code Done"
    PRIORITY="default"
    TAGS="white_check_mark"
    ;;
  Notification)
    MESSAGE=$(echo "$INPUT" | jq -r '.message // empty')
    TITLE="Claude Code"
    PRIORITY="high"
    TAGS="bell"
    ;;
  *)
    MESSAGE="Needs your attention"
    TITLE="Claude Code"
    PRIORITY="high"
    TAGS="bell"
    ;;
esac

# Truncate message for notification (keep first 100 chars)
SUMMARY=$(echo "$MESSAGE" | head -c 100)
if [ ${#MESSAGE} -gt 100 ]; then
  SUMMARY="${SUMMARY}..."
fi

# Detect if running in a remote SSH session
is_remote() {
  [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ] || [ -n "$SSH_CONNECTION" ]
}

if is_remote; then
  # Remote: send push notification via ntfy.sh
  curl -s \
    -H "Title: $TITLE" \
    -H "Priority: $PRIORITY" \
    -H "Tags: $TAGS" \
    -d "[$HOSTNAME] $PROJECT — $SUMMARY" \
    "ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1
fi

exit 0
