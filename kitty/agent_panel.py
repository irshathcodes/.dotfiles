#!/usr/bin/env python3
"""Live Claude Code agent panel for kitty — a herdr-style overview shown as an
overlay over the active window.

Runs as a plain standalone program in a kitty window (launched as an overlay by
agent_panel_toggle.py). It:
  - enumerates Claude agents in the *current* kitty OS-window via `kitty @ ls`
  - joins them with per-session state written by the agent-panel-state.py hook
    (~/.claude/agent-panel/state/<session_id>.json)
  - renders an overview list; the selected/focused agent expands to its full
    todo checklist + current activity
  - Enter jumps focus to the selected agent's window (`kitty @ focus-window`)

Data refreshes on a short poll (~0.5s), so the hook only has to keep the state
files current. No third-party deps; talks to kitty over the inherited
KITTY_LISTEN_ON socket.

Modes:
  agent_panel.py            run the live panel
  agent_panel.py --once     print one real frame and exit (debugging)
  agent_panel.py --demo     print a frame from built-in fake data (layout check)
"""
from __future__ import annotations

import glob
import json
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import termios
import time
import tty

HOME = os.path.expanduser("~")
BASE = os.path.join(HOME, ".claude", "agent-panel")
STATE_DIR = os.path.join(BASE, "state")

SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
TICK = 0.1           # render cadence (smooth spinner)
DATA_INTERVAL = 0.5  # how often to re-fetch kitty @ ls + state files (poll)

# Kanagawa palette (matches the user's kitty theme)
RESET = "\x1b[0m"
BOLD = "\x1b[1m"
FG = "\x1b[38;2;220;215;186m"
DIM = "\x1b[38;2;113;113;105m"
YELLOW = "\x1b[38;2;230;195;132m"
RED = "\x1b[38;2;232;104;118m"
GREEN = "\x1b[38;2;152;187;108m"
BLUE = "\x1b[38;2;126;156;216m"
MAGENTA = "\x1b[38;2;149;127;184m"

STATE_COLOR = {
    "working": YELLOW,
    "needs-input": RED,
    "idle": DIM,
    "done": BLUE,
}
STATE_ORDER = {"needs-input": 0, "working": 1, "idle": 2, "done": 3}


def _dbg(msg: str) -> None:
    # lifecycle tracing, off unless AGENT_PANEL_DEBUG is set
    if os.environ.get("AGENT_PANEL_DEBUG"):
        try:
            with open("/tmp/agent-panel-run.log", "a", encoding="utf-8") as f:
                f.write(msg + "\n")
        except OSError:
            pass


def _on_term(signum, frame):  # noqa: ARG001
    # exit cleanly on SIGTERM (used by the toggle to close us) / SIGHUP so the
    # finally block restores the terminal
    _dbg("signal %s -> exit" % signum)
    raise SystemExit(0)


# ---------------------------------------------------------------- kitty access

def kitty_ls() -> list:
    try:
        cp = subprocess.run(
            ["kitty", "@", "ls"],
            capture_output=True,
            timeout=2.0,
        )
        if cp.returncode != 0:
            return []
        return json.loads(cp.stdout or b"[]")
    except Exception:
        return []


def kitty_focus(window_id) -> None:
    try:
        subprocess.run(
            ["kitty", "@", "focus-window", "--match", "id:{}".format(window_id)],
            capture_output=True,
            timeout=2.0,
        )
    except Exception:
        pass


def self_window_id() -> int | None:
    wid = os.environ.get("KITTY_WINDOW_ID")
    if wid:
        try:
            return int(wid)
        except ValueError:
            return None
    return None


def current_os_window(state: list, self_wid) -> dict | None:
    # the OS-window that contains our own window (is_self), else the focused one
    for osw in state:
        for tab in osw.get("tabs", []):
            for win in tab.get("windows", []):
                if win.get("is_self") or (self_wid is not None and win.get("id") == self_wid):
                    return osw
    for osw in state:
        if osw.get("is_focused"):
            return osw
    return state[0] if state else None


def window_is_claude(win: dict) -> bool:
    cmdlines = []
    for fp in win.get("foreground_processes") or []:
        cl = fp.get("cmdline")
        if cl:
            cmdlines.append(cl)
    if win.get("cmdline"):
        cmdlines.append(win["cmdline"])
    for cl in cmdlines:
        for tok in cl:
            if os.path.basename(str(tok)) == "claude":
                return True
    return False


# --------------------------------------------------------------- state loading

