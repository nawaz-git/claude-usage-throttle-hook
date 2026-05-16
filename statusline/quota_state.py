#!/usr/bin/env python3
"""
Statusline script for claude-usage-throttle-hook.

Reads the official Claude Code statusLine JSON from stdin, persists a
quota snapshot to ~/.claude/usage-throttle/state.json, and prints a compact
status string for the terminal status bar.

Usage in settings.json:
  "statusLine": {
    "type": "command",
    "command": "python ~/.claude/usage-throttle/statusline/quota_state.py",
    "refreshInterval": 10
  }
"""

import json
import sys
import time
from pathlib import Path

STATE_DIR = Path.home() / ".claude" / "usage-throttle"
STATE_FILE = STATE_DIR / "state.json"
CONFIG_FILE = STATE_DIR / "config.json"


def pct(value):
    if value is None:
        return None
    try:
        return round(float(value), 1)
    except Exception:
        return None


def load_config():
    if not CONFIG_FILE.exists():
        return {"mode": "medium"}
    try:
        return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    except Exception:
        return {"mode": "medium"}


def severity_icon(five, week, mode):
    thresholds = {
        "fast":   {"conserve_5h": 90, "critical_5h": 98, "conserve_7d": 95, "critical_7d": 99},
        "medium": {"conserve_5h": 80, "critical_5h": 95, "conserve_7d": 85, "critical_7d": 95},
        "low":    {"conserve_5h": 50, "critical_5h": 75, "conserve_7d": 60, "critical_7d": 80},
    }
    t = thresholds.get(mode, thresholds["medium"])
    if (five is not None and five >= t["critical_5h"]) or (week is not None and week >= t["critical_7d"]):
        return "!!"
    if (five is not None and five >= t["conserve_5h"]) or (week is not None and week >= t["conserve_7d"]):
        return "!"
    return ""


def main():
    raw = sys.stdin.read() or "{}"
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        data = {}

    context = data.get("context_window", {}) or {}
    limits = data.get("rate_limits", {}) or {}

    five_hour = (limits.get("five_hour") or {})
    seven_day = (limits.get("seven_day") or {})

    five_used = pct(five_hour.get("used_percentage"))
    week_used = pct(seven_day.get("used_percentage"))
    ctx_used = pct(context.get("used_percentage"))

    snapshot = {
        "session_id": data.get("session_id"),
        "context_used_pct": ctx_used,
        "context_remaining_pct": pct(context.get("remaining_percentage")),
        "five_hour_used_pct": five_used,
        "five_hour_resets_at": five_hour.get("resets_at"),
        "seven_day_used_pct": week_used,
        "seven_day_resets_at": seven_day.get("resets_at"),
        "updated_at": time.time(),
    }

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(snapshot, indent=2), encoding="utf-8")

    config = load_config()
    mode = config.get("mode", "medium")
    icon = severity_icon(five_used, week_used, mode)

    def fmt(label, val):
        return f"{label}:{val:.0f}%" if isinstance(val, (int, float)) else f"{label}:--"

    parts = [fmt("5h", five_used), fmt("7d", week_used)]
    line = f"quota {' '.join(parts)}"
    if icon:
        line = f"{icon} {line}"
    line += f" [{mode}]"

    print(line)


if __name__ == "__main__":
    main()
