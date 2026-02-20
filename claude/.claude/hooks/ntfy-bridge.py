#!/usr/bin/env python3
"""
ntfy.sh → Claude Island bridge

Subscribes to a ntfy.sh topic via SSE and forwards events to Claude Island's
Unix socket. This lets remote SSH sessions appear in Claude Island's UI.

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

NTFY_TOPIC = "pyler-claude-cozhqjel"
NTFY_URL = f"https://ntfy.sh/{NTFY_TOPIC}/json"
SOCKET_PATH = "/tmp/claude-island.sock"
PID_FILE = "/tmp/ntfy-bridge.pid"


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

                    body = msg.get("message", "")
                    title = msg.get("title", "")
                    tags = msg.get("tags", [])

                    # Parse hostname and project from title "[hostname] project"
                    hostname = ""
                    project = title
                    if title.startswith("["):
                        end = title.find("]")
                        if end > 0:
                            hostname = title[1:end]
                            project = title[end + 1:].strip()

                    # Reconstruct state for Claude Island
                    state = {
                        "session_id": f"remote-{hostname}",
                        "cwd": f"ssh://{hostname}/{project}" if hostname else project,
                        "pid": 0,
                        "tty": f"remote:{hostname}",
                        "remote": True,
                        "hostname": hostname,
                    }

                    # Map back from ntfy tags/message to status
                    if "warning" in tags:
                        state["event"] = "PermissionRequest"
                        state["status"] = "waiting_for_approval"
                        state["tool"] = body.replace("Permission needed: ", "")
                    elif "white_check_mark" in tags:
                        state["event"] = "Stop"
                        state["status"] = "waiting_for_input"
                    else:
                        state["event"] = "Notification"
                        state["status"] = "processing"
                        state["message"] = body

                    forwarded = forward_to_island(state)
                    status = "forwarded" if forwarded else "socket unavailable"
                    print(f"[{time.strftime('%H:%M:%S')}] {status}: {title} — {body}")

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
