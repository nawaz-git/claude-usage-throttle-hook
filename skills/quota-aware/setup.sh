#!/usr/bin/env bash
# Bootstrap script for usage-throttle hooks.
# Called from the skill to install the full hook + statusline system.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.claude/usage-throttle"
SETTINGS_FILE="$HOME/.claude/settings.json"
MODE="${1:-medium}"

if [[ "$MODE" != "fast" && "$MODE" != "medium" && "$MODE" != "low" ]]; then
  MODE="medium"
fi

echo "Installing usage-throttle hooks (mode=$MODE)..."

mkdir -p "$INSTALL_DIR"/{hooks,statusline}

# Write hook scripts inline (self-contained, no external dependencies)
cat > "$INSTALL_DIR/statusline/quota_state.py" << 'STATUSLINE_EOF'
#!/usr/bin/env python3
import json, sys, time
from pathlib import Path

STATE_DIR = Path.home() / ".claude" / "usage-throttle"
STATE_FILE = STATE_DIR / "state.json"
CONFIG_FILE = STATE_DIR / "config.json"

def pct(v):
    if v is None: return None
    try: return round(float(v), 1)
    except: return None

def main():
    raw = sys.stdin.read() or "{}"
    try: data = json.loads(raw)
    except: data = {}
    ctx = data.get("context_window", {}) or {}
    lim = data.get("rate_limits", {}) or {}
    fh = (lim.get("five_hour") or {})
    sd = (lim.get("seven_day") or {})
    five_used, week_used = pct(fh.get("used_percentage")), pct(sd.get("used_percentage"))
    snapshot = {
        "session_id": data.get("session_id"),
        "context_used_pct": pct(ctx.get("used_percentage")),
        "context_remaining_pct": pct(ctx.get("remaining_percentage")),
        "five_hour_used_pct": five_used,
        "five_hour_resets_at": fh.get("resets_at"),
        "seven_day_used_pct": week_used,
        "seven_day_resets_at": sd.get("resets_at"),
        "updated_at": time.time(),
    }
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(snapshot, indent=2), encoding="utf-8")
    config = {}
    if CONFIG_FILE.exists():
        try: config = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        except: pass
    mode = config.get("mode", "medium")
    t = {"fast":(90,98,95,99),"medium":(80,95,85,95),"low":(50,75,60,80)}.get(mode,(80,95,85,95))
    icon = ""
    if (five_used is not None and five_used >= t[1]) or (week_used is not None and week_used >= t[3]): icon = "!! "
    elif (five_used is not None and five_used >= t[0]) or (week_used is not None and week_used >= t[2]): icon = "! "
    f5 = f"5h:{five_used:.0f}%" if isinstance(five_used,(int,float)) else "5h:--"
    f7 = f"7d:{week_used:.0f}%" if isinstance(week_used,(int,float)) else "7d:--"
    print(f"{icon}quota {f5} {f7} [{mode}]")

if __name__ == "__main__": main()
STATUSLINE_EOF

cat > "$INSTALL_DIR/hooks/user_prompt_submit.py" << 'UPS_EOF'
#!/usr/bin/env python3
import json
from pathlib import Path

STATE_FILE = Path.home() / ".claude" / "usage-throttle" / "state.json"
CONFIG_FILE = Path.home() / ".claude" / "usage-throttle" / "config.json"
THRESHOLDS = {"fast":{"c5":90,"x5":98,"c7":95,"x7":99},"medium":{"c5":80,"x5":95,"c7":85,"x7":95},"low":{"c5":50,"x5":75,"c7":60,"x7":80}}
POLICIES = {"normal":"Normal mode.","conserve":"Conserve mode: prefer concise answers, avoid unnecessary subagents, avoid web tools unless clearly needed, batch related edits.","critical":"Critical mode: no subagents, minimise tool use, prefer analysis and tiny edits only, do not spawn background agents."}

def load(p):
    if not p.exists(): return {}
    try: return json.loads(p.read_text(encoding="utf-8"))
    except: return {}

state = load(STATE_FILE)
config = load(CONFIG_FILE)
mode = config.get("mode", "medium")
t = THRESHOLDS.get(mode, THRESHOLDS["medium"])
five = state.get("five_hour_used_pct")
week = state.get("seven_day_used_pct")
sev = "critical" if (five is not None and five >= t["x5"]) or (week is not None and week >= t["x7"]) else "conserve" if (five is not None and five >= t["c5"]) or (week is not None and week >= t["c7"]) else "normal"
def f(l,k):
    v=state.get(k)
    return f"{l}={v:.0f}%" if isinstance(v,(int,float)) else f"{l}=--"
