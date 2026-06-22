#!/usr/bin/env python3
"""Claude Code hook -> per-session state for the kitty agent panel.

Registered for several lifecycle events in ~/.claude/settings.json; dispatches on
`hook_event_name` (a single script handles them all). On each event it merges a
small per-session record into ~/.claude/agent-panel/state/<session_id>.json. The
panel reads these files on a short poll, so the hook just has to keep them
current — no IPC/signalling needed.

Design notes:
- Writes are atomic (tmp file + os.replace) so the panel always reads a complete
  file. A per-session lock guards against concurrent hooks (parallel tool calls
  fire multiple PreToolUse hooks at once for the same session).
- This must never break the user's session: everything is wrapped so the hook
  always exits 0.
"""
from __future__ import annotations

import fcntl
import json
import os
import sys
import time

HOME = os.path.expanduser("~")
BASE = os.path.join(HOME, ".claude", "agent-panel")
STATE_DIR = os.path.join(BASE, "state")


def read_stdin_json() -> dict:
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def state_path(session_id: str) -> str:
    safe = session_id.replace("/", "_")
    return os.path.join(STATE_DIR, safe + ".json")


def load_record(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            txt = f.read()
        return json.loads(txt) if txt.strip() else {}
    except Exception:
        return {}


def write_record(path: str, rec: dict) -> None:
    tmp = "{}.tmp.{}".format(path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(rec, f)
    os.replace(tmp, path)


def git_branch(cwd: str) -> str:
    if not cwd:
        return ""
    try:
        with open(os.path.join(cwd, ".git", "HEAD"), "r", encoding="utf-8") as f:
            ref = f.read().strip()
        if ref.startswith("ref:"):
            return ref.split("/", 2)[-1]
        return ref[:7]
    except Exception:
        return ""


def base_name(p: str) -> str:
    return os.path.basename(p) if p else ""


def activity_from_tool(tool_name: str, tool_input: dict) -> str:
    ti = tool_input or {}
    if tool_name in ("Edit", "MultiEdit"):
        return "Editing " + base_name(ti.get("file_path", ""))
    if tool_name == "Write":
        return "Writing " + base_name(ti.get("file_path", ""))
    if tool_name == "Read":
        return "Reading " + base_name(ti.get("file_path", ""))
    if tool_name == "NotebookEdit":
        return "Editing " + base_name(ti.get("notebook_path", ""))
    if tool_name == "Bash":
        cmd = (ti.get("command", "") or "").strip().splitlines()
        return "Running " + (cmd[0][:48] if cmd else "command")
    if tool_name == "Grep":
        return "Searching " + str(ti.get("pattern", ""))[:32]
    if tool_name == "Glob":
        return "Finding " + str(ti.get("pattern", ""))[:32]
    if tool_name == "Task":
        return "Task: " + str(ti.get("description", ""))[:32]
    if tool_name in ("WebFetch", "WebSearch"):
        return tool_name
    if tool_name == "TodoWrite":
        return "Updating todos"
    if tool_name and tool_name.startswith("mcp__"):
        return tool_name.split("__")[-1][:32]
    return (tool_name or "Working") + "…"


def apply_event(rec: dict, data: dict, now: float) -> str:
    """Mutate rec for this event. Return 'delete' to remove the state file."""
    event = data.get("hook_event_name", "")
    cwd = data.get("cwd") or rec.get("cwd") or ""

    rec.setdefault("session_id", data.get("session_id", ""))
    if data.get("transcript_path"):
        rec["transcript_path"] = data["transcript_path"]
    rec["cwd"] = cwd
    wid = os.environ.get("KITTY_WINDOW_ID")
    if wid:
        try:
            rec["kitty_window_id"] = int(wid)
        except ValueError:
            pass
    rec["updated_at"] = now

    if event == "SessionStart":
        rec.setdefault("started_at", now)
        rec["git_branch"] = git_branch(cwd)
        if data.get("model"):
            rec["model"] = data["model"]
        rec.setdefault("state", "idle")
        rec.setdefault("activity", "")
        rec.setdefault("todos", [])
    elif event == "UserPromptSubmit":
        rec["state"] = "working"
        rec["started_at"] = now
        rec["activity"] = "Thinking…"
        if not rec.get("git_branch"):
            rec["git_branch"] = git_branch(cwd)
    elif event == "PreToolUse":
        rec["state"] = "working"
        rec["activity"] = activity_from_tool(
            data.get("tool_name", ""), data.get("tool_input") or {}
        )
    elif event == "PostToolUse":
        if data.get("tool_name") == "TodoWrite":
            todos = (data.get("tool_input") or {}).get("todos") or []
            rec["todos"] = todos
    elif event == "Notification":
        rec["state"] = "needs-input"
        msg = (data.get("message") or "").strip()
        rec["activity"] = msg[:60] if msg else "Needs your input"
    elif event == "Stop":
        rec["state"] = "idle"
        rec["activity"] = ""
    elif event == "SessionEnd":
        return "delete"
    return "keep"


def main() -> None:
    data = read_stdin_json()
    session_id = data.get("session_id") or ""
    if not session_id:
        return
    os.makedirs(STATE_DIR, exist_ok=True)
    path = state_path(session_id)
    lock_path = path + ".lock"

    action = "keep"
    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        rec = load_record(path)
        action = apply_event(rec, data, time.time())
        if action == "delete":
            for p in (path, path + ".tmp.{}".format(os.getpid())):
                try:
                    os.remove(p)
                except OSError:
                    pass
        else:
            write_record(path, rec)
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except OSError:
            pass
        os.close(lock_fd)

    if action == "delete":
        try:
            os.remove(lock_path)
        except OSError:
            pass


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
