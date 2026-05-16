# claude-usage-throttle-hook installer for Windows
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1 [-Mode fast|medium|low]
param(
    [ValidateSet("fast", "medium", "low")]
    [string]$Mode = "medium"
)

$ErrorActionPreference = "Stop"

$RepoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path "$RepoDir/statusline/quota_state.py")) {
    $RepoDir = Split-Path -Parent $PSScriptRoot
}

$InstallDir = Join-Path $env:USERPROFILE ".claude\usage-throttle"
$SettingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"

Write-Host "==> Installing claude-usage-throttle-hook (mode=$Mode)"

# ---------- copy files ----------
$dirs = @(
    "$InstallDir\hooks",
    "$InstallDir\statusline",
    "$InstallDir\skills\quota-aware"
)
foreach ($d in $dirs) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

Copy-Item "$RepoDir\statusline\quota_state.py"    "$InstallDir\statusline\quota_state.py" -Force
Copy-Item "$RepoDir\hooks\user_prompt_submit.py"   "$InstallDir\hooks\user_prompt_submit.py" -Force
Copy-Item "$RepoDir\hooks\pre_tool_use.py"         "$InstallDir\hooks\pre_tool_use.py" -Force
Copy-Item "$RepoDir\hooks\session_start.py"        "$InstallDir\hooks\session_start.py" -Force
Copy-Item "$RepoDir\hooks\stop.py"                 "$InstallDir\hooks\stop.py" -Force
Copy-Item "$RepoDir\skills\quota-aware\SKILL.md"   "$InstallDir\skills\quota-aware\SKILL.md" -Force

Write-Host "==> Files installed to $InstallDir"

# ---------- write config ----------
$configJson = @{ mode = $Mode } | ConvertTo-Json
Set-Content -Path "$InstallDir\config.json" -Value $configJson -Encoding UTF8
Write-Host "==> Config written (mode=$Mode)"

# ---------- merge into settings.json ----------
$settings = @{}
if (Test-Path $SettingsFile) {
    try {
        $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        $settings = @{}
    }
}

$settings["statusLine"] = @{
    type = "command"
    command = "python3 $InstallDir\statusline\quota_state.py"
    refreshInterval = 10
}

if (-not $settings.ContainsKey("hooks")) { $settings["hooks"] = @{} }

function Set-HookEntry($hookName, $matcher, $scriptName) {
    if (-not $settings.hooks.ContainsKey($hookName)) {
        $settings.hooks[$hookName] = @()
    }
    $settings.hooks[$hookName] = @(
        $settings.hooks[$hookName] | Where-Object {
            $dominated = $false
            foreach ($h in $_.hooks) {
                if ($h.command -match "usage-throttle") { $dominated = $true }
            }
            -not $dominated
        }
    )
    $settings.hooks[$hookName] += @{
        matcher = $matcher
        hooks = @(
            @{
                type = "command"
                command = "python3 $InstallDir\hooks\$scriptName"
            }
        )
    }
}

Set-HookEntry "UserPromptSubmit" "" "user_prompt_submit.py"
Set-HookEntry "PreToolUse" "Agent|WebSearch|WebFetch" "pre_tool_use.py"
Set-HookEntry "SessionStart" "" "session_start.py"
Set-HookEntry "Stop" "" "stop.py"

$settingsJson = $settings | ConvertTo-Json -Depth 10
New-Item -ItemType Directory -Path (Split-Path $SettingsFile) -Force | Out-Null
Set-Content -Path $SettingsFile -Value $settingsJson -Encoding UTF8
Write-Host "==> Updated $SettingsFile"

Write-Host ""
Write-Host "==> claude-usage-throttle-hook installed successfully!"
Write-Host ""
Write-Host "  Config:  $InstallDir\config.json"
Write-Host "  Skill:   /usage-throttle (in Claude Code)"
Write-Host ""
Write-Host "  Change mode:  Set-Content '$InstallDir\config.json' '{`"mode`": `"low`"}'"
Write-Host ""
Write-Host "  Start a new Claude Code session for changes to take effect."
