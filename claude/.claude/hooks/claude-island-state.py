#!/usr/bin/env python3
"""
Claude Island Hook
- Sends session state to ClaudeIsland.app via Unix socket
- For PermissionRequest: waits for user decision from the app
- Remote fallback: sends events via ntfy.sh when socket is unavailable
"""
import json
import os
import socket
import sys
import urllib.request

SOCKET_PATH = "/tmp/claude-island.sock"
TIMEOUT_SECONDS = 300  # 5 minutes for permission decisions
NTFY_TOPIC = "pyler-claude-cozhqjel"


def is_remote():
    """Detect if running in a remote SSH session"""
    return bool(
        os.environ.get("SSH_CLIENT")
        or os.environ.get("SSH_TTY")
        or os.environ.get("SSH_CONNECTION")
    )


def send_ntfy(state):
    """Send event to ntfy.sh as a fallback for remote sessions"""
    status = state.get("status", "unknown")
    event = state.get("event", "")
    cwd = state.get("cwd", "")
    project = os.path.basename(cwd)
    hostname = socket.gethostname()

    # Build a human-readable message
    tool = state.get("tool", "")
    message = state.get("message", "")

    status_labels = {
        "processing": "Processing...",
        "running_tool": f"Running: {tool}",
        "waiting_for_input": "Waiting for input",
        "waiting_for_approval": f"Permission needed: {tool}",
        "notification": message or "Notification",
        "compacting": "Compacting context",
        "ended": "Session ended",
    }
    body = status_labels.get(status, status)

    # Set priority based on status
    priority = "default"
    tags = "robot_face"
    if status == "waiting_for_input":
        priority = "high"
        tags = "white_check_mark"
    elif status == "waiting_for_approval":
        priority = "urgent"
        tags = "warning"

    title = f"[{hostname}] {project}"

    try:
        data = body.encode("utf-8")
        req = urllib.request.Request(
            f"https://ntfy.sh/{NTFY_TOPIC}",
            data=data,
            headers={
                "Title": title,
                "Priority": priority,
                "Tags": tags,
            },
        )
        urllib.request.urlopen(req, timeout=5)
    except Exception:
        pass


def get_tty():
    """Get the TTY of the Claude process (parent)"""
    import subprocess

    # Get parent PID (Claude process)
    ppid = os.getppid()

    # Try to get TTY from ps command for the parent process
    try:
        result = subprocess.run(
            ["ps", "-p", str(ppid), "-o", "tty="],
            capture_output=True,
            text=True,
            timeout=2
        )
        tty = result.stdout.strip()
        if tty and tty != "??" and tty != "-":
            # ps returns just "ttys001", we need "/dev/ttys001"
            if not tty.startswith("/dev/"):
                tty = "/dev/" + tty
            return tty
    except Exception:
        pass

    # Fallback: try current process stdin/stdout
    try:
        return os.ttyname(sys.stdin.fileno())
    except (OSError, AttributeError):
        pass
    try:
        return os.ttyname(sys.stdout.fileno())
    except (OSError, AttributeError):
        pass
    return None


def send_event(state):
    """Send event to app, return response if any"""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())

        # For permission requests, wait for response
        if state.get("status") == "waiting_for_approval":
            response = sock.recv(4096)
            sock.close()
            if response:
                return json.loads(response.decode())
        else:
            sock.close()

        return None
    except (socket.error, OSError, json.JSONDecodeError):
        # Socket unavailable — fall back to ntfy for remote sessions
        if is_remote():
            send_ntfy(state)
        return None


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    session_id = data.get("session_id", "unknown")
    event = data.get("hook_event_name", "")
    cwd = data.get("cwd", "")
    tool_input = data.get("tool_input", {})

    # Get process info
    claude_pid = os.getppid()
    tty = get_tty()

    # Build state object
    state = {
        "session_id": session_id,
        "cwd": cwd,
        "event": event,
        "pid": claude_pid,
        "tty": tty,
    }

    # Map events to status
    if event == "UserPromptSubmit":
        # User just sent a message - Claude is now processing
        state["status"] = "processing"

    elif event == "PreToolUse":
        state["status"] = "running_tool"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # Send tool_use_id to Swift for caching
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PostToolUse":
        state["status"] = "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # Send tool_use_id so Swift can cancel the specific pending permission
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PermissionRequest":
        # This is where we can control the permission
        state["status"] = "waiting_for_approval"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # tool_use_id lookup handled by Swift-side cache from PreToolUse

        # Remote sessions: send ntfy notification but skip bidirectional approval
        if is_remote():
            send_ntfy(state)
            sys.exit(0)

        # Send to app and wait for decision
        response = send_event(state)

        if response:
            decision = response.get("decision", "ask")
            reason = response.get("reason", "")

            if decision == "allow":
                # Output JSON to approve
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {"behavior": "allow"},
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

            elif decision == "deny":
                # Output JSON to deny
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {
                            "behavior": "deny",
                            "message": reason or "Denied by user via ClaudeIsland",
                        },
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

        # No response or "ask" - let Claude Code show its normal UI
        sys.exit(0)

    elif event == "Notification":
        notification_type = data.get("notification_type")
        # Skip permission_prompt - PermissionRequest hook handles this with better info
        if notification_type == "permission_prompt":
            sys.exit(0)
        elif notification_type == "idle_prompt":
            state["status"] = "waiting_for_input"
        else:
            state["status"] = "notification"
        state["notification_type"] = notification_type
        state["message"] = data.get("message")

    elif event == "Stop":
        state["status"] = "waiting_for_input"

    elif event == "SubagentStop":
        # SubagentStop fires when a subagent completes - usually means back to waiting
        state["status"] = "waiting_for_input"

    elif event == "SessionStart":
        # New session starts waiting for user input
        state["status"] = "waiting_for_input"

    elif event == "SessionEnd":
        state["status"] = "ended"

    elif event == "PreCompact":
        # Context is being compacted (manual or auto)
        state["status"] = "compacting"

    else:
        state["status"] = "unknown"

    # Send to socket (fire and forget for non-permission events)
    send_event(state)


if __name__ == "__main__":
    main()
