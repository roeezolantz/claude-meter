# claude-meter

A minimal statusline for Claude Code. Shows model, context usage, git info, and rate limits with pace tracking.

## Install

Requires `jq` (`brew install jq`).

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

## What it shows

```
Opus 4.6 (1M) ○ | my-project (main) 3f +24 -7
██████░░░░ 60% 1M | 5h 40% ⇣10% 2h  7d 25% ⇣5% 4d
```

- **Line 1:** Model, effort level, project, branch, git diff stats
- **Line 2:** Context bar, rate limit usage with pace delta and reset countdown

Pace arrows: `⇣` = under budget (good), `⇡` = over budget (slow down).

## License

MIT
