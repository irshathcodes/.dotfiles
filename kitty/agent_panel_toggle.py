#!/usr/bin/env python3
"""Toggle the Claude agent panel as an overlay over the active window.

Bound in kitty.conf via:

    map kitty_mod+a kitten ~/.dotfiles/kitty/agent_panel_toggle.py

This is a "no UI" kitten: `handle_result` runs *inside* the kitty process with
full access to the `boss`, so the toggle itself is instant — no helper window,
no flash, and no remote-control socket round-trip just to decide what to do.

Behaviour (toggle, scoped to the ACTIVE TAB):
  - a panel is open in the active tab (window with user var agent_panel=1)
    -> close it;
  - otherwise -> close any stray panels elsewhere in this OS-window, then launch
    the panel as an overlay over the active window.

Why active-tab scoping: an overlay is tied to one window in one tab. If we
searched the whole OS-window, pressing the key in tab B while a panel was left
open in tab A would *close A* and show nothing in B — so it'd take a second
press to actually open here. Scoping the toggle to the active tab (and reaping
strays on open) makes a single press always do the obvious thing.

Speed: the panel is launched with `/usr/bin/python3 -S`, not the `python3` on
PATH. On this machine `python3` is a pyenv shim (~120ms cold start) whereas
Apple's /usr/bin/python3 starts in ~10ms; the panel is pure-stdlib so it doesn't
need pyenv. `-S` skips site.py for a little extra. Net: the overlay paints in
~40ms instead of ~200ms.
"""
from __future__ import annotations

import os

from kitty.boss import Boss
from kittens.tui.handler import result_handler

PANEL = os.path.expanduser("~/.dotfiles/kitty/agent_panel.py")
# fastest-starting interpreter available (see module docstring)
PYTHON = "/usr/bin/python3"
PYFLAGS = ("-S",)


def _log(msg: str) -> None:
    if os.environ.get("AGENT_PANEL_DEBUG"):
        try:
            with open("/tmp/agent-panel-toggle.log", "a", encoding="utf-8") as f:
                f.write(msg + "\n")
        except OSError:
            pass


def main(args: list) -> str:
    return ""


def _is_panel(w) -> bool:
    try:
        return (getattr(w, "user_vars", None) or {}).get("agent_panel") == "1"
    except Exception:
        return False


def _panel_in_tab(tab):
    try:
        for w in tab.windows:
            if _is_panel(w):
                return w
    except Exception:
        pass
    return None


def _stray_panels(boss: Boss, os_window_id):
    """Every panel in this OS-window. Only called from the open path, where the
    active tab has no panel — so any panel found is a stray in another tab."""
    found = []
    try:
        for w in boss.window_id_map.values():
            if _is_panel(w) and getattr(w, "os_window_id", None) == os_window_id:
                found.append(w)
    except Exception:
        pass
    return found


def _close(boss: Boss, target, window) -> None:
    try:
        boss.call_remote_control(target, ("close-window", "--match", "id:%d" % window.id))
    except Exception as e:
        _log("close id=%s failed: %s" % (getattr(window, "id", "?"), e))


@result_handler(no_ui=True)
def handle_result(args: list, answer: str, target_window_id: int, boss: Boss) -> None:
    # robust target: the keypress window, else whatever is active now
    target = boss.window_id_map.get(target_window_id) or getattr(boss, "active_window", None)
    tab = boss.active_tab
    if target is None or tab is None:
        _log("no target/tab (target_window_id=%s)" % target_window_id)
        return

    here = _panel_in_tab(tab)
    if here is not None:
        _log("toggle OFF: close panel id=%s in active tab" % here.id)
        _close(boss, target, here)
        return

    # opening: reap any panels left open in other tabs so there's only ever one
    for w in _stray_panels(boss, getattr(target, "os_window_id", None)):
        _log("reap stray panel id=%s" % w.id)
        _close(boss, target, w)

    _log("toggle ON: launch overlay over window id=%s" % getattr(target, "id", "?"))
    try:
        boss.call_remote_control(
            target,
            (
                "launch",
                "--type=overlay",
                "--cwd=current",
                "--var", "agent_panel=1",
                PYTHON, *PYFLAGS, PANEL,
            ),
        )
    except Exception as e:
        _log("launch failed: %s" % e)
