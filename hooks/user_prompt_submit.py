#!/usr/bin/env python3
"""
UserPromptSubmit hook for claude-usage-throttle-hook.

Reads the persisted quota snapshot and injects a concise policy summary
into Claude's context via additionalContext. The policy adapts based on
the configured throttle mode (fast / medium / low).
"""

import json
import sys
from pathlib import Path

STATE_FILE = Path.home() / ".claude" / "usage-throttle" / "state.json"
CONFIG_FILE = Path.home() / ".claude" / "usage-throttle" / "config.json"

THRESHOLDS = {
    "fast": {
        "conserve_5h": 90, "critical_5h": 98,
        "conserve_7d": 95, "critical_7d": 99,
    },
    "medium": {
        "conserve_5h": 80, "critical_5h": 95,
        "conserve_7d": 85, "critical_7d": 95,
    },
    "low": {
        "conserve_5h": 50, "critical_5h": 75,
        "conserve_7d": 60, "critical_7d": 80,
    },
}

POLICIES = {
    "normal": "Normal mode.",
    "conserve": (
        "Conserve mode: prefer concise answers, avoid unnecessary subagents, "
        "avoid web tools unless clearly needed, batch related edits."
    ),
    "critical": (
        "Critical mode: no subagents, minimise tool use, prefer analysis and "
        "tiny edits only, do not spawn background agents."
    ),
}


def load_json(path):
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def resolve_mode(five, week, thresholds):
    if (five is not None and five >= thresholds["critical_5h"]) or \
       (week is not None and week >= thresholds["critical_7d"]):
        return "critical"
    if (five is not None and five >= thresholds["conserve_5h"]) or \
       (week is not None and week >= thresholds["conserve_7d"]):
        return "conserve"
    return "normal"


def main():
    state = load_json(STATE_FILE)
    config = load_json(CONFIG_FILE)

    throttle_mode = config.get("mode", "medium")
    t = THRESHOLDS.get(throttle_mode, THRESHOLDS["medium"])

    five = state.get("five_hour_used_pct")
    week = state.get("seven_day_used_pct")

    severity = resolve_mode(five, week, t)
    policy = POLICIES[severity]

    def fmt(label, key):
        v = state.get(key)
        return f"{label}={v:.0f}%" if isinstance(v, (int, float)) else f"{label}=--"

    summary = (
        f"Quota state: severity={severity}; "
        f"context_used={fmt('', 'context_used_pct').strip('=')}; "
        f"{fmt('five_hour', 'five_hour_used_pct')}; "
        f"{fmt('seven_day', 'seven_day_used_pct')}. "
        f"Throttle profile: {throttle_mode}. "
        f"{policy}"
    )

    output = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": summary,
        }
    }
    print(json.dumps(output))


if __name__ == "__main__":
    main()
