---
name: usage-throttle
description: >
  Show current Claude Code quota usage (5-hour and 7-day windows) and switch
  throttle profiles (fast / medium / low). Use when the user asks about quota,
  usage limits, remaining capacity, or wants to change their throttle mode for
  overnight builds or long sessions. Can also bootstrap the full hook system.
when_to_use: >
  When the user mentions quota, usage limits, rate limits, throttling, session
  budget, overnight mode, or asks how much capacity is left.
argument-hint: "[fast|medium|low|status|setup]"
allowed-tools: Bash, Write, Read
---

## Hook installation check

```!
if [ -f ~/.claude/usage-throttle/hooks/user_prompt_submit.py ]; then
  echo "HOOKS_INSTALLED=true"
else
  echo "HOOKS_INSTALLED=false"
fi
```

## Live quota snapshot

```!
cat ~/.claude/usage-throttle/state.json 2>/dev/null || echo '{"note": "No quota data yet. The statusline needs to run at least once. If hooks are not installed, run /usage-throttle setup"}'
```

## Current config

```!
cat ~/.claude/usage-throttle/config.json 2>/dev/null || echo '{"mode": "medium"}'
```

## Instructions

You are the usage-throttle assistant. Based on the live snapshot above, help the
user understand their current Claude Code quota usage and manage their throttle
profile.

### If hooks are not installed (HOOKS_INSTALLED=false) or user asked for "setup"

The full usage-throttle hook system needs to be installed. Run the setup script:
```bash
bash "${CLAUDE_SKILL_DIR}/setup.sh" medium
```
Replace `medium` with `fast` or `low` if the user specified a different mode.
After installation, tell the user to restart Claude Code for hooks to take effect.

### If the user asked for status (or no argument)

Report the current state concisely:
- Five-hour window usage and when it resets
- Seven-day window usage and when it resets
- Current throttle mode and what it means
- Whether any tool restrictions are active right now

### If the user asked to change mode

The user can switch between three throttle profiles. Update the config file at
`~/.claude/usage-throttle/config.json` by writing the new mode:

- **fast** - Minimal restrictions. Only blocks tools at >98% (5h) or >99% (7d).
  Best for quick tasks where speed matters more than conservation.
- **medium** (default) - Balanced. Conserves at >80% (5h) / >85% (7d), blocks
  subagents and web tools at >95%. Good for normal daily work.
- **low** - Aggressive conservation. Conserves at >50% (5h) / >60% (7d), blocks
  subagents at >75% and web tools at >80%. Best for overnight builds and long
  unattended sessions.

To change the mode, write the config file:
```bash
echo '{"mode": "TARGET_MODE"}' > ~/.claude/usage-throttle/config.json
```

Then confirm the change to the user.

### Threshold reference

| Mode   | Conserve (5h/7d) | Critical (5h/7d) | Agent blocked | Web blocked |
|--------|-------------------|-------------------|---------------|-------------|
| fast   | 90% / 95%         | 98% / 99%         | >98% 5h       | never       |
| medium | 80% / 85%         | 95% / 95%         | >95% 5h       | >95% 5h    |
| low    | 50% / 60%         | 75% / 80%         | >75% 5h       | >75% 5h    |

### Conserve vs Critical behavior

- **Conserve**: Claude prefers concise answers, avoids unnecessary subagents,
  avoids web tools unless clearly needed, batches related edits.
- **Critical**: Claude uses no subagents, minimises tool use, prefers analysis
  and tiny edits only, does not spawn background agents.
