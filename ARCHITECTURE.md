# Architecture

Developer reference for understanding, extending, and replicating the system.

> **GitHub:** [github.com/dannyjkk/Watchtower](https://github.com/dannyjkk/Watchtower)

---

## System Overview

```
┌─────────────────────────────────────────────────────┐
│                     Telegram                         │
│            (messages, callbacks, media)               │
└────────────┬────────────────────────┬────────────────┘
             │                        │
   ┌─────────▼──────────┐   ┌────────▼──────────┐
   │   OpenClaw Gateway  │   │  House Tasks Chat  │
   │  (routes by chat ID)│   │  (group messages)  │
   └──┬────────┬─────────┘   └────────┬──────────┘
      │        │                      │
 ┌────▼──┐  ┌──▼───┐           ┌─────▼────┐
 │Kal-El │  │Jarvis│           │    Jo    │
 │ Opus  │  │Sonnet│           │ Ollama   │
 └───┬───┘  └──┬───┘           └────┬─────┘
     │         │                    │
     │    ┌────▼──────────┐   ┌────▼───────────┐
     │    │Home Assistant │   │  Task Files    │
     │    │  (MCP tools)  │   │  (JSON on disk)│
     │    └────┬──────────┘   └────────────────┘
     │         │
┌────▼───┐  ┌──▼──────────────────────────────┐
│Web APIs│  │         HA Ecosystem             │
│Brave   │  │ Lights · Vacuum · AdGuard · NFC  │
│Tavily  │  │ Zones · Sensors · Power Mgmt     │
│Gmail   │  │ Tasker webhooks · Garmin sync     │
└────────┘  └──────────────────────────────────┘
```

---

## Repository Structure

```
~/.openclaw/                              # Repo root (on ubuntu-media VM)
│
├── README.md                             # Portfolio overview
├── ARCHITECTURE.md                       # This file
├── openclaw.json                         # Central config (credentials via ${VAR})
├── .env.example                          # Env var template for replication
├── .gitignore                            # Production gitignore (100+ rules)
├── pre-commit-hook.sh                    # Auto-scrub + secret scan hook
│
├── docs/                                 # Reference docs + screenshots
│   ├── images/                           # Dashboard screenshots (for README)
│   ├── JARVIS_CLAUDE_CONTRACT.md         # Agent behavior contract & boundaries
│   ├── Jarvis_Habits_Handoff.md          # Full habit system handoff document
│   ├── Jarvis_Habits_Cheatsheet.md       # Quick reference card
│   ├── OpenClaw_HA_Routing_Guide.md      # Message routing patterns
│   └── Doc_Update_Triggers.md            # When/how to update docs
│
├── workspace/                            # Kal-El's workspace
│   ├── AGENTS.md                         # Inter-agent instructions
│   ├── IDENTITY.md                       # Name, role, emoji
│   ├── TOOLS.md                          # Env-specific notes (media delivery)
│   ├── HEARTBEAT.md                      # Periodic check config (empty)
│   ├── docs-index.md                     # Doc navigation helper
│   ├── SOUL.md                           # ⛔ gitignored (personal persona)
│   └── USER.md                           # ⛔ gitignored (PII)
│
├── workspace-jarvis/                     # Jarvis's workspace
│   ├── AGENTS.md                         # Habit system + HA instructions
│   ├── IDENTITY.md                       # Name, role, emoji
│   ├── TOOLS.md                          # HA connection, Google account ref
│   ├── HEARTBEAT.md                      # Uses cron, not heartbeats
│   ├── SOUL.md                           # Jarvis persona & behavior rules
│   ├── habits-commands.md                # Curl examples for HA API
│   ├── state/modules.json                # Capability module on/off toggles
│   ├── ha-token.txt                      # ⛔ gitignored (HA auth token)
│   └── USER.md                           # ⛔ gitignored (PII)
│
├── shared-house/                         # Jo's workspace
│   ├── AGENTS.md                         # Cron syntax, group chat rules
│   ├── IDENTITY.md                       # Name, role, emoji
│   ├── TOOLS.md                          # Template (mostly defaults)
│   ├── HEARTBEAT.md                      # Empty
│   ├── SOUL.md                           # Task management instructions
│   ├── House_Tasks_Schema.md             # JSON schema + integration guide
│   ├── house_tasks.json                  # ⛔ gitignored (runtime state)
│   ├── reminders.json                    # ⛔ gitignored (runtime state)
│   └── USER.md                           # ⛔ gitignored (PII)
│
├── ha/                                   # Home Assistant config (pulled via scp)
│   ├── .gitignore                        # HA-specific ignores
│   ├── configuration.yaml                # Sensors, rest_commands, templates
│   ├── automations.yaml                  # All automations (webhook IDs scrubbed)
│   ├── scripts.yaml                      # Eval, sync, exemption, vacuum scripts
│   └── dashboard-habit-tracker.json      # Lovelace dashboard (importable)
│
├── adguard/                              # AdGuard Home config (reference copy)
│   └── AdGuardHome.yaml                  # DNS, client definitions, general settings
```

### Gitignored Categories

| Category | Examples | Why |
|----------|---------|-----|
| Credentials | `.env`, `ha-token.txt`, `credentials/`, `identity/` | API keys, tokens, auth headers |
| Personal | `**/USER.md`, `workspace/SOUL.md` | Phone numbers, deep personal persona |
| Runtime dirs | `agents/`, `cron/`, `logs/`, `media/`, `memory/`, `telegram/`, + 10 more | Session data, conversation history, node_modules |
| Runtime state | `house_tasks.json`, `reminders.json`, `**/state/*.json` (partial) | Ephemeral daily state |
| Config backups | `openclaw.json.*` | Auto-backups may contain plaintext credentials |

---

## OpenClaw Configuration

### openclaw.json

The central config file defines agents, Telegram bindings, channels, and plugins. All credentials use `${VAR}` substitution — OpenClaw reads `.env` and replaces these at startup.

**Credential variables used:**
- `${TELEGRAM_BOT_KALEL}`, `${TELEGRAM_BOT_JARVIS}`, `${TELEGRAM_BOT_JO}` — Telegram bot tokens
- `${DANNY_CHAT_ID}` — user's Telegram chat ID (routing key)
- `${OPENCLAW_GATEWAY_TOKEN}` — gateway authentication
- `${BRAVE_API_KEY}`, `${TAVILY_API_KEY}` — web search APIs
- `${TAILSCALE_CONTROL_UI_URL}` — web UI origin (CORS)

**Limitation:** `${VAR}` substitution only works in JSON string **values**, not in JSON keys. This means group chat IDs used as routing keys must remain as literal numbers in the config.

### Agent Workspace Structure

Every agent workspace follows a standard layout:

| File | Purpose | Committed? |
|------|---------|-----------|
| `SOUL.md` | Persona, tone, behavioral rules | Varies (Kal-El's is gitignored) |
| `AGENTS.md` | How to interact with other agents and systems | Yes |
| `IDENTITY.md` | Name, role, emoji — used in some UI contexts | Yes |
| `TOOLS.md` | Environment-specific: URLs, paths, delivery targets | Yes |
| `USER.md` | Personal info about the user | No (gitignored) |
| `HEARTBEAT.md` | Periodic health check tasks (empty = disabled) | Yes |
| `memory/` | Agent conversation memory (SQLite) | No (gitignored) |

Agents read these from the filesystem at runtime. Gitignoring a file only affects version control — agents still access and use gitignored files normally.

---

## Home Assistant

### Configuration Patterns

HA config is split across three files, pulled from the HA instance via `scp -O` (the `-O` flag forces legacy SCP protocol because the HA SSH add-on doesn't support SFTP):

```bash
scp -O danny@192.168.0.124:/config/{configuration.yaml,automations.yaml,scripts.yaml} ~/.openclaw/ha/
```

| File | Contains | Credential Handling |
|------|---------|-------------------|
| `configuration.yaml` | Template sensors, rest_commands, frontend config | `!secret` references |
| `automations.yaml` | All automations (habits, power, lights, NFC, health) | Webhook IDs auto-scrubbed by pre-commit |
| `scripts.yaml` | Reusable sequences (eval, sync, exemption, vacuum) | Uses rest_commands (secrets in config) |

### Key Automations

| Automation | Trigger | Purpose |
|------------|---------|---------|
| **Phone Usage Bulk Update** | Webhook (~90s) | Receives per-app usage JSON from Tasker |
| **Late Phone Usage** | Webhook | Flags screen-on after 23:30 |
| **Gym Entry / Exit** | Zone state | GPS-based gym visit detection (≥20 min) |
| **Nightly Report** | Time (23:20) | Evaluates all habits, applies points, sends report |
| **Late Phone Demerit** | Time (23:35) | Applies -1 if late phone flag is set |
| **Punishment Enforcer** | Zone/exemption change | Syncs AdGuard rules to match current zone |
| **Screen Time Warnings** | Template (50/75/92/100%) | Progressive Telegram alerts |
| **Midnight Reset** | Time (00:00) | Clears daily flags, preserves points |
| **Health Watchdog** | 30 min interval | Alerts if Tasker or AdGuard sync goes stale |
| **Power Blip / Stable** | Router ping | Detect outages, suppress lights, save/restore state |
| **Power Weekly Report** | Sunday 21:00 | Telegram summary of power stability |
| **House Tasks Prompt** | Time (22:30) | Inline buttons for task confirmation |

### The Daily Eval — Pure Function Design

`script.jarvis_compute_daily_eval` is a **pure function**: it reads all habit state, computes scoring deltas, and returns a structured result via `response_variable`. It never writes state.

The calling automation (Nightly Report) receives the result and decides what to do: apply points, handle overflow/exemption math, log to the HA calendar, and send the Telegram report.

Why this matters:
- The eval can be tested in isolation without changing any state
- The exemption path and normal path share the same computation
- A bug in scoring logic never accidentally writes incorrect state
- You can call it manually: `ha_call_service('script', 'jarvis_compute_daily_eval', return_response=True)`

### AdGuard Sync — Single Source of Truth

`script.jarvis_sync_adguard_rules` is the sole script that pushes filtering rules to AdGuard. It reads:
1. The current demerit zone (from `sensor.demerit_zone`)
2. Whether today is an exemption day (from `input_boolean.exemption_today`)

It computes the effective zone (green if exempt, else the actual zone), builds the per-client rule set from inline domain lists, and pushes via AdGuard's API. This is called by:
- The Punishment Enforcer (on zone or exemption change)
- The Periodic Sync (every 15 min, as drift correction)

Domain tiers are defined as variables inside the script — edit them there to change what gets blocked:

```
yellow_domains  → youtube.com, ytimg.com, googlevideo.com, youtu.be,
                  instagram.com, cdninstagram.com, fbcdn.net
orange_additions → netflix.com, nflxvideo.net, nflxext.com,
                   primevideo.com, amazonvideo.com, aiv-cdn.net, aiv-delivery.net
red_additions    → hotstar.com, hotstarext.com, jiohotstar.com,
                   disneyplus.com, disney-plus.net, dssott.com
always_allow     → /whatsapp-cdn.*\.fbcdn\.net/  (carve-out for WhatsApp media)
```

Each zone cumulatively includes all lower zones' domains. AdGuard rules are formatted as `||domain^$client='<client_name>'` for blocks and `@@pattern$client='<client_name>'` for allow-list overrides.

**AdGuard's own config** (`adguard/AdGuardHome.yaml`) defines the installation-level settings: DNS upstream (Cloudflare DoH), bootstrap DNS (Quad9), persistent client definitions, and general options. Notably, AdGuard's default filter lists are **disabled** — all content filtering is done exclusively via the HA-pushed custom rules, keeping the HA script as the single source of truth.

---

## Telegram Routing

### Message Flow

```
Incoming Telegram message
    │
    ├── Private chat (matches Danny's chat ID)
    │   └── OpenClaw routes to Kal-El workspace
    │       └── Habit commands escalate to Jarvis
    │
    ├── House tasks group (matches group chat ID)
    │   └── OpenClaw routes to Jo workspace
    │
    └── Inline button callback (e.g. "tasks_done")
        └── Mapped to HA script invocation
```

### Callback Routing

Telegram inline buttons use `callback_data` strings. OpenClaw maps these directly to script calls — pressing "Tasks Done" triggers `script.mark_tasks_done` in HA, which:
1. Checks if already done today (idempotent)
2. Flips `input_boolean.tasks_completed_today`
3. Sends Telegram confirmation

---

## Key Design Decisions

### Why DNS Blocking for Enforcement?

App-level screen time limits are trivially bypassed — uninstall the limiter, use a different browser, or just toggle it off in settings. DNS blocking via AdGuard operates at the network level:
- Affects every app, not just browsers
- Can't be bypassed without changing the phone's DNS settings
- Rules are pushed from the server, not enforced on the device
- The inconvenience of circumventing it IS the enforcement mechanism

### Why a Local LLM for Jo?

House task management is narrow and well-defined: parse natural language intent, read/write JSON files, send Telegram confirmations. A lightweight cloud model (Nemotron via Ollama's free tier) handles this comfortably. The tradeoffs:
- **Pro:** Zero cost — free tier is more than sufficient for this volume
- **Pro:** Any lightweight model works — not locked into a specific provider
- **Con:** Slightly less capable language understanding (irrelevant for this domain)

### Why Pure Function Eval?

The nightly evaluation could have been one monolithic automation. Splitting it into a pure function + caller automation gives:
- **Testability:** Run the eval without side effects
- **Reuse:** Exemption-day and normal-day paths share computation
- **Safety:** A bug in scoring never corrupts state

### Why 3-Second Router Pinging?

HA's default ping integration polls every 30 seconds — too slow to catch brief power blips (common in Indian power grid cycling). 3-second polling catches blips reliably. The automation tracks each individual blip within an event, handles the common rapid on-off-on-off pattern, and only declares "stable" after 30 continuous seconds of router uptime.

---

## Extending the System

### Adding a New Tracked Habit

1. **Create HA helpers** — `input_boolean` or `input_number` for the raw state (e.g., `input_boolean.reading_done_today`)
2. **Read it in the eval** — add a `states()` call in `script.jarvis_compute_daily_eval`'s first variable block
3. **Compute the delta** — add scoring logic in the second variable block (e.g., `reading_delta: '{{ 1 if reading_done else -1 }}'`)
4. **Include in result** — add fields to the `eval_result` variable
5. **Apply in Nightly Report** — add an `input_number.set_value` call and include in the Telegram message template
6. **Reset at midnight** — add the helper to the Midnight Reset automation
7. **Update docs** — `docs/Jarvis_Habits_Cheatsheet.md`

### Adding a New Agent

1. **Create a workspace** — `workspace-<name>/` with at minimum: `SOUL.md`, `AGENTS.md`, `IDENTITY.md`
2. **Get a Telegram bot** — create via @BotFather, add token to `.env` and `.env.example`
3. **Configure in openclaw.json** — add agent definition (model, workspace path, temperature) and channel binding (Telegram account, routing rules)
4. **Test** — send a message through Telegram, verify routing

### Adding a New HA Automation

1. **Create in HA UI** — HA generates a unique ID automatically
2. **Pull to repo** — `scp -O danny@<ha-ip>:/config/automations.yaml ~/.openclaw/ha/`
3. **Commit** — `git add ha/automations.yaml && git commit` — the pre-commit hook auto-scrubs webhook IDs and checks for leaked secrets
4. **If new webhooks** — add the real IDs to `.secret-replacements` (format: `real_id=<PLACEHOLDER>`)

---

## Setup Guide

For the full step-by-step replication guide, see **[SETUP.md](SETUP.md)**. It covers hardware requirements, Proxmox/VM setup, Home Assistant configuration (helpers, zones, template sensors, automations), AdGuard installation and DNS configuration, Tasker profile imports, Telegram bot creation, OpenClaw deployment, and end-to-end testing.

---

## Credential Security Model

| Layer | Mechanism | Files |
|-------|-----------|-------|
| OpenClaw config | `${VAR}` substitution from `.env` | `openclaw.json` |
| HA config | `!secret` references to `secrets.yaml` | `configuration.yaml` |
| HA webhooks | Auto-scrubbed by pre-commit hook | `automations.yaml` |
| Pre-commit pass 1 | `.secret-replacements` — known values → placeholders | All staged files |
| Pre-commit pass 2 | `.secret-patterns` — regex safety net | All staged files |
| Gitignore | 100+ rules covering credentials, runtime, PII | `.gitignore`, `ha/.gitignore` |

The pre-commit hook makes the workflow for HA config updates trivial: `scp pull → git commit`. The hook auto-replaces known secrets with placeholders, re-stages the cleaned files, then runs the pattern scan as a safety net.
