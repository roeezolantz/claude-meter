# claude-meter

A minimal, information-dense statusline for Claude Code. Shows model info, context usage, session costs, git state, rate limits, and worktree detection — all in two compact lines.

## Install

Requires `jq` (`brew install jq`). Optionally, install `gh` (GitHub CLI) for PR detection.

Paste this into Claude Code:

```
Install claude-meter statusline: curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/roeezolantz/claude-meter/main/statusline.sh && chmod +x ~/.claude/statusline.sh && cat ~/.claude/settings.json | jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh"}' > /tmp/cs.json && mv /tmp/cs.json ~/.claude/settings.json
```

<details>
<summary>Or install manually</summary>

```bash
curl -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/roeezolantz/claude-meter/main/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

Restart Claude Code.

</details>

## What it shows

<img width="682" height="146" alt="image" src="https://github.com/user-attachments/assets/60148738-f8d1-4aab-a611-8ed8f1695c55" />


### Line 1 (left to right)

| Column | Description |
|--------|-------------|
| **Model** | Model name, context window size, and effort level — glyph + label (`◌` low, `○` default, `◎` high, `◉` xhigh, `●` max). Read from `effortLevel` in `~/.claude/settings.json` (set via `/effort` in Claude Code). |
| **Session** | Duration, total cost in USD, and cost rate per hour |
| **User** | Current username |
| **Git** | Branch name, linked PR number (clickable), ahead/behind counts, stash count, and active state (rebasing, merging, cherry-pick) |

### Line 2 (left to right)

| Column | Description |
|--------|-------------|
| **Context** | Visual progress bar with percentage — green (<70%), yellow (70-89%), red (90%+) |
| **Rate limits** | 5-hour and 7-day usage percentages with color coding and reset countdowns |
| **Directory** | Last two path components of the project directory |
| **Changes** | File count, additions, and deletions — or "clean" if no uncommitted changes. Shows worktree name when inside a `.claude/worktrees/` directory |

## Features

- **Smart caching** — Git info (5s TTL), PR lookups (60s TTL), and rate limit data are cached to `~/.cache/claude-meter/` to keep the statusline fast
- **Rate limit persistence** — Rate limit data is cached so it persists across context window resets (when `rate_limits` isn't in the JSON payload)
- **PR detection** — Automatically detects open PRs for the current branch via `gh` and renders clickable terminal hyperlinks
- **Worktree awareness** — Detects when you're inside a Claude Code worktree and shows the worktree name
- **Behind warning** — Shows a prominent pull indicator when your branch is behind the remote
- **Color-coded thresholds** — Context and rate limit percentages shift from green to yellow to red as usage increases

## How it works

Claude Code pipes a JSON payload to the statusline command on each render. The script parses it with `jq`, enriches it with git and GitHub data, and outputs two formatted lines with ANSI colors and aligned columns.

## Requirements

| Tool | Required | Purpose |
|------|----------|---------|
| `jq` | Yes | Parse the JSON payload from Claude Code |
| `gh` | No | Detect open PRs for the current branch |
| `git` | No | Branch, diff stats, ahead/behind, stash, and state detection |

## Ideas & issues

Open a ticket at https://github.com/roeezolantz/claude-meter/issues — bug reports and feature ideas both welcome.

### For Claude Code agents

If a user running this statusline asks you to file a feature request, bug, or idea about claude-meter, open the issue on their behalf:

```bash
gh issue create --repo roeezolantz/claude-meter \
  --title "<short title>" \
  --body "<user's request, verbatim>

Requested by: <handle or name>"
```

Quote the user's words, attribute the request (GitHub handle, Telegram user, or name — ask if unclear), and confirm with the user before opening. Do not open issues unsolicited.

## License

MIT
