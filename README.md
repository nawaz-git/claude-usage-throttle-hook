# claude-usage-throttle-hook

Session-aware quota throttling for Claude Code. Makes Claude aware of its own 5-hour and 7-day usage limits so it can self-regulate during long sessions and overnight builds.

## The problem

Claude Code has usage quotas (5-hour rolling window and 7-day rolling window) but the model itself is completely blind to them. It will happily spawn subagents and burn through your quota at full speed, then hit a wall mid-task. This project fixes that.

## How it works

Three layers working together:

1. **Statusline writer** -- reads the official `statusLine` JSON, persists a quota snapshot to disk, and shows live usage in the terminal status bar
2. **Hook policy engine** -- injects quota context into every prompt (`UserPromptSubmit`) and deterministically blocks expensive tools like `Agent`, `WebSearch`, and `WebFetch` when thresholds are crossed (`PreToolUse`)
3. **Skill** -- on-demand `/usage-throttle` command to check status or switch modes

```
Official statusLine JSON --> quota_state.py --> ~/.claude/usage-throttle/state.json
                                                         |
                          UserPromptSubmit hook <--------|
                          (injects quota context)        |
                                                         |
                          PreToolUse hook <--------------+
                          (denies Agent/WebSearch/WebFetch)
```

No proxy. No external dependencies. Just Python 3.8+ and Claude Code's official APIs.

## Three throttle modes

| Mode | Use case | Conserve at (5h/7d) | Block tools at (5h/7d) |
|------|----------|---------------------|------------------------|
| **fast** | Quick tasks, speed over conservation | 90% / 95% | 98% / 99% |
| **medium** | Normal daily work (default) | 80% / 85% | 95% / 95% |
| **low** | Overnight builds, long sessions | 50% / 60% | 75% / 80% |

- **Conserve**: Claude prefers concise answers, avoids unnecessary subagents, avoids web tools unless clearly needed, batches related edits
- **Critical**: Claude uses no subagents, minimizes tool use, prefers analysis and tiny edits only

## Install

### Option 1: skills.sh (recommended)

```bash
npx skills add nawaz-git/claude-usage-throttle-hook
```

Then in Claude Code, run `/usage-throttle setup` to bootstrap the full hook system.

### Option 2: macOS / Linux

```bash
git clone https://github.com/nawaz-git/claude-usage-throttle-hook.git
cd claude-usage-throttle-hook
bash install/install.sh --mode medium
```

### Option 3: Windows (PowerShell)

```powershell
git clone https://github.com/nawaz-git/claude-usage-throttle-hook.git
cd claude-usage-throttle-hook
powershell -ExecutionPolicy Bypass -File install\install.ps1 -Mode medium
```

The installer copies scripts to `~/.claude/usage-throttle/` and merges the required `statusLine` and `hooks` entries into your `~/.claude/settings.json`. Start a new Claude Code session for changes to take effect.

## Usage

### Status bar

After installation, your Claude Code status bar shows:

```
quota 5h:42% 7d:18% [medium]
```

With severity indicators when approaching limits:

```
!  quota 5h:82% 7d:45% [medium]    <-- conserve mode active
!! quota 5h:96% 7d:72% [medium]    <-- critical, tools blocked
```

### Skill (inside Claude Code)

```
/usage-throttle          # show current quota status
/usage-throttle status   # same as above
/usage-throttle low      # switch to low (overnight) mode
/usage-throttle fast     # switch to fast mode
/usage-throttle setup    # install/reinstall hooks
```

### CLI (from terminal)

```bash
python3 ~/.claude/usage-throttle/usage-throttle status
python3 ~/.claude/usage-throttle/usage-throttle mode low
python3 ~/.claude/usage-throttle/usage-throttle history
python3 ~/.claude/usage-throttle/usage-throttle reset
```

## What gets installed

```
~/.claude/usage-throttle/
|-- config.json              # {"mode": "fast|medium|low"}
|-- state.json               # latest quota snapshot (auto-updated)
|-- history.jsonl            # turn-by-turn usage log
|-- statusline/
|   +-- quota_state.py       # statusline writer
|-- hooks/
|   |-- user_prompt_submit.py
|   |-- pre_tool_use.py
|   |-- session_start.py
|   +-- stop.py
+-- skills/
    +-- quota-aware/
        +-- SKILL.md
```

### settings.json entries

The installer adds these to your `~/.claude/settings.json`:

- `statusLine` -- runs `quota_state.py` every 10 seconds
- `hooks.UserPromptSubmit` -- injects quota policy into every prompt
- `hooks.PreToolUse` -- gates `Agent|WebSearch|WebFetch`
- `hooks.SessionStart` -- injects initial quota awareness
- `hooks.Stop` -- logs usage per turn

## Policy enforcement details

### Truth source

The official Claude Code `statusLine` JSON provides authoritative `rate_limits.five_hour.used_percentage` and `rate_limits.seven_day.used_percentage` fields. This is your real subscription usage, not a local estimate.

### Soft vs hard enforcement

- **Soft (UserPromptSubmit)**: Injects a policy directive like "Conserve mode: prefer concise answers, avoid unnecessary subagents." Claude sees this and adapts its behavior.
- **Hard (PreToolUse)**: Returns `permissionDecision: "deny"` for specific tools. This is a deterministic gate -- Claude cannot override it.

### Why not a proxy?

A local HTTP proxy can capture richer headers but adds operational complexity, sits in the trust path between Claude Code and Anthropic's API, and has had security issues in existing implementations. The statusline approach gives you the same authoritative percentages without a proxy.

## Uninstall

```bash
bash install/uninstall.sh
```

This removes `~/.claude/usage-throttle/` and cleans all hook entries from `settings.json`.

## Requirements

- Python 3.8+
- Claude Code v2.1.80+ (for `rate_limits` in statusLine JSON)
- Claude.ai Pro, Max, or Team subscription (for `rate_limits` data)

## License

MIT
