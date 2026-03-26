import json
import os

RESULT_FILE = "/tmp/kitty-sessions.json"


def main(args):
    return ""


def handle_result(args, answer, target_window_id, boss):
    try:
        active = boss.active_session
        all_names = sorted(boss.all_loaded_session_names)
        result = json.dumps({"active": active, "sessions": all_names})
    except Exception as e:
        result = json.dumps({"error": str(e)})
    with open(RESULT_FILE, "w") as f:
        f.write(result)
