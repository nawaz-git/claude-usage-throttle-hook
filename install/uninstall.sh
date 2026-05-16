#!/usr/bin/env bash
# claude-usage-throttle-hook uninstaller for macOS and Linux
set -euo pipefail

INSTALL_DIR="$HOME/.claude/usage-throttle"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "==> Uninstalling claude-usage-throttle-hook"

PYTHON_CMD=""
if command -v python3 &>/dev/null; then
  PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
  PYTHON_CMD="python"
fi

if [[ -n "$PYTHON_CMD" && -f "$SETTINGS_FILE" ]]; then
  $PYTHON_CMD - "$SETTINGS_FILE" <<'PYEOF'
import json, sys
from pathlib import Path

p = Path(sys.argv[1])
if not p.exists():
    sys.exit(0)
s = json.loads(p.read_text(encoding="utf-8"))

if "statusLine" in s:
    cmd = s["statusLine"].get("command", "")
    if "usage-throttle" in cmd:
        del s["statusLine"]

for hook_name in ["UserPromptSubmit", "PreToolUse", "SessionStart", "Stop"]:
    entries = s.get("hooks", {}).get(hook_name, [])
    s.setdefault("hooks", {})[hook_name] = [
        e for e in entries
        if not any("usage-throttle" in h.get("command", "") for h in e.get("hooks", []))
    ]
    if not s["hooks"][hook_name]:
        del s["hooks"][hook_name]

if not s.get("hooks"):
    s.pop("hooks", None)

p.write_text(json.dumps(s, indent=2) + "\n", encoding="utf-8")
print(f"==> Cleaned {p}")
PYEOF
fi

if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
  echo "==> Removed $INSTALL_DIR"
fi

echo "==> claude-usage-throttle-hook uninstalled."
echo "    Start a new Claude Code session for changes to take effect."
