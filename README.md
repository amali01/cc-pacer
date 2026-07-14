<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo/cc-pacer-logo-dark.svg">
    <img src="logo/cc-pacer-logo.svg" alt="cc-pacer" width="140">
  </picture>
</p>

<h1 align="center">cc-pacer</h1>

<p align="center"><em>Know your pace before you hit the wall.</em></p>

<p align="center">
  <img src="logo/demo.svg" alt="cc-pacer statusline demo" width="720">
</p>

<p align="center">
A zero-config statusline for Claude Code — rate-limit windows, pace projection,<br>
and API-equivalent cost, all at a glance.
</p>

## Install

```bash
npx cc-pacer
```

Backs up any existing statusline, installs to `~/.claude/cc-pacer.sh`, and wires up your Claude Code settings. Restart Claude Code to see it.

## What it shows

```
Opus 4.8 │ ✍️ 43% │ myrepo (main*) ↑2 │ ⏱ 42m · $1.23 │ +156/-23 │ ◑ medium │ 🎙● 🖥●

current ●●●○○○○○○○  34%→68% ⟳ 6:41pm · $2.10 🔥 $0.84/hr
weekly  ●●○○○○○○○○  18%      ⟳ jul 17, 9:00am · $14.32
month   $52.80 api-equiv · today $4.15
```

- **Line 1** — model · context % · directory & git branch · session time & cost · lines ±  · reasoning effort · 🎙 voice and 🖥 remote toggles (green = on).
- **current / weekly** — your official 5-hour and weekly rate-limit windows, with reset time and API-equivalent cost.
- **month** — calendar-month API-equivalent spend and today's total.

Bars are colored by usage — 🟢 `<50%` · 🟠 `50–69%` · 🟡 `70–89%` · 🔴 `≥90%`. The `→` value projects where you'll land at the window reset, so being ahead of pace flags **before** you hit the wall.

<details>
<summary><b>More features</b></summary>

- **Pace projection** — meters flag by projected end-of-window usage (`67%→120%`), not just the raw number.
- **Reasoning-effort dial** — `●` high/max · `◑` medium · `◔` low.
- **Commits ahead/behind** — `↑n↓n` vs. your branch's upstream.
- **Burn rate** — `🔥 $/hr` over the live 5-hour block.
- **Extra-usage meter** — shows automatically when your account has extra usage enabled.
- **Accurate pricing** — per-model rates, including legacy Opus ($15/$75) and cache read/write tiers.
- **Graceful failures** — bad input falls back to defaults; a failed usage-API call backs off with a compact hint (`⚠ auth`, `⚠ 429`).
- **Portable & private** — honors `CLAUDE_CONFIG_DIR`, caches to a per-user `0700` dir, sends your OAuth token to `curl` via stdin (never argv).

</details>

Costs are estimated locally from your transcripts (tokens × current API pricing, cached 60s). On older Claude Code versions that don't send rate-limit data, it falls back to Anthropic's usage API using your existing credentials — the only network request it ever makes.

## Requirements

Needs `jq`, `curl`, and `git`. `curl` and `git` are preinstalled on most systems; install `jq` with:

| System | Command |
| --- | --- |
| macOS | `brew install jq` |
| Debian / Ubuntu | `sudo apt install jq` |
| Fedora / RHEL | `sudo dnf install jq` |
| Arch | `sudo pacman -S jq` |
| Windows | `winget install jqlang.jq` |

## Uninstall

```bash
npx cc-pacer --uninstall
```

Restores your previous statusline from backup, or removes the script and cleans up your settings.

## License

MIT
