#!/usr/bin/env python3
"""Kitten: a small menu to spin up a new kitty session.

Bound to `cmd+j o`. Two choices:

  1  project   4 tabs (nvim/claude stacked, server/shell grid) in a directory
  2  scratch   one tab in ~

A project prompts for a directory and its session file is written to
~/.local/state/kitty/sessions/<name>.kitty-session, next to the ones seeded by
install.sh — so it persists, can be re-opened, and cmd+shift+s saves over it. An
existing file for that name is reused rather than clobbered. A scratch session is
written to a temp file and thrown away once loaded.
"""
from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import termios
import traceback
import tty
from typing import Any

try:
    from kittens.tui.handler import kitten_ui
except Exception:  # pragma: no cover - only absent outside kitty
    kitten_ui = None

LOG_PATH = "/tmp/kitty-new-session.log"
HOME = os.path.expanduser("~")
STATE_DIR = os.path.join(HOME, ".local/state/kitty/sessions")
DEFAULT_BASE = HOME + os.sep

# menu key -> kind
MENU = {
    "1": "project",
    "2": "scratch",
}


def sanitize(name: str) -> str:
    """A safe session-file name: keep [A-Za-z0-9_-], collapse the rest to -."""
    out = re.sub(r"[^A-Za-z0-9_-]+", "-", name.strip()).strip("-")
    return out


def expand(path: str) -> str:
    return os.path.abspath(os.path.expanduser(os.path.expandvars(path.strip())))


def complete(path: str) -> str:
    """Best-effort tab completion against the local filesystem (dirs only)."""
    raw = os.path.expanduser(os.path.expandvars(path))
    directory, prefix = os.path.split(raw)
    directory = directory or "."
    try:
        entries = [
            e for e in os.listdir(directory)
            if e.startswith(prefix) and os.path.isdir(os.path.join(directory, e))
        ]
    except OSError:
        return path
    if not entries:
        return path
    if len(entries) == 1:
        return os.path.join(os.path.split(path)[0], entries[0]) + os.sep
    common = os.path.commonprefix(entries)
    if len(common) > len(prefix):
        return os.path.join(os.path.split(path)[0], common)
    return path


def menu() -> str | None:
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    try:
        while True:
            sys.stdout.write("\x1b[2J\x1b[H")
            sys.stdout.write("New session\r\n\r\n")
            sys.stdout.write("  1  project    nvim / claude / server / shell in a folder (saved)\r\n")
            sys.stdout.write("  2  scratch    one tab in ~ (throwaway)\r\n\r\n")
            sys.stdout.write("  1-2 select   Esc cancel\r\n")
            sys.stdout.flush()
            ch = sys.stdin.read(1)
            if ch in MENU:
                return MENU[ch]
            if ch in ("\x1b", "q", "\x03"):  # esc, q, ctrl-c
                return None
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        sys.stdout.write("\x1b[2J\x1b[H")
        sys.stdout.flush()


def prompt_line(title: str, base: str, allow_complete: bool) -> str | None:
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    buf = base
    try:
        while True:
            sys.stdout.write("\x1b[2J\x1b[H")
            sys.stdout.write(title + "\r\n")
            hint = "Tab complete, " if allow_complete else ""
            sys.stdout.write(f"({hint}Enter to confirm, Esc to cancel):\r\n\r\n")
            sys.stdout.write("  " + buf)
            sys.stdout.flush()
            ch = sys.stdin.read(1)
            if ch in ("\r", "\n"):
                return buf.strip() or None
            if ch in ("\x1b", "\x03"):  # esc, ctrl-c
                return None
            if ch == "\t":
                if allow_complete:
                    buf = complete(buf)
            elif ch in ("\x7f", "\b"):
                buf = buf[:-1]
            elif ch == "\x15":  # ctrl-u: clear
                buf = ""
            elif ch.isprintable():
                buf += ch
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        sys.stdout.write("\x1b[2J\x1b[H")
        sys.stdout.flush()


