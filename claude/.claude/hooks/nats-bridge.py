#!/usr/bin/env python3
"""
NATS → Claude Island bridge

Subscribes to NATS subjects and forwards events to Claude Island's Unix socket.
Also writes local transcript .jsonl files for remote sessions.

Advantages over ntfy-bridge.py:
- No message rate limits
- Supports request/reply for remote PermissionRequest (approve/deny)
- Lower latency (local NATS server, no cloud relay)

Requires: pip install nats-py

Usage:
  nats-bridge.py start   # run in foreground
  nats-bridge.py stop    # stop the daemon
  nats-bridge.py status  # check if running
"""
import asyncio
import json
import os
import signal
import socket as sock
import sys
import time
import uuid as uuid_mod
from datetime import datetime, timezone

NATS_URL = "nats://localhost:4222"
SUBJECT_STATE = "claude.island.state"
SUBJECT_PERMISSION = "claude.island.permission"
SOCKET_PATH = "/tmp/claude-island.sock"
PID_FILE = "/tmp/nats-bridge.pid"
CLAUDE_PROJECTS = os.path.expanduser("~/.claude/projects")

# Track parent UUIDs per session for transcript chaining
last_uuid = {}


def cwd_to_project_dir(cwd):
    """Match Claude Island's ConversationParser.sessionFilePath() exactly"""
    return cwd.replace("/", "-").replace(".", "-")


def get_transcript_path(state):
    cwd = state.get("cwd", "/tmp")
    session_id = state.get("session_id", "unknown")
    project_dir = os.path.join(CLAUDE_PROJECTS, cwd_to_project_dir(cwd))
    os.makedirs(project_dir, exist_ok=True)
    return os.path.join(project_dir, f"{session_id}.jsonl")


def append_entry(transcript_path, entry):
    """Compact JSON — Claude Island matches 'line.contains(\"type\":\"user\")'"""
    with open(transcript_path, "a") as f:
        f.write(json.dumps(entry, separators=(",", ":")) + "\n")


def write_transcript(state, transcript_path):
    session_id = state.get("session_id", "unknown")
    cwd = state.get("cwd", "/tmp")
    event = state.get("event", "")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    wrote = False

    if event == "UserPromptSubmit":
        user_prompt = state.get("user_prompt", "") or "(remote session)"
        msg_uuid = str(uuid_mod.uuid4())
        append_entry(transcript_path, {
            "parentUuid": last_uuid.get(session_id),
            "isSidechain": False,
            "userType": "external",
            "cwd": cwd,
            "sessionId": session_id,
            "version": "remote-bridge",
            "type": "user",
            "uuid": msg_uuid,
            "timestamp": now,
            "message": {"content": user_prompt},
        })
        last_uuid[session_id] = msg_uuid
        wrote = True

    elif event == "PreToolUse":
        tool = state.get("tool", "unknown")
        tool_input = state.get("tool_input", {})
        tool_use_id = state.get("tool_use_id", str(uuid_mod.uuid4()))
        msg_uuid = str(uuid_mod.uuid4())
        append_entry(transcript_path, {
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
                "content": [{"type": "tool_use", "id": tool_use_id, "name": tool, "input": tool_input}],
            },
        })
        last_uuid[session_id] = msg_uuid
        wrote = True

    elif event in ("Stop", "SubagentStop"):
        message_text = state.get("last_assistant_message", "")
        if message_text:
            msg_uuid = str(uuid_mod.uuid4())
            append_entry(transcript_path, {
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
            })
            last_uuid[session_id] = msg_uuid
            wrote = True

    return wrote


def forward_to_island(state):
    try:
        s = sock.socket(sock.AF_UNIX, sock.SOCK_STREAM)
        s.settimeout(5)
        s.connect(SOCKET_PATH)
        s.sendall(json.dumps(state).encode())
        # For permission requests, wait for response
        if state.get("status") == "waiting_for_approval":
            response = s.recv(4096)
            s.close()
            if response:
                return json.loads(response.decode())
            return None
        s.close()
        return True
    except (sock.error, OSError, json.JSONDecodeError):
        return False


async def run_bridge():
    import nats

    print(f"nats-bridge: connecting to {NATS_URL}")
    nc = await nats.connect(NATS_URL)
    print(f"nats-bridge: subscribed to {SUBJECT_STATE}, {SUBJECT_PERMISSION}")
    print(f"nats-bridge: transcripts to {CLAUDE_PROJECTS}")

    async def handle_state(msg):
        """Handle fire-and-forget state events"""
        try:
            state = json.loads(msg.data.decode())
        except json.JSONDecodeError:
            return

        transcript_path = get_transcript_path(state)
        state["transcript_path"] = transcript_path

        wrote = write_transcript(state, transcript_path)
        if wrote:
            print(f"[{time.strftime('%H:%M:%S')}] wrote: {transcript_path}")

        result = forward_to_island(state)
        label = "forwarded" if result else "socket unavailable"
        session = state.get("session_id", "?")[:8]
        event = state.get("event", "?")
        status = state.get("status", "?")
        print(f"[{time.strftime('%H:%M:%S')}] {label}: {session} {event}={status}")

    async def handle_permission(msg):
        """Handle request/reply permission events — forward to Claude Island and reply"""
        try:
            state = json.loads(msg.data.decode())
        except json.JSONDecodeError:
            return

        transcript_path = get_transcript_path(state)
        state["transcript_path"] = transcript_path

        session = state.get("session_id", "?")[:8]
        tool = state.get("tool", "?")
        print(f"[{time.strftime('%H:%M:%S')}] permission: {session} {tool}")

        # Forward to Claude Island and wait for approve/deny
        response = forward_to_island(state)

        if isinstance(response, dict):
            reply = json.dumps(response).encode()
            print(f"[{time.strftime('%H:%M:%S')}] replied: {response.get('decision', '?')}")
        else:
            # No response from Claude Island — tell remote to fall back to terminal UI
            reply = json.dumps({"decision": "ask"}).encode()
            print(f"[{time.strftime('%H:%M:%S')}] replied: ask (fallback)")

        await msg.respond(reply)

    await nc.subscribe(SUBJECT_STATE, cb=handle_state)
    await nc.subscribe(SUBJECT_PERMISSION, cb=handle_permission)

    # Keep running
    stop = asyncio.Event()
    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)
    await stop.wait()
    await nc.close()
    print("\nnats-bridge: stopped")


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
    write_pid()
    try:
        asyncio.run(run_bridge())
    finally:
        try:
            os.unlink(PID_FILE)
        except FileNotFoundError:
            pass


def cmd_stop():
    pid = read_pid()
    if not pid or not is_running(pid):
        print("nats-bridge: not running")
        return
    os.kill(pid, signal.SIGTERM)
    print(f"nats-bridge: stopped (pid {pid})")
    try:
        os.unlink(PID_FILE)
    except FileNotFoundError:
        pass


def cmd_status():
    pid = read_pid()
    if pid and is_running(pid):
        print(f"nats-bridge: running (pid {pid})")
    else:
        print("nats-bridge: not running")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "start"
    {"start": cmd_start, "stop": cmd_stop, "status": cmd_status}.get(cmd, cmd_start)()
