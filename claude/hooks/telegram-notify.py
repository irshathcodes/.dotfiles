#!/usr/bin/env python3
"""Claude Code hook -> Telegram push notifications.

Purpose: make notifications work from remote/SSH sessions (e.g. running Claude
Code on `moideen`) where terminal-native notifications (kitty/iTerm2) can't reach
the local machine. Instead of writing terminal escape codes, this pushes a
message via the Telegram Bot API, which lands on every device signed into
Telegram (Mac desktop app + phone), with no binary required on the remote host.

Registered in settings.json for three events; dispatch on `hook_event_name`:
  - UserPromptSubmit : record the turn start time (feeds the Stop threshold)
  - Stop             : notify only if the turn ran >= STOP_THRESHOLD_S (avoids
                       spamming on quick back-and-forth turns)
  - Notification     : always notify (Claude needs input / a permission decision)

Secrets are read from the environment (TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID),
falling back to parsing ~/.dotfiles/.env directly (the .env is gitignored, so it
must exist on whichever host runs Claude Code -- including moideen).

This must never break the user's session: everything is wrapped and it always
exits 0.
"""
from __future__ import annotations

import html
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

# Only notify on Stop if the turn took at least this long (seconds). Keeps quick
# interactive turns from buzzing every device while still flagging long runs.
STOP_THRESHOLD_S = 30

# Where per-session turn-start timestamps are stashed (written on UserPromptSubmit,
# read + removed on Stop).
STATE_DIR = Path(os.environ.get("TMPDIR", "/tmp"))


def load_creds():
    """Return (token, chat_id) from env, falling back to ~/.dotfiles/.env."""
    tok = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat = os.environ.get("TELEGRAM_CHAT_ID")
    if tok and chat:
        return tok, chat
    envf = Path.home() / ".dotfiles" / ".env"
    try:
        for raw in envf.read_text().splitlines():
            line = raw.strip()
            if line.startswith("export "):
                line = line[len("export "):]
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            if key == "TELEGRAM_BOT_TOKEN" and not tok:
                tok = val
            elif key == "TELEGRAM_CHAT_ID" and not chat:
                chat = val
    except OSError:
        pass
    return tok, chat


def send(text):
    tok, chat = load_creds()
    if not tok or not chat:
        return
    data = urllib.parse.urlencode(
        {
            "chat_id": chat,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": "true",
        }
    ).encode()
    url = f"https://api.telegram.org/bot{tok}/sendMessage"
    try:
        urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=10)
    except Exception:
        pass


def start_file(session_id):
    safe = "".join(c for c in (session_id or "unknown") if c.isalnum() or c in "-_")
    return STATE_DIR / f"claude-turn-start-{safe}"


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return

    event = payload.get("hook_event_name", "")
    session_id = payload.get("session_id", "")
    cwd = payload.get("cwd") or os.getcwd()
    project = html.escape(os.path.basename(cwd.rstrip("/")) or cwd)
    host = html.escape(os.environ.get("CLAUDE_NOTIFY_HOST", os.uname().nodename.split(".")[0]))

    if event == "UserPromptSubmit":
        try:
            start_file(session_id).write_text(str(time.time()))
        except OSError:
            pass
        return

    if event == "Stop":
        elapsed = None
        sf = start_file(session_id)
        try:
            if sf.exists():
                elapsed = time.time() - float(sf.read_text().strip())
                sf.unlink()
        except (OSError, ValueError):
            elapsed = None
        if elapsed is not None and elapsed < STOP_THRESHOLD_S:
            return
        dur = f" ({int(elapsed)}s)" if elapsed is not None else ""
        send(f"✅ <b>Claude finished</b>{dur}\n\U0001f4c1 {project} · {host}")
        return

    if event == "Notification":
        msg = html.escape(payload.get("message", "Claude needs your attention"))
        send(f"\U0001f514 <b>Claude needs you</b>\n{msg}\n\U0001f4c1 {project} · {host}")
        return


if __name__ == "__main__":
    main()
