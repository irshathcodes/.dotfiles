#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import select
import shutil
import subprocess
import sys
import termios
import time
import traceback
import tty
from typing import Any, Iterable

try:
    from kittens.tui.handler import kitten_ui
except Exception:  # pragma: no cover - only absent outside kitty
    kitten_ui = None

LOG_PATH = "/tmp/kitty-picker.log"


class PickerItem:
    def __init__(
        self,
        id: str,
        title: str,
        subtitle: str = "",
        search_text: tuple[str, ...] = (),
        payload: dict[str, Any] | None = None,
        active: bool = False,
    ) -> None:
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.search_text = search_text
        self.payload = payload or {}
        self.active = active


class PickerState:
    def __init__(
        self,
        items: list[PickerItem],
        query: str = "",
        selected: int = 0,
        armed_delete_id: str | None = None,
    ) -> None:
        self.items = items
        self.query = query
        self.selected = selected
        self.armed_delete_id = armed_delete_id

    def matches(self) -> list[PickerItem]:
        return rank_items(self.items, self.query)

    def selected_item(self) -> PickerItem | None:
        matches = self.matches()
        if not matches:
            return None
        self.selected = max(0, min(self.selected, len(matches) - 1))
        return matches[self.selected]

    def move(self, amount: int) -> None:
        matches = self.matches()
        if not matches:
            self.selected = 0
            return
        self.selected = max(0, min(self.selected + amount, len(matches) - 1))
        self.armed_delete_id = None

    def set_query(self, query: str) -> None:
        self.query = query
        self.selected = 0
        self.armed_delete_id = None

    def append_query(self, text: str) -> None:
        self.set_query(self.query + text)

    def backspace(self) -> None:
        self.set_query(self.query[:-1])

    def clear_or_exit(self) -> bool:
        self.armed_delete_id = None
        if self.query:
            self.set_query("")
            return False
        return True

    def delete_action(self) -> dict[str, Any] | None:
        item = self.selected_item()
        if item is None:
            return None
        if item.payload.get("action") == "goto_session":
            return {"action": "close_session", "name": item.payload["name"]}
        if item.payload.get("action") == "focus_window":
            return {"action": "close_window", "window_id": item.payload["window_id"]}
        return None

    def remove_item(self, item_id: str) -> None:
        self.items = [item for item in self.items if item.id != item_id]
        self.selected = max(0, min(self.selected, len(self.matches()) - 1))
        self.armed_delete_id = None

    def replace_items(self, items: list[PickerItem]) -> None:
        selected = self.selected_item()
        selected_id = selected.id if selected else None
        self.items = items
        matches = self.matches()
        if not matches:
            self.selected = 0
            return
        if selected_id:
            for idx, item in enumerate(matches):
                if item.id == selected_id:
                    self.selected = idx
                    return
        self.selected = max(0, min(self.selected, len(matches) - 1))


def initial_selected_index(items: list[PickerItem], query: str = "") -> int:
    matches = rank_items(items, query)
    for idx, item in enumerate(matches):
        if item.active:
            return idx
    return 0


def query_words(query: str) -> list[str]:
    return [word.casefold() for word in query.split() if word.strip()]


def item_fields(item: PickerItem) -> list[str]:
    fields = [item.title, item.subtitle, *item.search_text]
    return [field.casefold() for field in fields if field]


def is_subsequence(needle: str, haystack: str) -> bool:
    if not needle:
        return True
    pos = 0
    for char in haystack:
        if char == needle[pos]:
            pos += 1
            if pos == len(needle):
                return True
    return False


def word_match_score(word: str, fields: Iterable[str]) -> int | None:
    best: int | None = None
    for field in fields:
        parts = re.findall(r"[\w.-]+", field)
        score: int | None = None
        if word in parts:
            score = 0
        elif any(part.startswith(word) for part in parts):
            score = 1
        elif word in field:
            score = 2
        elif is_subsequence(word, field):
            score = 3
        if score is not None and (best is None or score < best):
            best = score
    return best


def rank_items(items: list[PickerItem], query: str) -> list[PickerItem]:
    words = query_words(query)
    if not words:
        return items

    ranked: list[tuple[tuple[int, int, int, int], PickerItem]] = []
    for index, item in enumerate(items):
        fields = item_fields(item)
        scores: list[int] = []
        for word in words:
            score = word_match_score(word, fields)
            if score is None:
                break
            scores.append(score)
        else:
            ranked.append(((sum(scores), max(scores), len(item.title), index), item))
    return [item for _, item in sorted(ranked, key=lambda row: row[0])]


