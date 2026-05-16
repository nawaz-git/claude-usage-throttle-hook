#!/usr/bin/env python3
"""
SessionStart hook for claude-usage-throttle-hook.

Injects initial quota context at the very start of a session so Claude
is aware of limits from the first prompt.
"""

import json
from pathlib import Path

STATE_FILE = Path.home() / ".claude" / "usage-throttle" / "state.json"
CONFIG_FILE = Path.home() / ".claude" / "usage-throttle" / "config.json"


def load_json(path):
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def main():
    state = load_json(STATE_FILE)
    config = load_json(CONFIG_FILE)
    mode = config.get("mode", "medium")

    five = state.get("five_hour_used_pct")
    week = state.get("seven_day_used_pct")

    def fmt(label, val):
        return f"{label}={val:.0f}%" if isinstance(val, (int, float)) else f"{label}=--"

    summary = (
        f"[usage-throttle] {fmt('5h', five)} {fmt('7d', week)} mode={mode}. "
        f"Usage throttle is active and will inject policy per prompt."
    )

    output = {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": summary,
        }
    }
    print(json.dumps(output))


if __name__ == "__main__":
    main()
