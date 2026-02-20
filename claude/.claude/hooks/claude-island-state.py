#!/usr/bin/env python3
"""
Claude Island Hook
- Sends session state to ClaudeIsland.app via Unix socket
- For PermissionRequest: waits for user decision from the app
"""
import json
import os
import socket
import sys

SOCKET_PATH = "/tmp/claude-island.sock"
TIMEOUT_SECONDS = 300  # 5 minutes for permission decisions
NATS_HOST = "localhost"
NATS_PORT = 4222
NATS_SUBJECT_STATE = "claude.island.state"
NATS_SUBJECT_PERMISSION = "claude.island.permission"


def is_remote():
    """Detect if running in a remote SSH session"""
    return bool(
        os.environ.get("SSH_CLIENT")
        or os.environ.get("SSH_TTY")
        or os.environ.get("SSH_CONNECTION")
    )


def nats_publish(subject, payload):
    """Publish a message via raw NATS protocol (no library needed)"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((NATS_HOST, NATS_PORT))
        # Read server INFO
        s.recv(4096)
        # Send CONNECT
        s.sendall(b"CONNECT {}\r\n")
        # PUB subject length\r\npayload\r\n
        data = payload.encode("utf-8")
        s.sendall(f"PUB {subject} {len(data)}\r\n".encode())
        s.sendall(data + b"\r\n")
        s.sendall(b"PING\r\n")
        s.recv(4096)  # wait for PONG to ensure delivery
        s.close()
    except Exception:
        pass


def nats_request(subject, payload, timeout=300):
    """Send a NATS request and wait for reply (raw protocol, no library needed)"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect((NATS_HOST, NATS_PORT))
        # Read server INFO
        s.recv(4096)
        # Send CONNECT
        s.sendall(b"CONNECT {}\r\n")
        # Subscribe to a unique inbox for the reply
        inbox = f"_INBOX.{os.getpid()}.{id(s)}"
        s.sendall(f"SUB {inbox} 1\r\n".encode())
        # PUB with reply-to
        data = payload.encode("utf-8")
        s.sendall(f"PUB {subject} {inbox} {len(data)}\r\n".encode())
        s.sendall(data + b"\r\n")
        s.sendall(b"PING\r\n")
        # Read until we get a MSG
        buf = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
            text = buf.decode("utf-8", errors="replace")
            if "MSG " in text:
                # Parse MSG inbox sid length\r\npayload\r\n
                lines = text.split("\r\n")
                for i, line in enumerate(lines):
                    if line.startswith("MSG "):
                        parts = line.split()
                        msg_len = int(parts[-1])
                        msg_payload = lines[i + 1][:msg_len]
                        s.close()
                        return json.loads(msg_payload)
        s.close()
    except Exception:
        pass
    return None


def get_remote_tmux_target():
    """Get tmux pane target on remote machine (only when in tmux)"""
    if not os.environ.get("TMUX"):
        return None
    import subprocess
    try:
        result = subprocess.run(
            ["tmux", "display-message", "-p",
             "#{session_name}:#{window_index}.#{pane_index}"],
            capture_output=True, text=True, timeout=2,
        )
        target = result.stdout.strip()
        if target:
            return target
    except Exception:
        pass
    return None


def get_remote_hostname():
    """Get FQDN of remote machine"""
    import subprocess
    try:
        result = subprocess.run(
            ["hostname", "-f"], capture_output=True, text=True, timeout=2,
        )
        hostname = result.stdout.strip()
        if hostname:
            return hostname
    except Exception:
        pass
    return None


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
        # Socket unavailable — fall back to NATS for remote sessions
        if is_remote():
            nats_publish(NATS_SUBJECT_STATE, json.dumps(state))
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
        state["user_prompt"] = data.get("prompt", "")

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

        # Remote: use NATS request/reply for bidirectional approve/deny
        if is_remote():
            response = nats_request(
                NATS_SUBJECT_PERMISSION, json.dumps(state)
            )
        else:
            # Local: send to app via Unix socket and wait for decision
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
        state["last_assistant_message"] = data.get("last_assistant_message", "")

    elif event == "SubagentStop":
        # SubagentStop fires when a subagent completes - usually means back to waiting
        state["status"] = "waiting_for_input"
        state["last_assistant_message"] = data.get("last_assistant_message", "")

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

    # Add remote tmux info for state events (not permissions — those exit above)
    # Bridge uses these to create proxy tmux panes for remote sessions
    if is_remote() and os.environ.get("TMUX"):
        remote_target = get_remote_tmux_target()
        remote_hostname = get_remote_hostname()
        if remote_target:
            state["remote_tmux_target"] = remote_target
        if remote_hostname:
            state["remote_hostname"] = remote_hostname

    # Send to socket (fire and forget for non-permission events)
    send_event(state)


if __name__ == "__main__":
    main()
