#!/bin/bash
INPUT=$(cat)

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
PROJECT=$(basename "$CWD")

case "$EVENT" in
  Stop)
    MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')
    TITLE="Claude Code Done"
    ;;
  Notification)
    MESSAGE=$(echo "$INPUT" | jq -r '.message // empty')
    TITLE="Claude Code"
    ;;
  *)
    MESSAGE="Needs your attention"
    TITLE="Claude Code"
    ;;
esac

# Truncate message for notification (keep first 100 chars)
SUMMARY=$(echo "$MESSAGE" | head -c 100)
if [ ${#MESSAGE} -gt 100 ]; then
  SUMMARY="${SUMMARY}..."
fi

# Ring the terminal bell (triggers Alacritty bell config)
printf '\a'

# Send notification via terminal-notifier
# - Click notification to focus Alacritty
# - Notifications persist in Notification Center as a reviewable list
terminal-notifier \
  -title "$TITLE" \
  -subtitle "$PROJECT — $CWD" \
  -message "$SUMMARY" \
  -activate org.alacritty \
  -group "claude-$PROJECT" \
  -sound default

exit 0
