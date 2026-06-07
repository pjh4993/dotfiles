#!/usr/bin/env python3
"""Wave Terminal attention signal hook for Claude Code.

Drives the current Wave block's frame border color and corner badge based on
the Claude Code hook event, so a glance at the panel shows whether Claude needs
attention. Uses the `wsh` CLI, targeting the block via the inherited
WAVETERM_BLOCKID env var (`-b this`).

No-ops silently when not running inside a Wave block or when `wsh` is missing,
so it is safe on remote/SSH/non-Wave sessions. Always exits 0 and never writes
to stdout, so it cannot interfere with the permission flow or other hooks.

Colors follow the Dracula palette to match the terminal theme.
"""

import json
import os
import shutil
import subprocess
import sys

# Dracula palette
RED = "#ff5555"     # needs permission
YELLOW = "#f1fa8c"  # wants attention / notification
GREEN = "#50fa7b"   # turn finished, your move

# event -> ("set", border_color, badge_icon, badge_color) | ("clear",)
ACTIONS = {
    "PermissionRequest": ("set", RED, "lock", RED),
    "Notification": ("set", YELLOW, "bell", YELLOW),
    "Stop": ("set", GREEN, "circle-check", GREEN),
    "PostToolUse": ("clear",),       # work resumed after approval
    "UserPromptSubmit": ("clear",),  # user is back and replied
    "SessionStart": ("clear",),
    "SessionEnd": ("clear",),
}


def find_wsh():
    wsh = shutil.which("wsh")
    if wsh:
        return wsh
    fallback = os.path.expanduser(
        "~/Library/Application Support/waveterm/bin/wsh"
    )
    return fallback if os.path.exists(fallback) else None


def run(wsh, args):
    try:
        subprocess.run(
            [wsh, *args],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
    except Exception:
        pass


def set_signal(wsh, border, icon, color):
    run(wsh, ["setmeta", "-b", "this",
              f"frame:bordercolor={border}",
              f"frame:activebordercolor={border}"])
    run(wsh, ["badge", icon, "--color", color, "-b", "this"])


def clear_signal(wsh):
    run(wsh, ["setmeta", "-b", "this",
              "frame:bordercolor=", "frame:activebordercolor="])
    run(wsh, ["badge", "--clear", "-b", "this"])


def main():
    # Only act inside a local Wave block.
    if os.environ.get("WAVETERM") != "1" or not os.environ.get("WAVETERM_BLOCKID"):
        return
    wsh = find_wsh()
    if not wsh:
        return

    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}

    event = data.get("hook_event_name", "")
    action = ACTIONS.get(event)
    if not action:
        return

    if action[0] == "set":
        _, border, icon, color = action
        set_signal(wsh, border, icon, color)
    else:
        clear_signal(wsh)


if __name__ == "__main__":
    try:
        main()
    finally:
        sys.exit(0)
