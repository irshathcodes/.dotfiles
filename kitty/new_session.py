#!/usr/bin/env python3
"""Kitten: a small menu to spin up a new session, local or on moideen.

Bound to `cmd+j o`. Four choices:

  1  local project    4 tabs (nvim/claude stacked, server/shell grid) in a dir
  2  moideen project  same, but remote via remote-attach.sh (persistent)
  3  local scratch     one tab in ~
  4  moideen scratch   one remote tab in ~ (persistent)

Project entries prompt for a directory; scratch entries prompt for a session
name. Local sessions are written to a temp file (ephemeral). Remote sessions
are written to ~/.local/state/kittymux/<name>.kitty-session so they persist and
show up in the `cmd+j /` picker, exactly like the registered projects. The zmx
session is kept alive server-side regardless, so reopening reattaches.
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
STATE_DIR = os.path.join(HOME, ".local/state/kittymux")
RA = os.path.join(HOME, ".config/kitty/remote-attach.sh")
DEFAULT_BASE = HOME + os.sep

# menu key -> (location, kind)
MENU = {
    "1": ("local", "project"),
    "2": ("remote", "project"),
    "3": ("local", "scratch"),
    "4": ("remote", "scratch"),
}


def sanitize(name: str) -> str:
    """A safe session/zmx identifier: keep [A-Za-z0-9_-], collapse the rest to -."""
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


def menu() -> tuple[str, str] | None:
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    try:
        while True:
            sys.stdout.write("\x1b[2J\x1b[H")
            sys.stdout.write("New session\r\n\r\n")
            sys.stdout.write("  1  local project     nvim / claude / server / shell in a folder\r\n")
            sys.stdout.write("  2  moideen project   same, on moideen (persistent)\r\n")
            sys.stdout.write("  3  local scratch      one tab in ~\r\n")
            sys.stdout.write("  4  moideen scratch    one tab in ~ on moideen (persistent)\r\n\r\n")
            sys.stdout.write("  1-4 select   Esc cancel\r\n")
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

def local_project_text(directory: str) -> str:
    # local mirrors the old cmd+j o template (no auto-claude, which may be a
    # shell alias rather than a binary here). Layout: 1&2 stack, 3&4 grid.
    tabs = [
        ("nvim", "stack", "nvim ."),
        ("shell", "stack", ""),
        ("server", "grid", ""),
        ("shell", "grid", ""),
    ]
    out = []
    for i, (title, layout, cmd) in enumerate(tabs):
        out.append(f"new_tab {title}")
        out.append(f"layout {layout}")
        out.append(f"cd {directory}")
        out.append("")
        out.append(("launch " + cmd).rstrip())
        if i == 0:
            out.append("focus")
        out.append("")
    return "\n".join(out)


def remote_project_text(base: str, path: str) -> str:
    # path is passed literally to remote-attach.sh (kitty does not tilde-expand
    # launch ARGS), so ~ is resolved server-side by cs. cs_cwd carries it so a
    # kittymux save round-trips the dir.
    tabs = [("edit", "stack"), ("cc", "stack"), ("srv", "grid"), ("sh", "grid")]
    out = []
    for i, (nm, layout) in enumerate(tabs):
        out.append("new_tab")
        out.append(f"layout {layout}")
        out.append(
            f"launch --var=cs_session={base}.{nm} --var=cs_project={base} "
            f"--var=cs_cwd={path} {RA} {base} {nm} {path}"
        )
        if i == 0:
            out.append("focus")
        out.append("")
    return "\n".join(out)


def local_scratch_text(name: str) -> str:
    return f"new_tab {name}\ncd {HOME}\n\nlaunch\nfocus\n"


def remote_scratch_text(name: str) -> str:
    # ~ passed literally -> cs expands to the server home.
    return (
        f"new_tab\n"
        f"launch --var=cs_session={name}.sh --var=cs_project={name} "
        f"--var=cs_cwd=~ {RA} {name} sh ~\n"
        f"focus\n"
    )


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
    choice = menu()
    if not choice:
        return json.dumps({})
    loc, kind = choice

    if kind == "project":
        where = " on moideen" if loc == "remote" else ""
        # local: prefill the Mac home and offer FS completion; remote: prefill
        # ~/ (a server-relative path, expanded on moideen by cs), no completion.
        base = DEFAULT_BASE if loc == "local" else "~/"
        raw = prompt_line(f"New project directory{where}", base, allow_complete=(loc == "local"))
        if not raw:
            return json.dumps({})
        if loc == "local":
            directory = expand(raw)
            if not os.path.isdir(directory):
                show_error(f"Not a directory: {directory}")
                return json.dumps({})
            name = os.path.basename(directory.rstrip(os.sep)) or "session"
            path = write_temp(name, local_project_text(directory))
            return json.dumps({"action": "goto_session", "path": path, "cleanup": True})
        # remote
        base = sanitize(os.path.basename(raw.strip().rstrip("/"))) or "session"
        path = write_state(base, remote_project_text(base, raw.strip()))
        return json.dumps({"action": "goto_session", "path": path, "cleanup": False})

    # kind == "scratch"
    where = " on moideen" if loc == "remote" else ""
    raw = prompt_line(f"New scratch session name{where}", "", allow_complete=False)
    name = sanitize(raw or "")
    if not name:
        return json.dumps({})
    if loc == "local":
        path = write_temp(name, local_scratch_text(name))
        return json.dumps({"action": "goto_session", "path": path, "cleanup": True})
    path = write_state(name, remote_scratch_text(name))
    return json.dumps({"action": "goto_session", "path": path, "cleanup": False})


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
