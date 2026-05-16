#!/usr/bin/env python3
"""
PreToolUse hook for claude-usage-throttle-hook.

Reads the persisted quota snapshot and deterministically denies expensive
tools (Agent, WebSearch, WebFetch) when quota thresholds are crossed.
Thresholds adapt based on the configured throttle mode.
"""

import json
import sys
from pathlib import Path

STATE_FILE = Path.home() / ".claude" / "usage-throttle" / "state.json"
CONFIG_FILE = Path.home() / ".claude" / "usage-throttle" / "config.json"

DENY_RULES = {
    "fast": [
        {"tools": ["Agent"], "five_min": 98, "week_min": 99},
    ],
    "medium": [
        {"tools": ["Agent"],                    "five_min": 95, "week_min": 95},
        {"tools": ["WebSearch", "WebFetch"],     "five_min": 95, "week_min": None},
    ],
    "low": [
        {"tools": ["Agent"],                    "five_min": 75, "week_min": 80},
        {"tools": ["WebSearch", "WebFetch"],     "five_min": 75, "week_min": 85},
    ],
}


def load_json(path):
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def check_threshold(value, minimum):
    if minimum is None:
        return False
    if value is None:
        return False
    return value >= minimum


def main():
    raw = sys.stdin.read() or "{}"
    try:
        event = json.loads(raw)
    except json.JSONDecodeError:
        event = {}

    tool_name = event.get("tool_name", "")

    state = load_json(STATE_FILE)
    config = load_json(CONFIG_FILE)

    throttle_mode = config.get("mode", "medium")
    rules = DENY_RULES.get(throttle_mode, DENY_RULES["medium"])

    five = state.get("five_hour_used_pct")
    week = state.get("seven_day_used_pct")

    deny = False
    reason = None

    for rule in rules:
        if tool_name in rule["tools"]:
            five_hit = check_threshold(five, rule.get("five_min"))
            week_hit = check_threshold(week, rule.get("week_min"))
            if five_hit or week_hit:
                deny = True
                parts = []
                if five is not None:
                    parts.append(f"five_hour={five:.0f}%")
                if week is not None:
                    parts.append(f"seven_day={week:.0f}%")
                reason = (
                    f"Quota guard denied {tool_name} "
                    f"({', '.join(parts)}, mode={throttle_mode})."
                )
                break

    if deny:
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
                "additionalContext": reason,
            }
        }
    else:
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": "Quota guard allows this tool.",
            }
        }

    print(json.dumps(output))


if __name__ == "__main__":
    main()