summary = f"Quota state: severity={sev}; {f('context','context_used_pct')}; {f('five_hour','five_hour_used_pct')}; {f('seven_day','seven_day_used_pct')}. Throttle: {mode}. {POLICIES[sev]}"
print(json.dumps({"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":summary}}))
UPS_EOF

cat > "$INSTALL_DIR/hooks/pre_tool_use.py" << 'PTU_EOF'
#!/usr/bin/env python3
import json, sys
from pathlib import Path

STATE_FILE = Path.home() / ".claude" / "usage-throttle" / "state.json"
CONFIG_FILE = Path.home() / ".claude" / "usage-throttle" / "config.json"
RULES = {"fast":[{"t":["Agent"],"f":98,"w":99}],"medium":[{"t":["Agent"],"f":95,"w":95},{"t":["WebSearch","WebFetch"],"f":95,"w":None}],"low":[{"t":["Agent"],"f":75,"w":80},{"t":["WebSearch","WebFetch"],"f":75,"w":85}]}

def load(p):
    if not p.exists(): return {}
    try: return json.loads(p.read_text(encoding="utf-8"))
    except: return {}

raw = sys.stdin.read() or "{}"
try: event = json.loads(raw)
except: event = {}
tool = event.get("tool_name","")
state = load(STATE_FILE)
config = load(CONFIG_FILE)
mode = config.get("mode","medium")
rules = RULES.get(mode, RULES["medium"])
five = state.get("five_hour_used_pct")
week = state.get("seven_day_used_pct")
deny = False
reason = None
for r in rules:
    if tool in r["t"]:
        fh = r.get("f"); wk = r.get("w")
        if (fh is not None and five is not None and five >= fh) or (wk is not None and week is not None and week >= wk):
            deny = True
            parts = []
            if five is not None: parts.append(f"five_hour={five:.0f}%")
            if week is not None: parts.append(f"seven_day={week:.0f}%")
            reason = f"Quota guard denied {tool} ({', '.join(parts)}, mode={mode})."
            break
if deny:
    print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":reason,"additionalContext":reason}}))
else:
    print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Quota guard allows this tool."}}))
PTU_EOF

cat > "$INSTALL_DIR/hooks/session_start.py" << 'SS_EOF'
#!/usr/bin/env python3
import json
from pathlib import Path

STATE_FILE = Path.home() / ".claude" / "usage-throttle" / "state.json"
CONFIG_FILE = Path.home() / ".claude" / "usage-throttle" / "config.json"

def load(p):
    if not p.exists(): return {}
    try: return json.loads(p.read_text(encoding="utf-8"))
    except: return {}

state = load(STATE_FILE)
config = load(CONFIG_FILE)
mode = config.get("mode","medium")
five = state.get("five_hour_used_pct")
week = state.get("seven_day_used_pct")
f5 = f"5h={five:.0f}%" if isinstance(five,(int,float)) else "5h=--"
f7 = f"7d={week:.0f}%" if isinstance(week,(int,float)) else "7d=--"
print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":f"[usage-throttle] {f5} {f7} mode={mode}. Quota guard is active and will inject policy per prompt."}}))
SS_EOF

chmod +x "$INSTALL_DIR/statusline/quota_state.py"
chmod +x "$INSTALL_DIR/hooks/"*.py

# Write config
cat > "$INSTALL_DIR/config.json" << EOF
{"mode": "$MODE"}
EOF

# Merge into settings.json
python3 - "$SETTINGS_FILE" "$INSTALL_DIR" << 'PYEOF'
import json, sys
from pathlib import Path

sp = Path(sys.argv[1])
d = sys.argv[2]
s = {}
if sp.exists():
    try: s = json.loads(sp.read_text(encoding="utf-8"))
    except: s = {}
s["statusLine"] = {"type":"command","command":f"python3 {d}/statusline/quota_state.py","refreshInterval":10}
h = s.setdefault("hooks", {})
for name, matcher, script in [
    ("UserPromptSubmit", "", "user_prompt_submit.py"),
    ("PreToolUse", "Agent|WebSearch|WebFetch", "pre_tool_use.py"),
    ("SessionStart", "", "session_start.py"),
]:
    lst = h.setdefault(name, [])
    lst[:] = [e for e in lst if not any("usage-throttle" in x.get("command","") for x in e.get("hooks",[]))]
    lst.append({"matcher":matcher,"hooks":[{"type":"command","command":f"python3 {d}/hooks/{script}"}]})
sp.parent.mkdir(parents=True, exist_ok=True)
sp.write_text(json.dumps(s, indent=2) + "\n", encoding="utf-8")
PYEOF

echo "Done! Hooks installed. Restart Claude Code for changes to take effect."