def active_tab_from_state(state: list[dict[str, Any]]) -> dict[str, Any] | None:
    tabs: list[dict[str, Any]] = []
    for os_window in state:
        tabs.extend(os_window.get("tabs", []))
    for tab in tabs:
        if tab.get("is_active"):
            return tab
    for tab in tabs:
        if tab.get("is_focused"):
            return tab
    return tabs[0] if tabs else None


def non_self_windows(tab: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not tab:
        return []
    return [window for window in tab.get("windows", []) if not window.get("is_self")]


def active_window_id_from_tab(tab: dict[str, Any] | None) -> int | None:
    if not tab:
        return None
    active_id = tab.get("active_window_id")
    for window in non_self_windows(tab):
        if window.get("id") == active_id:
            return active_id
    for window in non_self_windows(tab):
        if window.get("is_active") or window.get("is_focused"):
            return window.get("id")
    newest_window: dict[str, Any] | None = None
    newest_focus = -1.0
    for window in non_self_windows(tab):
        focused_at = float(window.get("last_focused_at") or 0)
        if focused_at > newest_focus:
            newest_focus = focused_at
            newest_window = window
    return newest_window.get("id") if newest_window else active_id


def tab_with_self(tabs: list[dict[str, Any]]) -> dict[str, Any] | None:
    for tab in tabs:
        if any(window.get("is_self") for window in tab.get("windows", [])):
            return tab
    return None


def active_tab_from_tabs(tabs: list[dict[str, Any]]) -> dict[str, Any] | None:
    for tab in tabs:
        if tab.get("is_active") and non_self_windows(tab):
            return tab
    for tab in tabs:
        if tab.get("is_focused") and non_self_windows(tab):
            return tab
    return None


def most_recent_split_tab(tabs: list[dict[str, Any]]) -> dict[str, Any] | None:
    best_tab: dict[str, Any] | None = None
    best_focus = -1.0
    for tab in tabs:
        for window in non_self_windows(tab):
            focused_at = float(window.get("last_focused_at") or 0)
            if focused_at > best_focus:
                best_focus = focused_at
                best_tab = tab
    return best_tab


def active_split_tab_from_state(state: list[dict[str, Any]]) -> dict[str, Any] | None:
    for os_window in state:
        tabs = os_window.get("tabs", [])
        self_tab = tab_with_self(tabs)
        if self_tab is None:
            continue
        if non_self_windows(self_tab):
            return self_tab
        return active_tab_from_tabs(tabs) or most_recent_split_tab(tabs)

    active_tab = active_tab_from_state(state)
    if active_tab and non_self_windows(active_tab):
        return active_tab
    all_tabs: list[dict[str, Any]] = []
    for os_window in state:
        all_tabs.extend(os_window.get("tabs", []))
    return most_recent_split_tab(all_tabs)


def window_sort_key(window: dict[str, Any]) -> tuple[int, int]:
    return (int(window.get("num") or 0), int(window.get("id") or 0))


def active_session_name_from_tab(tab: dict[str, Any] | None) -> str | None:
    if not tab:
        return None
    active_id = active_window_id_from_tab(tab)
    for window in tab.get("windows", []):
        if window.get("is_self"):
            continue
        if window.get("id") == active_id or window.get("is_active") or window.get("is_focused"):
            return window.get("session_name") or tab.get("session_name")
    return None


def active_session_name_from_state(state: list[dict[str, Any]]) -> str | None:
    tab_session = active_session_name_from_tab(active_tab_from_state(state))
    if tab_session:
        return tab_session

    best_name: str | None = None
    best_focus = -1.0
    for os_window in state:
        for tab in os_window.get("tabs", []):
            for window in tab.get("windows", []):
                name = window.get("session_name") or tab.get("session_name")
                if not name:
                    continue
                if window.get("is_self"):
                    continue
                focused_at = float(window.get("last_focused_at") or 0)
                if focused_at > best_focus:
                    best_focus = focused_at
                    best_name = name
    return best_name


def short_cwd(window: dict[str, Any]) -> str:
    cwd = window.get("cwd") or ""
    if cwd.startswith(os.path.expanduser("~")):
        cwd = "~" + cwd[len(os.path.expanduser("~")) :]
    return cwd


def window_title(window: dict[str, Any]) -> str:
    return window.get("title") or window.get("name") or f"Split {window.get('id')}"


def strip_loading_prefix(title: str) -> str:
    return re.sub(r"^[\u2800-\u28ff✳]\s*", "", title).strip() or title


def title_has_loading_spinner(title: str) -> bool:
    return bool(re.match(r"^[\u2800-\u28ff]", title or ""))


def truthy_metadata(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value > 0
    if isinstance(value, str):
        return value.strip().casefold() in {"1", "true", "yes", "y", "on", "loading", "running"}
    return False


def window_is_loading(window: dict[str, Any]) -> bool:
    if title_has_loading_spinner(window_title(window)):
        return True

    for key in ("is_loading", "loading"):
        if truthy_metadata(window.get(key)):
            return True

    progress = window.get("progress")
    if isinstance(progress, (int, float)):
        return 0 < progress < 100
    if isinstance(progress, str) and progress.strip().isdigit():
        return 0 < int(progress) < 100

    user_vars = window.get("user_vars") or {}
    for key in ("is_loading", "loading", "progress", "kitty_progress"):
        value = user_vars.get(key)
        if key.endswith("progress"):
            if isinstance(value, (int, float)):
                return 0 < value < 100
            if isinstance(value, str) and value.strip().isdigit():
                return 0 < int(value) < 100
        elif truthy_metadata(value):
            return True
    return False


def build_window_items(state: list[dict[str, Any]]) -> list[PickerItem]:
    tab = active_split_tab_from_state(state)
    windows = sorted(non_self_windows(tab), key=window_sort_key)
    active_id = active_window_id_from_tab(tab)
    total = len(windows)
    items: list[PickerItem] = []
    for idx, window in enumerate(windows, start=1):
        cwd = short_cwd(window)
        session_name = window.get("session_name") or tab.get("session_name") or ""
        win_id = str(window.get("id"))
        raw_title = window_title(window)
        display_title = strip_loading_prefix(raw_title)
        items.append(
            PickerItem(
                id=win_id,
                title=display_title,
                subtitle=cwd,
                search_text=(raw_title, display_title, cwd, session_name, str(window.get("id", ""))),
                payload={
                    "action": "focus_window",
                    "window_id": win_id,
                    "index": str(idx),
                    "position": f"{idx}/{total}",
                    "session_name": session_name,
                    "loading": window_is_loading(window),
                },
                active=window.get("id") == active_id,
            )
        )
    return items


def build_session_items(state: list[dict[str, Any]]) -> list[PickerItem]:
    active_session = active_session_name_from_state(state)
    sessions: dict[str, dict[str, Any]] = {}
    for os_window in state:
        for tab in os_window.get("tabs", []):
            for window in tab.get("windows", []):
                name = window.get("session_name") or tab.get("session_name")
                if not name:
                    continue
                entry = sessions.setdefault(name, {"count": 0})
                entry["count"] += 1

    items: list[PickerItem] = []
    for name in sorted(sessions):
        items.append(
            PickerItem(
                id=name,
                title=name,
                search_text=(name,),
                payload={"action": "goto_session", "name": name},
                active=name == active_session,
            )
        )
    return items


def truncate(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width == 1:
        return ">"
    return text[: width - 1] + ">"


def clear_screen() -> None:
    sys.stdout.write("\x1b[2J\x1b[H")


def split_row(prefix: str, heading: str, path: str, width: int) -> str:
    available = width - len(prefix)
    if available <= 0:
        return truncate(prefix, width)
    if not path:
        return prefix + truncate(heading, available)

    gap = 4
    min_heading_width = min(12, max(1, available - gap))
    path_width = min(len(path), max(0, available - min_heading_width - gap))
    if path_width <= 0:
        return prefix + truncate(heading, available)

    path_text = truncate(path, path_width)
    heading_width = max(1, available - len(path_text) - gap)
    heading_text = truncate(heading, heading_width)
    padding = max(gap, available - len(heading_text) - len(path_text))
    return prefix + heading_text + (" " * padding) + path_text


def split_heading(item: PickerItem) -> str:
    session_name = item.payload.get("session_name") or ""
    heading = f"{session_name} - {item.title}" if session_name else item.title
    if item.payload.get("loading"):
        heading += "   (loading)"
    return heading


def render(mode: str, state: PickerState, status: str = "") -> None:
    width, height = shutil.get_terminal_size((100, 30))
    matches = state.matches()
    selected = state.selected_item()
    label = "sessions" if mode == "sessions" else "splits"
    max_rows = max(1, height - 5)
    start = 0
    if state.selected >= max_rows:
        start = state.selected - max_rows + 1
    visible = matches[start : start + max_rows]

    clear_screen()
    sys.stdout.write(f"Kitty {label} picker\n")
    sys.stdout.write(f"> {state.query}\n")
    sys.stdout.write("-" * width + "\n")
    if not state.items:
        sys.stdout.write(f"No {label} available.\n")
    elif not matches:
        sys.stdout.write("No matches.\n")
    else:
        for offset, item in enumerate(visible, start=start):
            is_selected = selected is not None and item.id == selected.id and offset == state.selected
            if mode == "sessions":
                cursor = ">" if is_selected else " "
                sys.stdout.write(f"{cursor} {truncate(item.title, width - 2)}\n")
                continue
            cursor = ">" if is_selected else " "
            index = item.payload.get("index") or str(offset + 1)
            prefix = f"{cursor} {index}. "
            sys.stdout.write(split_row(prefix, split_heading(item), item.subtitle, width) + "\n")

    footer = status or "Enter select  Ctrl+D close session  Esc clear/exit"
    if mode != "sessions":
        footer = status or "Enter select  Ctrl+D close split  Esc clear/exit"
    sys.stdout.write("-" * width + "\n")
    sys.stdout.write(truncate(footer, width) + "\n")
    sys.stdout.flush()


def read_key() -> str:
    char = sys.stdin.read(1)
    if char == "\x1b":
        r, _, _ = select.select([sys.stdin], [], [], 0.03)
        if not r:
            return "esc"
        seq = char + sys.stdin.read(1)
        if seq == "\x1b[":
            final = sys.stdin.read(1)
            if final in "123456789":
                suffix = sys.stdin.read(1)
                seq += final + suffix
            else:
                seq += final
        mapping = {
            "\x1b[A": "up",
            "\x1b[B": "down",
            "\x1b[5~": "page_up",
            "\x1b[6~": "page_down",
            "\x1b[H": "home",
            "\x1b[F": "end",
        }
        return mapping.get(seq, "esc")
    if char in ("\r", "\n"):
        return "enter"
    if char in ("\x7f", "\b"):
        return "backspace"
    if char == "\x04":
        return "ctrl_d"
    if char == "\x0b":
        return "up"
    if char == "\x0e":
        return "down"
    if char == "\x10":
        return "up"
    if char.isprintable():
        return char
    return ""


def poll_key(timeout: float) -> str | None:
    ready, _, _ = select.select([sys.stdin], [], [], timeout)
    if not ready:
        return None
    return read_key()


def build_items_for_mode(mode: str) -> list[PickerItem]:
    state = load_kitty_state()
    return build_session_items(state) if mode == "sessions" else build_window_items(state)


class RawTerminal:
    def __enter__(self) -> None:
        self.fd = sys.stdin.fileno()
        self.old = termios.tcgetattr(self.fd)
        tty.setcbreak(self.fd)
        sys.stdout.write("\x1b[?25l")
        sys.stdout.flush()

    def __exit__(self, exc_type: object, exc: object, tb: object) -> None:
        termios.tcsetattr(self.fd, termios.TCSADRAIN, self.old)
        sys.stdout.write("\x1b[?25h\x1b[2J\x1b[H")
        sys.stdout.flush()


def run_picker(mode: str, items: list[PickerItem]) -> dict[str, Any] | None:
    state = PickerState(items, selected=initial_selected_index(items))
    page_size = max(1, shutil.get_terminal_size((100, 30)).lines - 5)
    status = ""
    refresh_interval = 1.0 if mode != "sessions" else 0.0
    next_refresh = time.monotonic() + refresh_interval if refresh_interval else 0.0
    with RawTerminal():
        while True:
            render(mode, state, status)
            status = ""
            timeout = max(0.0, next_refresh - time.monotonic()) if refresh_interval else None
            key = poll_key(timeout) if timeout is not None else read_key()
            if key is None:
                try:
                    state.replace_items(build_items_for_mode(mode))
                except Exception:
                    status = "Refresh failed"
                next_refresh = time.monotonic() + refresh_interval
                continue
            if key == "enter":
                item = state.selected_item()
                if item and mode != "sessions" and item.payload.get("action") == "focus_window":
                    focus_window(item.payload["window_id"])
                    return None
                return item.payload if item else None
            if key == "esc":
                if state.clear_or_exit():
                    return None
            elif key == "up":
                state.move(-1)
            elif key == "down":
                state.move(1)
            elif key == "page_up":
                state.move(-page_size)
            elif key == "page_down":
                state.move(page_size)
            elif key == "home":
                state.selected = 0
                state.armed_delete_id = None
            elif key == "end":
                state.selected = max(0, len(state.matches()) - 1)
                state.armed_delete_id = None
            elif key == "backspace":
                state.backspace()
            elif key == "ctrl_d" and mode == "sessions":
                item = state.selected_item()
                action = state.delete_action()
                if item and action:
                    # Gather the backing zmx sessions BEFORE closing (the windows
                    # carry the info). Close the kitty session first so each pane's
                    # reconnect loop dies and cannot recreate the session, THEN
                    # kill the zmx sessions on the server.
                    zmx = zmx_sessions_for(action["name"])
                    close_session(action["name"])
                    kill_zmx(zmx)
                    state.remove_item(item.id)
                    status = f"Closed {action['name']}" + (f" (+{len(zmx)} zmx)" if zmx else "")
            elif key == "ctrl_d" and mode != "sessions":
                item = state.selected_item()
                action = state.delete_action()
                if item and action:
                    close_window(action["window_id"])
                    state.remove_item(item.id)
                    status = "Closed split"
            elif len(key) == 1:
                state.append_query(key)


def load_kitty_state() -> list[dict[str, Any]]:
    cp = main.remote_control(["ls"], capture_output=True)
    if cp.returncode != 0:
        sys.stderr.buffer.write(cp.stderr)
        raise SystemExit(cp.returncode)
    return json.loads(cp.stdout)


def close_session(name: str) -> None:
    main.remote_control(["action", "close_session", name], capture_output=True)


def close_window(window_id: str) -> None:
    main.remote_control(["close-window", "--match", f"id:{window_id}"], capture_output=True)


def focus_window(window_id: str) -> None:
    main.remote_control(["focus-window", "--match", f"id:{window_id}"], capture_output=True)


REMOTE_HOST = os.environ.get("REMOTE_HOST", "moideen")


def zmx_sessions_for(session_name: str) -> list[str]:
    """Every cs/zmx session name backing the remote panes of a kitty session.

    Read straight from live kitty state: a remote pane carries its zmx session
    in user_vars.cs_session (set by kittymux / new_session.py); fall back to
    parsing the `remote-attach.sh <proj> <name>` cmdline for older panes. Local
    panes have neither, so a local session yields [] (nothing to kill).
    """
    try:
        state = load_kitty_state()
    except Exception:
        return []
    found: list[str] = []
    for os_window in state:
        for tab in os_window.get("tabs", []):
            tab_sn = tab.get("session_name")
            for window in tab.get("windows", []):
                if (window.get("session_name") or tab_sn) != session_name:
                    continue
                cs = (window.get("user_vars") or {}).get("cs_session")
                if not cs:
                    cmd = window.get("cmdline") or []
                    if (isinstance(cmd, list) and len(cmd) >= 4
                            and isinstance(cmd[1], str) and "remote-attach" in cmd[1]):
                        cs = f"{cmd[2]}.{cmd[3]}"
                if cs and cs not in found:
                    found.append(cs)
    return found


def kill_zmx(sessions: list[str]) -> bool:
    """Kill the given zmx sessions on the server (zmx kill takes many names)."""
    if not sessions:
        return False
    ssh = shutil.which("ssh") or "/usr/bin/ssh"
    try:
        subprocess.run([ssh, REMOTE_HOST, "zmx", "kill", *sessions],
                       timeout=10, capture_output=True)
        return True
    except Exception:
        return False


def picker_main(args: list[str]) -> str:
    try:
        mode = next((arg for arg in args if arg in {"sessions", "windows", "splits"}), "sessions")
        items = build_items_for_mode(mode)
        payload = run_picker(mode, items)
        return json.dumps(payload or {})
    except Exception:
        with open(LOG_PATH, "a", encoding="utf-8") as log:
            log.write("\n--- kitty picker crash ---\n")
            log.write("args: " + repr(args) + "\n")
            traceback.print_exc(file=log)
        raise


if kitten_ui is None:
    main = picker_main
else:
    main = kitten_ui(allow_remote_control=True)(picker_main)


def handle_result(args: list[str], answer: str, target_window_id: int, boss: Any) -> None:
    try:
        payload = json.loads(answer or "{}")
    except json.JSONDecodeError:
        return
    action = payload.get("action")
    target = boss.window_id_map.get(target_window_id)
    if target is None:
        return
    if action == "focus_window":
        boss.call_remote_control(target, ("focus-window", "--match", f"id:{payload['window_id']}"))
    elif action == "goto_session":
        boss.call_remote_control(target, ("action", "goto_session", payload["name"]))
    elif action == "close_session":
        boss.call_remote_control(target, ("action", "close_session", payload["name"]))
