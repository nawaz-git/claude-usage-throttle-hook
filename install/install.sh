#!/usr/bin/env bash
# claude-usage-throttle-hook installer for macOS and Linux
# Usage: curl -fsSL <url>/install.sh | bash
#    or: bash install.sh [--mode fast|medium|low]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$HOME/.claude/usage-throttle"
SETTINGS_FILE="$HOME/.claude/settings.json"
MODE="medium"

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: install.sh [--mode fast|medium|low]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ "$MODE" != "fast" && "$MODE" != "medium" && "$MODE" != "low" ]]; then
  echo "Error: mode must be fast, medium, or low"
  exit 1
fi

echo "==> Installing claude-usage-throttle-hook (mode=$MODE)"

# ---------- copy files ----------
mkdir -p "$INSTALL_DIR"/{hooks,statusline,skills/quota-aware}

cp "$REPO_DIR/statusline/quota_state.py"        "$INSTALL_DIR/statusline/quota_state.py"
cp "$REPO_DIR/hooks/user_prompt_submit.py"       "$INSTALL_DIR/hooks/user_prompt_submit.py"
cp "$REPO_DIR/hooks/pre_tool_use.py"             "$INSTALL_DIR/hooks/pre_tool_use.py"
cp "$REPO_DIR/hooks/session_start.py"            "$INSTALL_DIR/hooks/session_start.py"
cp "$REPO_DIR/hooks/stop.py"                     "$INSTALL_DIR/hooks/stop.py"
cp "$REPO_DIR/skills/quota-aware/SKILL.md"       "$INSTALL_DIR/skills/quota-aware/SKILL.md"

chmod +x "$INSTALL_DIR/statusline/quota_state.py"
chmod +x "$INSTALL_DIR/hooks/"*.py

echo "==> Files installed to $INSTALL_DIR"

# ---------- write config ----------
cat > "$INSTALL_DIR/config.json" <<EOF
{
  "mode": "$MODE"
}
EOF
echo "==> Config written (mode=$MODE)"

# ---------- merge into settings.json ----------
PYTHON_CMD=""
if command -v python3 &>/dev/null; then
  PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
  PYTHON_CMD="python"
else
  echo "Error: Python 3 is required but not found in PATH"
  exit 1
fi

$PYTHON_CMD - "$SETTINGS_FILE" "$INSTALL_DIR" <<'PYEOF'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
install_dir = sys.argv[2]

settings = {}
if settings_path.exists():
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
    except Exception:
        settings = {}

# --- statusLine ---
settings["statusLine"] = {
    "type": "command",
    "command": f"python3 {install_dir}/statusline/quota_state.py",
    "refreshInterval": 10,
}

# --- hooks ---
hooks = settings.setdefault("hooks", {})

# UserPromptSubmit
ups_list = hooks.setdefault("UserPromptSubmit", [])
ups_entry = {
    "matcher": "",
    "hooks": [
        {
            "type": "command",
            "command": f"python3 {install_dir}/hooks/user_prompt_submit.py",
        }
    ],
}
# Remove any existing usage-throttle entries
ups_list[:] = [
    e for e in ups_list
    if not any("usage-throttle" in h.get("command", "") for h in e.get("hooks", []))
]
ups_list.append(ups_entry)

# PreToolUse
ptu_list = hooks.setdefault("PreToolUse", [])
ptu_entry = {
    "matcher": "Agent|WebSearch|WebFetch",
    "hooks": [
        {
            "type": "command",
            "command": f"python3 {install_dir}/hooks/pre_tool_use.py",
        }
    ],
}
ptu_list[:] = [
    e for e in ptu_list
    if not any("usage-throttle" in h.get("command", "") for h in e.get("hooks", []))
]
ptu_list.append(ptu_entry)

# SessionStart
ss_list = hooks.setdefault("SessionStart", [])
ss_entry = {
    "matcher": "",
    "hooks": [
        {
            "type": "command",
            "command": f"python3 {install_dir}/hooks/session_start.py",
        }
    ],
}
ss_list[:] = [
    e for e in ss_list
    if not any("usage-throttle" in h.get("command", "") for h in e.get("hooks", []))
]
ss_list.append(ss_entry)

# Stop
stop_list = hooks.setdefault("Stop", [])
stop_entry = {
    "matcher": "",
    "hooks": [
        {
            "type": "command",
            "command": f"python3 {install_dir}/hooks/stop.py",
        }
    ],
}
stop_list[:] = [
    e for e in stop_list
    if not any("usage-throttle" in h.get("command", "") for h in e.get("hooks", []))
]
stop_list.append(stop_entry)

settings_path.parent.mkdir(parents=True, exist_ok=True)
settings_path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
print(f"==> Updated {settings_path}")
PYEOF

echo ""
echo "==> claude-usage-throttle-hook installed successfully!"
echo ""
echo "  Status line:  quota 5h:--% 7d:--% [${MODE}]"
echo "  Hooks:        UserPromptSubmit, PreToolUse, SessionStart, Stop"
echo "  Config:       $INSTALL_DIR/config.json"
echo "  Skill:        /usage-throttle (in Claude Code)"
echo ""
echo "  Change mode:  echo '{\"mode\": \"low\"}' > $INSTALL_DIR/config.json"
echo ""
echo "  Start a new Claude Code session for changes to take effect."