def load_states() -> tuple[dict, dict]:
    by_wid: dict = {}
    by_cwd: dict = {}
    for p in glob.glob(os.path.join(STATE_DIR, "*.json")):
        try:
            with open(p, "r", encoding="utf-8") as f:
                rec = json.load(f)
        except Exception:
            continue
        wid = rec.get("kitty_window_id")
        if wid is not None:
            try:
                by_wid[int(wid)] = rec
            except (TypeError, ValueError):
                pass
        if rec.get("cwd"):
            by_cwd.setdefault(rec["cwd"], rec)
    return by_wid, by_cwd


def short_model(model: str | None) -> str:
    if not model:
        return "claude"
    for fam in ("opus", "sonnet", "haiku", "fable"):
        if fam in model:
            return fam
    return "claude"


_TITLE_GLYPH = re.compile(r"^[⠀-⣿✳⚙⚠✨]+\s*")


def title_is_working(title: str) -> bool:
    return bool(re.match(r"^[⠀-⣿]", title or ""))


def strip_title(title: str) -> str:
    return _TITLE_GLYPH.sub("", title or "").strip()


def make_agent(win: dict, rec: dict | None) -> dict:
    rec = rec or {}
    cwd = rec.get("cwd") or win.get("cwd") or ""
    title = win.get("title") or ""
    state = rec.get("state")
    if not state:
        state = "working" if title_is_working(title) else "idle"
    title_act = strip_title(title)
    has_live_title = title_is_working(title) and title_act and title_act.lower() != "claude code"
    if has_live_title:
        # Claude is actively showing a verb in its title (braille spinner present)
        # — that's the richest, most current activity text.
        activity = title_act
    else:
        # otherwise trust the hook-derived activity; fall back to the (static)
        # title only when we have no state record at all.
        activity = rec.get("activity") or (title_act if not rec else "")
    if activity.lower() == "claude code":
        activity = ""  # generic app name is not a useful activity
    repo = os.path.basename(cwd.rstrip("/")) or cwd or "agent"
    return {
        "window_id": win.get("id"),
        "is_focused": bool(win.get("is_focused")),
        "last_focused_at": float(win.get("last_focused_at") or 0),
        "repo": repo,
        "branch": rec.get("git_branch") or "",
        "model": short_model(rec.get("model")),
        "state": state,
        "activity": activity,
        "todos": rec.get("todos") or [],
        "started_at": rec.get("started_at"),
        "updated_at": rec.get("updated_at"),
    }


def collect_agents() -> list:
    state = kitty_ls()
    self_wid = self_window_id()
    osw = current_os_window(state, self_wid)
    if not osw:
        return []
    by_wid, by_cwd = load_states()
    agents = []
    for tab in osw.get("tabs", []):
        for win in tab.get("windows", []):
            wid = win.get("id")
            if wid == self_wid:
                continue
            if (win.get("user_vars") or {}).get("agent_panel") == "1":
                continue
            if not window_is_claude(win):
                continue
            rec = by_wid.get(wid) or by_cwd.get(win.get("cwd"))
            agents.append(make_agent(win, rec))
    agents.sort(key=lambda a: (STATE_ORDER.get(a["state"], 9), a["repo"], a["window_id"] or 0))
    return agents


# ------------------------------------------------------------------- rendering

