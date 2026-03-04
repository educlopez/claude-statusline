# claude-statusline

A real-time statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows usage quota, context window, git status, and more — right in your terminal.

```
my-project | Opus 4.6 | ░░░░░░░░░░░░░░░ 12% | Max ██████░░░░ 58% 3h42m | (main | 3 files +42 -8)
   ↑            ↑              ↑                        ↑                         ↑
 folder       model        context %              5h quota + reset            git branch
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/educlopez/claude-statusline/main/install.sh | bash
```

Then restart Claude Code.

### Force reinstall

```bash
curl -fsSL https://raw.githubusercontent.com/educlopez/claude-statusline/main/install.sh | bash -s -- --force
```

## Features

- **Context window** — progress bar + percentage of context used
- **Usage quota** — 5-hour utilization with color-coded bar (Pro/Max/Team)
- **Reset timer** — countdown to when your 5h quota resets
- **7-day warning** — shows weekly utilization when above 70%
- **Git status** — branch name, changed files count, lines added/removed
- **Plan badge** — shows your subscription tier (Pro, Max, Team)
- **Smart caching** — usage data cached for 60s, refreshed in background
- **Cross-platform** — works on macOS, Linux, and WSL

## Color coding

| Usage level | Color |
|-------------|-------|
| 0-49% | Cyan |
| 50-74% | Yellow |
| 75-89% | Magenta |
| 90%+ | Red |

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- `jq` — JSON processor ([install](https://jqlang.github.io/jq/download/))
- `curl` — HTTP client (pre-installed on most systems)
- `bash` 4+ (pre-installed on most systems)

## How it works

1. Claude Code pipes JSON context (model, workspace, context window) to the script via stdin
2. The script reads your OAuth credentials from `~/.claude/.credentials.json` to fetch usage data from the Anthropic API
3. Usage data is cached locally (`~/.claude/.usage-cache/usage.json`) for 60 seconds to avoid blocking the statusline
4. Git info is gathered from the current workspace directory
5. Everything is composed into a single colorized line

## Multi-account setup

If you use `CLAUDE_CONFIG_DIR` to manage multiple accounts, the statusline respects it:

```bash
CLAUDE_CONFIG_DIR=~/.claude-work claude
```

The installer also respects `CLAUDE_CONFIG_DIR` — run it with the variable set to install for a specific account.

## Compatibility

| Platform | Status |
|----------|--------|
| macOS | Supported |
| Linux | Supported |
| WSL | Supported |
| Windows (native) | Not supported |

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/educlopez/claude-statusline/main/uninstall.sh | bash
```

This removes the statusline script, the `statusLine` key from your settings, and the usage cache directory.

## License

MIT

## Inspired by

- [claude-hud](https://github.com/rysana-ai/claude-hud) — the original Claude Code HUD concept