def show_error(msg: str) -> None:
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    try:
        sys.stdout.write("\x1b[2J\x1b[H")
        sys.stdout.write(msg + "\r\n\r\nPress any key to close.")
        sys.stdout.flush()
        sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        sys.stdout.write("\x1b[2J\x1b[H")
        sys.stdout.flush()


# ---- session-file builders --------------------------------------------------

def project_text(directory: str) -> str:
    # Same shape as the checked-in templates (kitty/sessions/*.kitty-session):
    # editor and claude stacked, server and shell in a grid. --hold keeps the
    # pane as a shell when the program exits. Tab titles are left dynamic so the
    # running program names them.
    tabs = [
        ("stack", "--hold nvim ."),
        ("stack", "--hold claude"),
        ("grid", ""),
        ("grid", ""),
    ]
    out = []
    for i, (layout, cmd) in enumerate(tabs):
        out.append("new_tab")
        out.append(f"layout {layout}")
        out.append(f"cd {directory}")
        out.append(("launch " + cmd).rstrip())
        if i == 0:
            out.append("focus")
        out.append("")
    return "\n".join(out)


def scratch_text(name: str) -> str:
    return f"new_tab {name}\ncd {HOME}\n\nlaunch\nfocus\n"


# ---- file writers -----------------------------------------------------------

def write_temp(name: str, text: str) -> str:
    d = tempfile.mkdtemp(prefix="kitty-session-")
    path = os.path.join(d, f"{name}.kitty-session")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


def write_state(name: str, text: str) -> str:
    """Persistent session file. If one already exists for this name, keep it
    (reopen the existing session) rather than clobbering it."""
    os.makedirs(STATE_DIR, exist_ok=True)
    path = os.path.join(STATE_DIR, f"{name}.kitty-session")
    if not os.path.exists(path):
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
    return path


# ---- orchestration ----------------------------------------------------------

def main_impl(args: list[str]) -> str:
    kind = menu()
    if not kind:
        return json.dumps({})

    if kind == "project":
        raw = prompt_line("New project directory", DEFAULT_BASE, allow_complete=True)
        if not raw:
            return json.dumps({})
        directory = expand(raw)
        if not os.path.isdir(directory):
            show_error(f"Not a directory: {directory}")
            return json.dumps({})
        name = sanitize(os.path.basename(directory.rstrip(os.sep))) or "session"
        # Persisted, so the session survives a kitty restart and cmd+shift+s has
        # a file to save over.
        path = write_state(name, project_text(directory))
        return json.dumps({"action": "goto_session", "path": path, "cleanup": False})

    # kind == "scratch": ephemeral, nothing to keep on disk.
    raw = prompt_line("New scratch session name", "", allow_complete=False)
    name = sanitize(raw or "")
    if not name:
        return json.dumps({})
    path = write_temp(name, scratch_text(name))
    return json.dumps({"action": "goto_session", "path": path, "cleanup": True})


def cli_main(args: list[str]) -> str:
    try:
        return main_impl(args)
    except Exception:
        with open(LOG_PATH, "a", encoding="utf-8") as log:
            log.write("\n--- new_session crash ---\n")
            traceback.print_exc(file=log)
        raise


if kitten_ui is None:
    main = cli_main
else:
    main = kitten_ui(allow_remote_control=True)(cli_main)


def handle_result(args: list[str], answer: str, target_window_id: int, boss: Any) -> None:
    try:
        payload = json.loads(answer or "{}")
    except json.JSONDecodeError:
        return
    if payload.get("action") != "goto_session":
        return
    target = boss.window_id_map.get(target_window_id)
    if target is not None:
        boss.call_remote_control(target, ("action", "goto_session", payload["path"]))
    # goto_session loads synchronously; a local (temp) session can now be removed.
    if payload.get("cleanup"):
        import shutil

        shutil.rmtree(os.path.dirname(payload["path"]), ignore_errors=True)
