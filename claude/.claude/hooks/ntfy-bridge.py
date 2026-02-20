#!/usr/bin/env python3
"""
ntfy.sh → Claude Island bridge

Subscribes to a ntfy.sh topic via SSE and forwards events to Claude Island's
Unix socket. This lets remote SSH sessions appear in Claude Island's UI.

Also writes local transcript files for remote sessions so Claude Island
can display message content.

Usage:
  ntfy-bridge.py start   # run in foreground
  ntfy-bridge.py daemon  # run as background daemon
  ntfy-bridge.py stop    # stop the daemon
  ntfy-bridge.py status  # check if running
"""
import json
import os
import signal
import socket
import sys
import time
import urllib.request
import uuid
from datetime import datetime, timezone

NTFY_TOPIC = "pyler-claude-cozhqjel"
NTFY_URL = f"https://ntfy.sh/{NTFY_TOPIC}/json"
SOCKET_PATH = "/tmp/claude-island.sock"
PID_FILE = "/tmp/ntfy-bridge.pid"
CLAUDE_PROJECTS = os.path.expanduser("~/.claude/projects")

# Track parent UUIDs per session for transcript chaining
last_uuid = {}


def cwd_to_project_dir(cwd):
    """Convert a remote cwd like /home/pyler/project to Claude's project dir name.
    Must match Claude Island's ConversationParser.sessionFilePath() exactly:
    cwd.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
    """
    return cwd.replace("/", "-").replace(".", "-")


def get_transcript_path(state):
    """Get the local transcript path for a remote session"""
    cwd = state.get("cwd", "/tmp")
    session_id = state.get("session_id", "unknown")
    project_dir_name = cwd_to_project_dir(cwd)
    project_dir = os.path.join(CLAUDE_PROJECTS, project_dir_name)
    os.makedirs(project_dir, exist_ok=True)
    return os.path.join(project_dir, f"{session_id}.jsonl")


def append_entry(transcript_path, entry):
    """Append a JSONL entry to the transcript file.
    Must use compact JSON (no spaces) because Claude Island's parser
    matches lines with line.contains('"type":"user"') — no space after colon.
    """
    with open(transcript_path, "a") as f:
        f.write(json.dumps(entry, separators=(",", ":")) + "\n")


def write_transcript(state, transcript_path):
    """Write transcript entries based on event type.
    Returns True if something was written."""
    session_id = state.get("session_id", "unknown")
    cwd = state.get("cwd", "/tmp")
    event = state.get("event", "")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    wrote = False

    if event == "UserPromptSubmit":
        # Write the actual user prompt
        user_prompt = state.get("user_prompt", "") or "(remote session)"
        msg_uuid = str(uuid.uuid4())
        entry = {
            "parentUuid": last_uuid.get(session_id),
            "isSidechain": False,
            "userType": "external",
            "cwd": cwd,
            "sessionId": session_id,
            "version": "remote-bridge",
            "type": "user",
            "uuid": msg_uuid,
            "timestamp": now,
            "message": {
                "content": user_prompt,
            },
        }
        append_entry(transcript_path, entry)
        last_uuid[session_id] = msg_uuid
        wrote = True

    elif event == "PreToolUse":
        # Write a tool_use entry
        tool = state.get("tool", "unknown")
        tool_input = state.get("tool_input", {})
        tool_use_id = state.get("tool_use_id", str(uuid.uuid4()))
        msg_uuid = str(uuid.uuid4())
        entry = {
            "parentUuid": last_uuid.get(session_id),
            "isSidechain": False,
            "userType": "external",
            "cwd": cwd,
            "sessionId": session_id,
            "version": "remote-bridge",
            "type": "assistant",
            "uuid": msg_uuid,
            "timestamp": now,
            "message": {
                "type": "message",
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "id": tool_use_id,
                        "name": tool,
                        "input": tool_input,
                    }
                ],
            },
        }
        append_entry(transcript_path, entry)
        last_uuid[session_id] = msg_uuid
        wrote = True

    elif event in ("Stop", "SubagentStop"):
        # Write assistant message if present
        message_text = state.get("last_assistant_message", "")
        if message_text:
            msg_uuid = str(uuid.uuid4())
            entry = {
                "parentUuid": last_uuid.get(session_id),
                "isSidechain": False,
                "userType": "external",
                "cwd": cwd,
                "sessionId": session_id,
                "version": "remote-bridge",
                "type": "assistant",
                "uuid": msg_uuid,
                "timestamp": now,
                "message": {
                    "type": "message",
                    "role": "assistant",
                    "content": [{"type": "text", "text": message_text}],
                },
            }
            append_entry(transcript_path, entry)
            last_uuid[session_id] = msg_uuid
            wrote = True

    return wrote


