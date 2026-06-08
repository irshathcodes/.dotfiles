#!/usr/bin/env python3
"""Kitten: prompt for a directory, then spin up the usual 4-tab session.

The trailing folder name of the chosen directory becomes the session name.
Layout mirrors the hand-written sessions in sessions/*.kitty-session:
    tab 1: "nvim"   -> opens `nvim .`
    tab 2: (blank)  -> shell
    tab 3: "server" -> shell
    tab 4: (blank)  -> shell
"""
from __future__ import annotations

import json
import os
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
DEFAULT_BASE = os.path.expanduser("~/")


def expand(path: str) -> str:
    return os.path.abspath(os.path.expanduser(os.path.expandvars(path.strip())))


def complete(path: str) -> str:
    """Best-effort tab completion against the filesystem (dirs only)."""
    raw = os.path.expanduser(os.path.expandvars(path))
    directory, prefix = os.path.split(raw)
    directory = directory or "."
    try:
        entries = [
            e
            for e in os.listdir(directory)
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


def prompt_directory() -> str | None:
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    buf = DEFAULT_BASE
    try:
        while True:
            sys.stdout.write("\x1b[2J\x1b[H")
            sys.stdout.write("New kitty session\r\n")
            sys.stdout.write("Directory (Tab to complete, Enter to confirm, Esc to cancel):\r\n\r\n")
            sys.stdout.write("  " + buf)
            sys.stdout.flush()
            ch = sys.stdin.read(1)
            if ch in ("\r", "\n"):
                return buf.strip() or None
            if ch == "\x1b":  # esc
                return None
            if ch == "\t":
                buf = complete(buf)
            elif ch in ("\x7f", "\b"):
                buf = buf[:-1]
            elif ch == "\x15":  # ctrl-u
                buf = ""
            elif ch == "\x17":  # ctrl-w
                buf = buf.rstrip()
                buf = buf[: buf.rstrip(os.sep).rfind(os.sep) + 1] if os.sep in buf else ""
            elif ch.isprintable():
                buf += ch
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        sys.stdout.write("\x1b[2J\x1b[H")
        sys.stdout.flush()


def session_text(name: str, directory: str) -> str:
    def tab(title: str, win_id: int, extra: str = "") -> str:
        header = f"new_tab {title}" if title else "new_tab"
        data = {"id": win_id}
        if extra:
            data["cmd_at_shell_startup"] = extra
        return (
            f"{header}\n"
            f"layout fat\n"
            f"cd {directory}\n\n"
            f"launch 'kitty-unserialize-data={json.dumps(data)}'\n"
            f"focus\n"
        )

    parts = [
        tab("nvim", 1, "nvim ."),
        tab("", 2),
        tab("server", 3),
        tab("", 4),
    ]
    return "\n".join(parts) + "\nfocus_tab 0\n"


def main_impl(args: list[str]) -> str:
    directory = prompt_directory()
    if not directory:
        return json.dumps({})
    directory = expand(directory)
    if not os.path.isdir(directory):
        return json.dumps({"error": f"Not a directory: {directory}"})
    name = os.path.basename(directory.rstrip(os.sep)) or "session"
    tmpdir = tempfile.mkdtemp(prefix="kitty-session-")
    path = os.path.join(tmpdir, f"{name}.kitty-session")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(session_text(name, directory))
    return json.dumps({"action": "goto_session", "path": path})


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
    if payload.get("action") == "goto_session":
        target = boss.window_id_map.get(target_window_id)
        if target is not None:
            boss.call_remote_control(target, ("action", "goto_session", payload["path"]))
        # session is loaded synchronously above; clean up the temp file/dir
        import shutil

        shutil.rmtree(os.path.dirname(payload["path"]), ignore_errors=True)
