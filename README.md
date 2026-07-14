<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo/cc-pacer-logo-dark.svg">
    <img src="logo/cc-pacer-logo.svg" alt="cc-pacer" width="150">
  </picture>
</p>

<h1 align="center">cc-pacer</h1>

<p align="center"><em>Know your pace before you hit the wall.</em></p>

<p align="center">
  <img src="logo/demo.svg" alt="cc-pacer statusline demo" width="700">
</p>

Configure your Claude Code statusline to show limits, cost, directory and git info


```
Fable 5 │ ✍️ 43% │ myrepo (main*) ↑2 │ ⏱ 42m · $1.23 │ +156/-23 │ ◑ medium │ 🎙● 🖥●

current ●●●○○○○○○○  34%→68% ⟳ 6:41pm · $2.10 🔥 $0.84/hr
weekly  ●●○○○○○○○○  18% ⟳ jul 17, 9:00am · $14.32
month   $52.80 api-equiv · today $4.15
```

What you get, no configuration needed:

- **Line 1** — model, context %, directory + git branch (`*` = dirty, `↑n↓n` = commits ahead/behind upstream, `⚡` = `--dangerously-skip-permissions`), session duration + session cost, lines added/removed, reasoning effort, and two toggles: 🎙 voice mode and 🖥 remote control (green = on).
- **Meters** — your official 5-hour and weekly rate-limit windows with reset times, each annotated with what that usage would have cost on the API. The percentage is colored by your projected end-of-window usage (`→68%`) so being ahead of pace flags early. `🔥 $/hr` is your burn rate over the current 5-hour block.
- **month** — your calendar-month API-equivalent spend and today's total. An extra-usage meter appears too when that data is available (it comes from the usage API fallback below).

### Beyond the basics

- **Pace projection** — meters aren't colored by raw usage but by where you're *projected* to land at the window reset (`67%→120%`), so you get an early warning while there's still time to ease off.
- **Reasoning-effort dial** — a glyph that tracks your current effort level: `●` high/max (magenta), `◑` medium, `◔` low.
- **Commits ahead/behind** — `↑n↓n` against your branch's upstream, so you see unpushed/unpulled work at a glance.
- **Burn rate** — `🔥 $/hr` measured over the live 5-hour block (against wall-clock now, not the last transcript entry).
- **Extra-usage meter** — appears automatically when your account has extra usage enabled, showing utilization and credit spend.
- **Accurate pricing** — per-model rates including legacy Opus billing ($15/$75) and cache-read/write tiers, so the API-equivalent estimate reflects what you'd actually be charged.
- **Graceful under failure** — malformed stdin degrades to sane defaults instead of blanking; a failed usage-API call backs off and shows a compact hint (`⚠ auth`, `⚠ 429 rate limited`) rather than silently disappearing.
- **Portable & private** — honors `CLAUDE_CONFIG_DIR`, caches to a per-user `0700` dir, and passes your OAuth token to `curl` via stdin (never argv).

Costs are estimates computed locally from your transcripts (tokens × current API pricing, cached for 60s). When Claude Code doesn't provide rate-limit data on stdin (older versions), the script falls back to fetching it from Anthropic's usage API using your existing Claude Code credentials — that is the only network request it ever makes. Requires `jq` (see below).

## Install

```bash
npx cc-pacer
```

It backups your old status line if any and copies the status line script to `~/.claude/cc-pacer.sh` and configures your Claude Code settings.

## Requirements

- [jq](https://jqlang.github.io/jq/) — for parsing JSON
- curl — for fetching rate limit data
- git — for branch info

On macOS:

```bash
brew install jq
```

## Uninstall

```bash
node bin/install.js --uninstall
```

If you had a previous statusline, it restores it from the backup. Otherwise it removes the script and cleans up your settings.

## License

MIT