def forward_to_island(state):
    """Forward a state dict to Claude Island's Unix socket"""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())
        sock.close()
        return True
    except (socket.error, OSError):
        return False


def subscribe():
    """Subscribe to ntfy.sh and forward events to Claude Island"""
    while True:
        try:
            req = urllib.request.Request(NTFY_URL)
            with urllib.request.urlopen(req, timeout=90) as resp:
                for line in resp:
                    line = line.decode("utf-8").strip()
                    if not line:
                        continue
                    try:
                        msg = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    if msg.get("event") != "message":
                        continue

                    tags = msg.get("tags", [])

                    # Only process bridge messages (from claude-island-state.py)
                    # Skip human-readable messages from notify.sh
                    if "bridge" not in tags:
                        continue

                    # Body is the full JSON state — forward directly
                    body = msg.get("message", "")
                    try:
                        state = json.loads(body)
                    except json.JSONDecodeError:
                        print(f"[{time.strftime('%H:%M:%S')}] invalid JSON: {body[:100]}")
                        continue

                    # Set local transcript path for Claude Island
                    transcript_path = get_transcript_path(state)
                    state["transcript_path"] = transcript_path

                    # Write transcript entries BEFORE forwarding to socket
                    # (Claude Island re-reads the file when it receives socket events)
                    wrote = write_transcript(state, transcript_path)
                    if wrote:
                        print(f"[{time.strftime('%H:%M:%S')}] wrote: {transcript_path}")

                    forwarded = forward_to_island(state)
                    label = "forwarded" if forwarded else "socket unavailable"
                    session = state.get("session_id", "?")
                    status = state.get("status", "?")
                    event = state.get("event", "?")
                    print(f"[{time.strftime('%H:%M:%S')}] {label}: {session} {event}={status}")

        except Exception as e:
            print(f"[{time.strftime('%H:%M:%S')}] Connection lost: {e}, reconnecting...")
            time.sleep(5)


def write_pid():
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))


def read_pid():
    try:
        with open(PID_FILE) as f:
            return int(f.read().strip())
    except (FileNotFoundError, ValueError):
        return None


def is_running(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def cmd_start():
    print(f"ntfy-bridge: subscribing to ntfy.sh/{NTFY_TOPIC}")
    print(f"ntfy-bridge: forwarding to {SOCKET_PATH}")
    print(f"ntfy-bridge: transcripts to {CLAUDE_PROJECTS}")
    write_pid()
    try:
        subscribe()
    except KeyboardInterrupt:
        print("\nntfy-bridge: stopped")
    finally:
        try:
            os.unlink(PID_FILE)
        except FileNotFoundError:
            pass


def cmd_daemon():
    pid = read_pid()
    if pid and is_running(pid):
        print(f"ntfy-bridge: already running (pid {pid})")
        return

    child = os.fork()
    if child > 0:
        print(f"ntfy-bridge: started daemon (pid {child})")
        return

    # Detach from terminal
    os.setsid()
    sys.stdin = open(os.devnull)
    log = open("/tmp/ntfy-bridge.log", "a")
    sys.stdout = log
    sys.stderr = log

    write_pid()
    try:
        subscribe()
    finally:
        try:
            os.unlink(PID_FILE)
        except FileNotFoundError:
            pass


def cmd_stop():
    pid = read_pid()
    if not pid or not is_running(pid):
        print("ntfy-bridge: not running")
        return
    os.kill(pid, signal.SIGTERM)
    print(f"ntfy-bridge: stopped (pid {pid})")
    try:
        os.unlink(PID_FILE)
    except FileNotFoundError:
        pass


def cmd_status():
    pid = read_pid()
    if pid and is_running(pid):
        print(f"ntfy-bridge: running (pid {pid})")
    else:
        print("ntfy-bridge: not running")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "start"
    {"start": cmd_start, "daemon": cmd_daemon, "stop": cmd_stop, "status": cmd_status}.get(
        cmd, cmd_start
    )()
