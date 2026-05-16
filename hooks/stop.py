#!/usr/bin/env python3
"""
Stop hook for claude-usage-throttle-hook.

Runs after each assistant turn. Records the turn timestamp to
~/.claude/usage-throttle/history.jsonl for session analytics.
Keeps history bounded to the last 500 entries.
"""

import json
import time
from pathlib import Path

STATE_DIR = Path.home() / ".claude" / "usage-throttle"
STATE_FILE = STATE_DIR / "state.json"
HISTORY_FILE = STATE_DIR / "history.jsonl"
MAX_HISTORY = 500


def load_json(path):
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def main():
    state = load_json(STATE_FILE)

    entry = {
        "ts": time.time(),
        "session_id": state.get("session_id"),
        "five_hour_used_pct": state.get("five_hour_used_pct"),
        "seven_day_used_pct": state.get("seven_day_used_pct"),
        "context_used_pct": state.get("context_used_pct"),
    }

    STATE_DIR.mkdir(parents=True, exist_ok=True)

    lines = []
    if HISTORY_FILE.exists():
        try:
            lines = HISTORY_FILE.read_text(encoding="utf-8").strip().splitlines()
        except Exception:
            lines = []

    lines.append(json.dumps(entry))

    if len(lines) > MAX_HISTORY:
        lines = lines[-MAX_HISTORY:]

    HISTORY_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