def fmt_elapsed(start: float | None) -> str:
    if not start:
        return ""
    secs = int(max(0, time.time() - start))
    if secs < 60:
        return "{}s".format(secs)
    if secs < 3600:
        return "{}m{:02d}s".format(secs // 60, secs % 60)
    return "{}h{:02d}m".format(secs // 3600, (secs % 3600) // 60)


def disp_width(s: str) -> int:
    # our glyphs render single-width in kitty (ambiguous=narrow); strip SGR
    return len(re.sub(r"\x1b\[[0-9;]*m", "", s))


def truncate(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width == 1:
        return "…"
    return text[: width - 1] + "…"


def pad_between(left: str, right: str, width: int) -> str:
    """Left-justify `left`, right-justify `right`, on a single line of `width`."""
    lw, rw = disp_width(left), disp_width(right)
    if lw + rw + 1 > width:
        left = truncate(left, max(1, width - rw - 1))
        lw = disp_width(left)
    gap = max(1, width - lw - rw)
    return left + (" " * gap) + right


def state_dot(state: str) -> str:
    color = STATE_COLOR.get(state, DIM)
    glyph = "●" if state in ("working", "needs-input") else "○"
    return color + glyph + RESET


def spinner_char(state: str, frame: int) -> str:
    if state == "working":
        return YELLOW + SPINNER[frame % len(SPINNER)] + RESET
    if state == "needs-input":
        return RED + "⚠" + RESET
    if state == "done":
        return BLUE + "✓" + RESET
    return DIM + "·" + RESET


def todo_glyph(status: str) -> tuple[str, str]:
    if status == "completed":
        return DIM + "☑" + RESET, DIM
    if status == "in_progress":
        return YELLOW + "■" + RESET, FG + BOLD
    return DIM + "☐" + RESET, FG


def render_agent(a: dict, selected: bool, frame: int, width: int) -> list[str]:
    lines = []
    color = STATE_COLOR.get(a["state"], FG)
    cursor = (BLUE + "›" + RESET) if selected else " "
    # header: cursor + dot + repo .......... n/m
    todos = a["todos"]
    done = sum(1 for t in todos if t.get("status") == "completed")
    total = len(todos)
    repo = (BOLD + color + a["repo"] + RESET)
    left = "{} {} {}".format(cursor, state_dot(a["state"]), repo)
    right = (DIM + "{}/{}".format(done, total) + RESET) if total else ""
    lines.append(pad_between(left, right, width))

    # meta line: branch · model · elapsed
    meta_bits = []
    if a["branch"]:
        meta_bits.append(a["branch"])
    meta_bits.append(a["model"])
    if a["state"] == "working":
        el = fmt_elapsed(a["started_at"])
        if el:
            meta_bits.append(el)
    elif a["state"] == "needs-input":
        meta_bits.append("needs input")
    lines.append("   " + DIM + truncate(" · ".join(meta_bits), width - 3) + RESET)

    # activity line
    activity = a["activity"] or {"idle": "idle", "done": "done"}.get(a["state"], "")
    if activity:
        sp = spinner_char(a["state"], frame)
        act = truncate(activity, width - 5)
        lines.append("   {} {}".format(sp, FG + act + RESET))

    # todo checklist (only when expanded/selected)
    if selected and total:
        for t in todos:
            glyph, txt_color = todo_glyph(t.get("status", "pending"))
            label = t.get("content", "")
            label = truncate(label, width - 7)
            lines.append("     {} {}".format(glyph, txt_color + label + RESET))
    return lines


def render_frame(agents: list, selected_wid, frame: int, width: int, height: int) -> str:
    width = max(20, width)
    out = ["\x1b[H\x1b[2J"]  # home + clear
    header = " agents"
    count = "{}".format(len(agents))
    out.append(BOLD + BLUE + header + RESET + "  " + DIM + count + RESET)
    out.append(DIM + ("─" * width) + RESET)
    if not agents:
        out.append("")
        out.append("   " + DIM + "No Claude agents in this window." + RESET)
        out.append("")
        out.append("   " + DIM + "Start `claude` in a tab here." + RESET)
        return "\r\n".join(out) + "\r\n"
    for a in agents:
        selected = a["window_id"] == selected_wid
        out.extend(render_agent(a, selected, frame, width))
        out.append("")
    # footer
    out.append(DIM + ("─" * width) + RESET)
    out.append(DIM + " ↑↓ move · ⏎ jump · q quit" + RESET)
    body = "\r\n".join(out)
    return body + "\r\n"


# ------------------------------------------------------------------- key input

def read_key() -> str:
    ch = sys.stdin.read(1)
    if ch == "":
        return "quit"  # EOF: terminal/pty closed (window closed) -> exit
    if ch == "\x1b":
        r, _, _ = select.select([sys.stdin], [], [], 0.02)
        if not r:
            return "esc"
        seq = ch + sys.stdin.read(1)
        if seq == "\x1b[":
            seq += sys.stdin.read(1)
        return {"\x1b[A": "up", "\x1b[B": "down"}.get(seq, "esc")
    if ch in ("\r", "\n"):
        return "enter"
    if ch in ("\x03", "\x04"):
        return "quit"
    if ch in ("k", "\x10"):
        return "up"
    if ch in ("j", "\x0e"):
        return "down"
    if ch in ("q",):
        return "quit"
    if ch in ("g",):
        return "home"
    if ch in ("G",):
        return "end"
    return ""


# ----------------------------------------------------------------------- loop

def resolve_selection(agents: list, selected_wid):
    ids = [a["window_id"] for a in agents]
    if selected_wid in ids:
        return selected_wid
    # default: the focused claude agent, else most-recently-focused, else first
    focused = [a for a in agents if a["is_focused"]]
    if focused:
        return focused[0]["window_id"]
    if agents:
        return max(agents, key=lambda a: a["last_focused_at"])["window_id"]
    return None


def run() -> int:
    os.makedirs(BASE, exist_ok=True)
    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGHUP, _on_term)

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    sys.stdout.write("\x1b[?25l")  # hide cursor
    sys.stdout.flush()

    agents: list = []
    selected_wid = None
    frame = 0
    last_fetch = 0.0
    _dbg("run() entered; isatty=%s" % sys.stdin.isatty())
    try:
        while True:
            now = time.monotonic()
            if (now - last_fetch) >= DATA_INTERVAL:
                agents = collect_agents()
                _dbg("fetch f=%d agents=%d" % (frame, len(agents)))
                selected_wid = resolve_selection(agents, selected_wid)
                last_fetch = now
            width, height = shutil.get_terminal_size((40, 40))
            try:
                sys.stdout.write(render_frame(agents, selected_wid, frame, width, height))
                sys.stdout.flush()
            except (BrokenPipeError, OSError) as e:
                _dbg("write failed -> exit: %r" % e)
                break  # terminal went away (window closed)
            frame += 1

            r, _, _ = select.select([sys.stdin], [], [], TICK)
            if not r:
                continue
            key = read_key()
            _dbg("key=%r" % key)
            if key == "quit":
                break
            if key == "esc":
                break
            if not agents:
                continue
            ids = [a["window_id"] for a in agents]
            try:
                idx = ids.index(selected_wid)
            except ValueError:
                idx = 0
            if key == "up":
                idx = max(0, idx - 1)
                selected_wid = ids[idx]
            elif key == "down":
                idx = min(len(ids) - 1, idx + 1)
                selected_wid = ids[idx]
            elif key == "home":
                selected_wid = ids[0]
            elif key == "end":
                selected_wid = ids[-1]
            elif key == "enter":
                kitty_focus(selected_wid)
    finally:
        # best-effort: restore the terminal (the overlay just closes, no layout
        # to undo)
        try:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
            sys.stdout.write("\x1b[?25h\x1b[2J\x1b[H")
            sys.stdout.flush()
        except Exception:
            pass
    return 0


# ------------------------------------------------------------------- dev modes

def _demo_agents() -> list:
    now = time.time()
    return [
        {
            "window_id": 1, "is_focused": True, "last_focused_at": now,
            "repo": "spend-management", "branch": "expense-updates", "model": "opus",
            "state": "working", "activity": "Adding notify calls to expense-reports.service",
            "started_at": now - 83, "updated_at": now,
            "todos": [
                {"content": "Create BillingNotificationService", "status": "completed"},
                {"content": "Wire BillingModule into both modules", "status": "completed"},
                {"content": "Add notify calls in expense-reports.service", "status": "in_progress"},
                {"content": "Add BILLING_INVOICING_URL env + update spec", "status": "pending"},
                {"content": "Build + lint check, then update worklog", "status": "pending"},
            ],
        },
        {
            "window_id": 2, "is_focused": False, "last_focused_at": now - 200,
            "repo": "gql", "branch": "main", "model": "sonnet",
            "state": "needs-input", "activity": "Allow running migration?",
            "started_at": now - 400, "updated_at": now, "todos": [],
        },
        {
            "window_id": 3, "is_focused": False, "last_focused_at": now - 600,
            "repo": "frontend", "branch": "main", "model": "opus",
            "state": "idle", "activity": "", "started_at": None, "updated_at": now - 240,
            "todos": [{"content": "x", "status": "completed"}, {"content": "y", "status": "completed"}],
        },
    ]


def main(argv: list[str]) -> int:
    if "--demo" in argv:
        agents = _demo_agents()
        width, height = shutil.get_terminal_size((40, 40))
        sys.stdout.write(render_frame(agents, 1, 2, min(width, 44), height).replace("\r\n", "\n"))
        return 0
    if "--once" in argv:
        agents = collect_agents()
        sel = resolve_selection(agents, None)
        width, height = shutil.get_terminal_size((40, 40))
        sys.stdout.write(render_frame(agents, sel, 2, min(width, 44), height).replace("\r\n", "\n"))
        return 0
    return run()


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except BaseException:
        import traceback
        try:
            with open("/tmp/agent-panel.log", "a", encoding="utf-8") as _f:
                _f.write("--- crash ---\n" + traceback.format_exc())
        except OSError:
            pass
        sys.exit(1)
