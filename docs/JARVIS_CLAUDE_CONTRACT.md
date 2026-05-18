# Jarvis ↔ Claude Coordination Contract

**Last verified:** May 17, 2026 (OpenClaw reconciliation pass: steps habit added to command templates, tunables 6→7, tasks_done enhanced with house_tasks.json integration, §6.6 house tasks coordination added, stale refs cleaned)
**Prior audits:** May 10 (Claude live MCP audit, snapshot refreshed, 7 optional-fix issues), May 6 (defensive defaults, dead code cleanup, tasks view, OpenClaw cron inventory by Kal-El), May 3, May 2
**Audience:** Both Jarvis (OpenClaw) and Claude (Anthropic via MCP). Same doc, two consumers.
**Replaces:** `CAPABILITY_AUDIT.md`, `CLAUDE_BOUNDARIES.md`, `JARVIS_CAPABILITIES_FOR_CLAUDE.md`

---

## 0. Why this doc exists

There were three Jarvis-authored docs trying to define the boundary, and they drifted from each other and from the live system within weeks. Symptoms: wrong MCP function names, wrong reload service, command triggers described incorrectly, claims of "direct AdGuard MCP" Claude doesn't have, an `escalations.json` example referencing a module not in the module list.

This doc fixes that by being:

1. **The single source of truth** for cross-agent boundaries. If anything in the older three docs contradicts this, this wins.
2. **Symmetric.** Both agents read the same file. Each one's "what I can do" is the other one's "what the other can do."
3. **Marked.** Every claim is tagged `[V]` (verified by Claude via live MCP), `[J]` (asserted by Jarvis, not verifiable from Claude's side), or `[~]` (correcting a mistake in earlier docs).
4. **Defers to:** `Jarvis_Habits_Handoff.md` for system internals, `habits-commands.md` for command triggers (single authoritative source), `Jarvis_Habits_Cheatsheet.md` for quick lookups.

When a capability or boundary changes on either side, update this file and re-share to both agents. That's the drift-prevention mechanism.

---

## 1. The contract in one paragraph

**HA is the source of truth for state and business logic.** All habit scoring, punishment enforcement, AdGuard rule pushes, and time-based automations live in HA and run regardless of which agent is awake. **Jarvis owns conversation, scheduling, and Telegram delivery.** Natural language command triggers, watcher/core cron jobs, proactive alerts, and DM-style replies all flow through Jarvis. **Claude owns infrastructure changes and deep debugging.** YAML/storage edits to automations and scripts, UI helper edits, log inspection, and ad-hoc multi-tool analysis go through Claude. Neither agent pushes AdGuard rules outside `script.jarvis_sync_adguard_rules`. Neither agent mutates habit state during the eval window (23:15–23:40 IST) without an explicit user override in the immediately preceding exchange.

---

## 2. Ownership map

| Domain | Jarvis | Claude | Authoritative path |
|---|---|---|---|
| HA entity reads | yes | yes | either |
| HA service calls (writes) | yes | yes | coordinate during eval window |
| HA automation/script edits | no | yes | Claude via `ha_config_set_*` |
| HA UI template helper edits | no | yes | Claude via `ha_set_config_entry_helper` |
| HA YAML file edits (`configuration.yaml`) | no | no | Danny edits the file; either agent reloads |
| HA input_* helper reloads (YAML-defined) | yes | yes | either via `input_number.reload`, `input_boolean.reload`, etc. |
| HA log reading | via ssh/file | yes | Claude via `ha_get_logs` |
| HA automation traces | via UI | yes | Claude via `ha_get_automation_traces` |
| AdGuard reads | via HA `rest_command.adguard_get` | via HA `rest_command.adguard_get` | same hop, either fine |
| AdGuard rule pushes | no | no | only `script.jarvis_sync_adguard_rules` |
| Telegram delivery to Danny | yes | no | Jarvis only |
| Telegram polling/reading | yes | no | Jarvis only |
| Habits command triggers | yes | no | Jarvis only |
| Google Workspace (Gmail/Cal/Tasks/Drive) | yes via `gog` CLI | no MCP | Jarvis only; ad-hoc requests route through Jarvis |
| OpenClaw cron management | yes | no | Jarvis only |
| OpenClaw workspace state files | yes | no | Jarvis only |
| Chrome browser (web UI) | no | yes | Claude only; rarely needed |
| Cross-agent messaging via "Jo" | yes | no | Jarvis only |

---

## 3. What Jarvis can do — asserted authoritative list

Everything in this section is `[J]` — Claude has no way to verify any of it from MCP. Jarvis: please correct on your side if anything is stale.

### 3.1 Architecture

- **Two-tier:** Watcher (Haiku, frequent polling, escalates to `state/escalations.json`) → Core (Sonnet, scheduled synthesis, delivers via Telegram).
- **Direct messages:** Sonnet, full reasoning, reads state files and calls HA/Google APIs.
- **Sessions:** isolated by default. State persists via workspace files at `/home/danny/.openclaw/workspace-jarvis/`.

### 3.2 Module architecture (two-tier)

**Capability modules** (7, toggled in `state/modules.json`):

User-facing feature groups. These control which high-level capabilities are active.

| # | Module | Status | Cron Jobs | State File | Operational? |
|---|---|---|---|---|---|
| 1 | **Home Pulse** | enabled (ON-DEMAND ONLY) | none | `home-pulse.json` (empty) | ⚠️ on-demand only, no scheduled watcher |
| 2 | **Thought Catcher** | enabled | 1 (Task Triage & Cleanup) | none | ✅ scheduled |
| 3 | **Inbox Intel** | enabled (ON-DEMAND ONLY) | none | none | ⚠️ on-demand only, no scheduled watcher |
| 4 | **Smart Reminders** | enabled | 2 (Calendar Watcher + Core) | `escalations.json` | ✅ scheduled |
| 5 | **Pantry Brain** | disabled | none | none (file removed May 6) | ❌ not implemented |
| 6 | **Subscription Sentinel** | enabled | 2 (Watcher + Core) | `subscriptions.json` | ✅ scheduled |
| 7 | **Daily Brief** | enabled | 1 (Morning Brief) | none | ✅ scheduled |

Modules 1 and 3 are explicitly annotated "ON-DEMAND ONLY: no scheduled watcher" in `state/modules.json` notes. They respond when Danny asks directly but do not proactively monitor. Module 2 (Thought Catcher) was promoted from on-demand to scheduled on May 13, 2026 (Kal-El).

**Active cron jobs** (6 total, verified live May 13, 2026 — all `lastRunStatus: ok`):

| Job | Model | Schedule (Asia/Calcutta) | Delivery | Last Duration |
|---|---|---|---|---|
| Thought Catcher — Task Triage & Cleanup | Sonnet | `30 8 * * *` (08:30) | none (silent pre-brief cleanup) | ~28s |
| Morning Brief — Daily Summary + Tasks | Sonnet | `0 9 * * *` (09:00) | none (LLM uses tool) | ~85s |
| Subscription Sentinel — Watcher | Haiku | `0 18 * * *` (18:00) | none (writes escalations.json) | ~30s |
| Subscription Sentinel — Core | Sonnet | `30 18 * * *` (18:30) | none (LLM uses tool) | ~39s |
| Smart Reminders — Calendar Watcher | Haiku | `0 20 * * *` (20:00) | none (writes escalations.json) | ~11s |
| Smart Reminders — Core Processor | Sonnet | `30 20 * * *` (20:30) | none (LLM uses tool) | ~17s |

All 6 jobs use `sessionTarget: isolated`, `wakeMode: now`, and `delivery.mode: none` (the LLM handles Telegram delivery via the `openclaw message send` tool inside its prompt, or runs silently for cleanup jobs). This replaces the older `delivery.mode: announce` pattern that was failing on 6 of 10 jobs in earlier audits — those jobs are gone.

The Thought Catcher job (added May 13) runs 30 minutes before the Morning Brief. It scans all 3 Google Tasks lists (Daily/Weekly/Monthly) for tasks with garbled or messy titles (typically from voice-dictated input), cleans up the titles, and moves tasks to the correct list based on their nature. This ensures the 9 AM Morning Brief reads clean, properly categorized tasks.

**Cleaned up since May 2, 2026:** removed 6 broken module-linked cron jobs (Screen Time Monitor, Screen Time Alerts Core, Task Monitor pair, Subscription Sentinel pair under old config), Morning Task Reminder (folded into Morning Brief), and 6 standalone reminders (water, plants, garbage, EOD, laundry, groceries). Total cron inventory dropped from 16 to 5, then back to 6 with Thought Catcher activation (May 13).

Claude cannot see either tier from MCP. To debug "why didn't Jarvis alert me?", ask Danny for `state/modules.json` (capability toggle) and `openclaw cron list` (active watchers).

**Subscription Sentinel error (May 13, resolved):** Both Subscription Sentinel jobs were erroring with `ERR_MODULE_NOT_FOUND: store.runtime-ePKOB3LA.js` due to a partial OpenClaw npm update leaving stale chunk hashes. Fixed by updating OpenClaw to 2026.5.7 + gateway restart. Manual trigger confirmed `status: ok`.

### 3.3 State files (4)

Located at `/home/danny/.openclaw/workspace-jarvis/state/`. Verified May 17, 2026:

| File | Size | Purpose |
|---|---|---|
| `modules.json` | 757 B | Capability module toggles + notes per module |
| `escalations.json` | 3 B (`[]`) | Watcher → Core handoff queue (currently empty) |
| `subscriptions.json` | 2.6 KB | Subscription tracking data |
| `home-pulse.json` | 65 B | HA status snapshot (empty until Home Pulse runs on-demand) |

**Removed since previous handoff:**
- `pantry.json` — Pantry Brain disabled, file removed May 6 (Kal-El).
- `screen-time-alerts.json` — vestigial; the screen-time-monitor cron job was removed but the file kept being touched. Deleted May 6 (Kal-El) as no live producer was found in `cron/jobs.json`.
- `house-tasks-context.json` — superseded by direct `mark_tasks_done` flow.
- 5 abandoned EOD task check-in files + 1 stale fix-plan doc (May 2).

### 3.4 Tool surface

- **HA REST API** via curl with long-lived token in `ha-token.txt` (183 bytes). Read entity states, call services, render templates, fire events.
- **AdGuard:** indirect, through HA's `rest_command.adguard_get` (read) and `rest_command.adguard_set_custom_rules` via `script.jarvis_sync_adguard_rules` (write). No direct AdGuard credentials.
- **Google Workspace:** `gog` CLI v0.12.0. Gmail (list/read/send/reply/modify), Calendar (events/create/update/delete), Tasks (list/items/CRUD), Drive/Docs/Sheets.
- **Telegram:** `openclaw message send --channel telegram --account jarvis --target "<DANNY_CHAT_ID>" --message "..."`. Send-only. Cannot read history, react, or post to groups (except house-tasks group via Jo). Chat IDs are in `secrets.yaml` — do not paste in docs (see Handoff §8 / OF-2).
- **Cron:** `openclaw cron list/add/update/remove/run`.
- **File system:** full read/write to workspace.

### 3.5 Habits-system role

Conversational frontend. Routes **natural language command triggers** per `habits-commands.md` (single authoritative source):

**Implemented commands** (all of these have HA-side scaffolding verified live; bare words, NOT slash-prefixed since `/` clashes with OpenClaw built-ins):
- `status` — Full dashboard (points, zone, habits, steps, exemptions, exemption-blocks-lifted indicator)
- `points` — Demerit points and zone
- `screen` — Screen time breakdown today (uses `sensor.jarvis_screen_limit_today`, auto-scales for relaxed days)
- `habits` — Today's habit check (gym, guitar, screen, tasks, late phone, steps)
- `exempt` — Use an exemption day (calls `script.mark_exemption_today`; lifts AdGuard blocks for the day per Handoff §6.3)
- `exempt status` — Check exemption bank, current relaxed-day state, blocks-lifted indicator
- `holiday` — Declare today a soft day with relaxed screen limit (calls `script.jarvis_mark_holiday_today`; doesn't cost an exemption day; eval still runs)
- `tasks_done` — Confirm house tasks done today (enhanced flow: reads `shared-house/house_tasks.json`, marks entries done, then calls `script.mark_tasks_done`)
- `health` — System health snapshot (Tasker poll age, AdGuard sync age, switch states)
- `help habits` — Show command list

Also handles variations: "what's my status", "show points", "screen time", "use exemption", "how many exemptions", "soft day today", "tasks done", etc.

**Important:** Bare-word triggers WITHOUT leading `/`. The OpenClaw Routing Guide uses `/status` etc. as section headers/spec convention but Jarvis's actual trigger matching is bare-word. The `/` prefix is reserved for OpenClaw built-ins (`/exec`, `/elevated`, `/reasoning`, etc.) and must not be used for habits commands.

**Implementation reference:** Jinja templates and POST endpoints for all 10 commands are in `OpenClaw_HA_Routing_Guide.md`. All read-only commands use `POST /api/template` with the template body as the request payload; all write commands POST to `/api/services/script/<script_name>` with empty body.

Jarvis cannot edit any HA YAML, scripts, automations, or UI helpers. Jarvis cannot push AdGuard rules outside the HA script.

### 3.6 Other agents Jarvis interacts with

- **Kal-El** — Danny's primary assistant on Telegram. Architecture decisions, agent creation. Jarvis escalates out-of-remit requests here.
- **Jo** — household task manager in the shared group with Maria. Jarvis routes anything Maria-relevant through Jo, never DMs Maria. Red line.

---

## 4. What Claude can do — verified MCP toolkit

Everything in this section is `[V]` — verified live via MCP on May 2, 2026.

### 4.1 Home Assistant — full toolkit

**Reads:**

- `ha_get_state(entity_id)` — single entity state and attributes.
- `ha_search_entities(query, domain_filter, area_filter, limit, offset)` — find entities by name/area/domain. There is **no `ha_get_states` plural** — use this with a broad query or empty string + domain filter to list.
- `ha_get_overview()` — system-level overview.
- `ha_eval_template(template)` — Jinja2 evaluation. **There is no `ha_render_template`** despite earlier docs.
- `ha_deep_search(query, search_types)` — searches *inside* automation/script/helper/dashboard configs. Use this to find automations referencing an entity, scripts using a service, etc.
- `ha_get_logs(source, level, search, hours_back, limit, entity_id)` — sources are `logbook` / `system` / `error_log` / `supervisor`.
- `ha_list_services(domain, query, detail_level)` — discover services.
- `ha_get_automation_traces(...)` — debug actual execution.
- `ha_get_history(...)` — recorder history.
- `ha_get_integration(domain, entry_id, include_schema)` — inspect integration config entries, including UI template helper formulas (`domain="template"`).
- `ha_get_entity`, `ha_get_device`, `ha_get_zone`, `ha_get_addon`, `ha_get_blueprint`, `ha_get_camera_image`, `ha_get_system_health`, `ha_get_updates`, `ha_get_helper_schema`, `ha_get_todo`, `ha_get_entity_exposure`, `ha_get_operation_status`.
- `ha_check_config()` — validate before reload.

**Writes:**

- `ha_call_service(domain, service, entity_id, data, return_response)` — universal service caller. Can return script `response_variable` payloads when `return_response=True`.
- `ha_config_set_automation`, `ha_config_set_script`, `ha_config_set_helper`, `ha_config_set_dashboard`, `ha_config_set_dashboard_resource`, `ha_config_set_area`, `ha_config_set_floor`, `ha_config_set_group`, `ha_config_set_label`, `ha_config_set_category`, `ha_config_set_calendar_event`, `ha_set_zone`, `ha_set_entity`, `ha_set_todo_item`, `ha_set_config_entry_helper`, `ha_set_integration_enabled`.
- `ha_config_remove_*` — remove the corresponding object types. Includes `ha_remove_entity`, `ha_remove_device`, `ha_delete_config_entry`.
- `ha_bulk_control` — bulk operations.
- `ha_reload_core()` — reload HA without full restart.
- `ha_restart()` — full HA restart.
- `ha_backup_create()`, `ha_backup_restore()`.
- `ha_call_addon_api(slug, path, method, body, ...)` — call any add-on's HTTP/WebSocket API.
- `ha_hacs_search`, `ha_hacs_download`, `ha_hacs_add_repository`, `ha_hacs_repository_info` — HACS management.
- `ha_import_blueprint(url)`.

**Important storage-vs-YAML constraint** `[~]`: Claude's `ha_config_set_automation` / `ha_config_set_script` write to HA's storage backend. They work for storage-mode (UI-created) automations and scripts. They do **not** edit `configuration.yaml` on disk. For things defined in `configuration.yaml` directly (`rest_command:`, the 2 YAML template sensors `phone_screen_time_total` and `demerit_zone`, possibly old YAML automations), Danny has to edit the file. Claude cannot SSH or read/write files on the HA host.

> Verified May 2: the Jarvis automations and scripts referenced in this system live under storage category `01KQ8475KY5WD3511F1HYD02KT` — they are storage-mode and Claude can edit them via `ha_config_set_*`.

### 4.2 Reload services after YAML edits

> `[~]` Earlier docs told Claude to call `ha_call_service('homeassistant', 'reload_config_entry', ...)`. **That is wrong.** `reload_config_entry` is for reloading an *integration's* config entry (e.g., the AdGuard Home integration), not for reloading YAML.

Correct reload services after `configuration.yaml` edits:

| What was edited | Service to call |
|---|---|
| Automations (YAML) | `ha_call_service('automation', 'reload')` |
| Scripts (YAML) | `ha_call_service('script', 'reload')` |
| `rest_command:` block | `ha_call_service('rest_command', 'reload')` |
| YAML template sensors | `ha_call_service('template', 'reload')` |
| Input helpers (YAML-defined) | `ha_call_service('input_number', 'reload')`, `ha_call_service('input_boolean', 'reload')`, etc. |
| All YAML at once | `ha_reload_core()` or `ha_call_service('homeassistant', 'reload_all')` |
| Integration config entry | `ha_call_service('homeassistant', 'reload_config_entry', {entry_id: ...})` — different use case |

### 4.3 AdGuard

`[~]` **Claude has no direct AdGuard MCP.** Earlier docs assumed I did. I don't. AdGuard is reached through HA's REST commands, identical hop count to Jarvis:

- Read: `ha_call_service('rest_command', 'adguard_get', data={'path': '<endpoint>'}, return_response=True)`. Endpoints: `status`, `clients`, `filtering/status`, `querylog?limit=N&search=Danny%20S23`, `stats`.
- Write rules: never directly. Only via `ha_call_service('script', 'jarvis_sync_adguard_rules')`. Domain lists live in that script's `variables:`.

The 4-step end-to-end verification chain (Section 17 of the handoff) works the same for either agent.

### 4.4 Google Workspace

Claude has **no Gmail / Calendar / Tasks / Drive MCP**. If Danny asks for a Workspace operation, Claude routes to Jarvis: "Ask Jarvis — he has the gog CLI." No exceptions.

### 4.5 Telegram

Claude has no Telegram access. Cannot send, cannot read. If Claude needs Danny notified about a system event, it does one of:

1. Reply in the current Claude chat (Danny is presumably reading it).
2. Make an HA change that triggers `rest_command.jarvis_send_message` as a side effect.
3. Tell Danny "ask Jarvis to ping you when X completes."

### 4.6 OpenClaw

Claude has no access to OpenClaw cron, workspace files, message logs, or the Watcher/Core scheduler. Any debugging that requires those goes through Danny: "Can you paste `state/escalations.json`?" / "Can you run `openclaw cron list`?"

### 4.7 Chrome browser

Claude has a browser tool (Claude in Chrome). Almost never relevant for habits work. Listed only for completeness.

---

## 5. Shared red lines (neither agent does these)

1. **No AdGuard rule pushes outside `script.jarvis_sync_adguard_rules`.** Domain lists live in the script. Direct pushes get clobbered on the next periodic sync (every 15 min).
2. **No manual triggering of time-based automations** (`automation.jarvis_nightly_report_*`, `automation.jarvis_late_phone_demerit`, `automation.jarvis_midnight_reset`, `automation.jarvis_adguard_periodic_sync`, `automation.jarvis_health_watchdog`) outside their scheduled times. Exceptions: Danny explicitly asks, or emergency recovery from a missed run.
3. **No habit-state mutation during eval window (23:15–23:40 IST)** without an explicit user override in the immediately preceding exchange (Danny says "do X anyway" in the last 1-2 messages). The window covers the 23:20 nightly report and 23:35 late-phone demerit, with 5-minute padding either side.
4. **No DM to Maria** from either agent. Anything Maria-relevant routes through Jo to the house-tasks group `-1003839611586`.
5. **No financial advice / sensitive credentials in messages.** This isn't Jarvis-specific — it's a general operating constraint.
6. **No credentials in documentation files.** Bot tokens, API keys, and passwords should reference `secrets.yaml` entries, not be pasted in plaintext. Credentials were redacted from all canonical docs on May 10 (see OF-2 in Handoff §13). The actual values are still inline in `configuration.yaml` pending migration.

For read-only "what would happen tonight" testing, use `ha_call_service('script', 'jarvis_compute_daily_eval', return_response=True)`. This is a pure function, no side effects, safe anytime.

---

## 6. Coordination rules

### 6.1 Eval window (23:15–23:40 IST)

State writes that touch habit booleans, demerit_points, overflow_points, or exemption_days during this window can race with the nightly automations. If Danny asks for a write here, the responding agent should warn first: "This is during the eval window. Proceed anyway?" If Danny confirms, proceed. If it's an emergency fix (e.g., midnight reset failed), proceed and log it.

### 6.2 AdGuard rule changes

Procedure for adding/removing blocked domains: see Handoff §16 runbook ("Add or remove a blocked domain") for the 5-step sequence (edit script lists → reload → force sync → verify via `adguard_get` → update Handoff §6.2). YAML/storage edit constraints: Handoff §6.2.

Cross-agent notes specific to this contract:
- Neither agent pushes AdGuard rules outside `script.jarvis_sync_adguard_rules` (red line, §5). The 15-min periodic sync would clobber any direct push within minutes regardless.
- Domain-list edits via `ha_config_set_script` are Claude-only (Jarvis lacks HA edit MCP).
- If today is an exemption day, `user_rules` will be `[]` regardless of the domain edit — the change only surfaces in `user_rules` after exemption flips off at midnight (sync forces zone to green when exempt; see Handoff §6.2 for the override template).

### 6.3 Tunables

Seven `input_number.jarvis_*` helpers (points_max, points_per_exemption, screen_limit_normal, screen_limit_relaxed, gym_min_minutes, guitar_target_minutes, steps_target) are designed for live editing. Either agent can change them via `input_number.set_value`, but: confirm with Danny first, and don't change them mid-day during active scoring (i.e., not between 00:00 and 23:20).

### 6.4 Gmail / Calendar overlap

Doesn't apply right now — Claude has no Workspace MCP. Listed only so future-Claude with such MCP knows: Jarvis owns scheduled monitoring (Inbox Intel, Smart Reminders), Claude would own ad-hoc queries. Don't both auto-label or auto-archive.

### 6.5 Command triggers

Claude never responds to habits command triggers. Claude has no Telegram access in any case, but the principle holds: if Danny pastes `status` or `exempt` into a Claude session by mistake, Claude says "that's a Jarvis command" and stops.

### 6.6 House tasks coordination

Shared files at `/home/danny/.openclaw/shared-house/`:
- `house_tasks.json` — today's active tasks. **Jo writes** (creates entries from group chat + recurring crons), **Jarvis reads + marks complete** (during `tasks_done` flow).
- `reminders.json` — one-off future reminders. Jo writes, Jarvis reads for awareness.
- Schema: `House_Tasks_Schema.md`.

**Boundary:** Jo owns task/reminder creation and deletion. Jarvis marks tasks `status: "done"` during `tasks_done` but never creates or removes entries. Neither agent flips HA booleans on behalf of the other — Jarvis calls `script.mark_tasks_done` (HA boolean), Jo never touches HA.

---

## 7. Debug paths across the boundary

### 7.1 Claude needs Jarvis-side info

When Danny asks Claude something Claude can't see, Claude asks Danny to fetch:

- "Why didn't Jarvis alert me about X?" → ask for `state/modules.json` (is the module on?), `state/escalations.json` (was it queued?), `openclaw cron list` (is the watcher scheduled?).
- "What was Jarvis's last brief?" → ask Danny to scroll Telegram or check OpenClaw message logs.
- "Did the watcher fire at noon?" → `openclaw cron list` plus state-file timestamps.

### 7.2 Jarvis needs Claude-side info

When Jarvis hits something it can't fix, escalate via Danny:

- "Telegram messages stopped arriving and AdGuard sync started failing simultaneously" → Claude inspects `ha_get_logs(source="system", level="ERROR", search="rest_command")` for `Setup failed for 'rest_command'`. This is the YAML-indent-slip pattern (handoff Section 7.3).
- "Punishment isn't kicking in" → Claude runs the 4-step AdGuard chain verification (handoff Section 17), checks `switch.adguard_home_protection_2` and `switch.adguard_home_filtering_2`, inspects automation traces.
- "Eval gave wrong result last night" → Claude calls `script.jarvis_compute_daily_eval` with `return_response=True`, compares against `pre_eval_points` and habit-state at the time, walks through the math.

### 7.3 Either agent needs to verify the system end-to-end

Use the 4-step `adguard_get` chain documented in Handoff §17 and Cheatsheet ("AdGuard read-side"): `status` → `clients` → `filtering/status` → `querylog?search=Danny%20S23`. Both agents call it through HA's `rest_command.adguard_get` — same hop count, same expected results. If 1–3 pass and 4 returns empty, the phone isn't using AdGuard for DNS (most common cause: Android Private DNS bypass).

---

## 8. Pinned corrections from earlier Jarvis-authored docs

These were repeated across `CAPABILITY_AUDIT.md`, `CLAUDE_BOUNDARIES.md`, and `JARVIS_CAPABILITIES_FOR_CLAUDE.md`. Listed here so they don't slip back in:

| Mistake | Reality |
|---|---|
| `ha_get_states` (plural) | Doesn't exist. Use `ha_search_entities` or `ha_get_overview`. |
| `ha_render_template` | Doesn't exist. Use `ha_eval_template`. |
| `ha_get_entities`, `ha_get_services`, `ha_fire_event`, `ha_get_config` | Not these names. Use `ha_search_entities`, `ha_list_services`, etc. |
| `adguard_get_status`, `adguard_get_clients`, `adguard_get_filtering`, `adguard_get_querylog`, `adguard_get_stats`, `adguard_set_rules` | None exist. Claude uses HA's `rest_command.adguard_get` and `rest_command.adguard_set_custom_rules` (via the script) — same as Jarvis. |
| `ha_call_service('homeassistant', 'reload_config_entry', ...)` for YAML reloads | Wrong service. Use `automation.reload`, `script.reload`, `rest_command.reload`, `template.reload`, `ha_reload_core`, or `homeassistant.reload_all`. `reload_config_entry` is for *integration* config entries. |
| Claude can edit `/config/configuration.yaml` directly | Cannot. No filesystem access. Storage-mode entities yes (via `ha_config_set_*`); YAML-file entities require Danny to edit. |
| Claude cannot restart HA | Can. `ha_restart()` exists. |
| Command triggers have leading `/` (`/status`, `/points`, etc.) | Wrong. These are natural language triggers WITHOUT `/`. Per `habits-commands.md`: "These are natural language triggers, NOT slash commands (slash commands clash with OpenClaw built-ins)." Full list: `status`, `points`, `screen`, `habits`, `exempt`, `exempt status`, `help habits`. |
| `escalations.json` example uses `module: "taskMonitor"` | Correct, but it's an **operational module** (watcher identifier), not one of the 7 **capability modules** in `state/modules.json`. See §3.2 for the two-tier taxonomy. |

---

## 9. Versioning and update protocol

This file is the source of truth for cross-agent boundaries. When it changes:

1. Whoever made the change writes a one-line entry below in §9.1 with date and what changed.
2. Danny syncs the file to both agents' contexts (Claude's project files, Jarvis's workspace).
3. The other three Jarvis-authored capability docs (`CAPABILITY_AUDIT.md`, `CLAUDE_BOUNDARIES.md`, `JARVIS_CAPABILITIES_FOR_CLAUDE.md`) should be deleted, not maintained alongside this — they were the drift problem.
4. The handoff (`Jarvis_Habits_Handoff.md`), cheatsheet (`Jarvis_Habits_Cheatsheet.md`), and command reference (`habits-commands.md`) remain authoritative for system internals and stay in sync independently.

Re-verify quarterly: each agent runs through its own §3 or §4 list and confirms the tools and capabilities still match. Anything that has changed gets updated here.

### 9.1 Change log

- **2026-05-17** — OpenClaw reconciliation pass by Claude. Steps habit (6th habit, bonus-only +2/0, `sensor.garmin_connect_steps` vs `input_number.jarvis_steps_target`) added to `status` and `habits` command templates in both `habits-commands.md` and `OpenClaw_HA_Routing_Guide.md`. Tunables updated from 6→7 (added `steps_target`) in §6.3. `tasks_done` command upgraded to enhanced flow: reads `shared-house/house_tasks.json`, lists pending tasks, marks them done in file (`last_updated_by: "jarvis"`), then calls `script.mark_tasks_done` — closing the gap where Jo created tasks but nobody marked them complete in the file. New §6.6 added for house tasks coordination (Jo writes, Jarvis reads+marks, boundary rules). AGENTS.md state files cleaned (removed deleted `screen-time-alerts.json` and `pantry.json`). Stale Handoff/Cheatsheet copies in `workspace-jarvis/docs/` replaced with May 17 reconciled versions. Kal-El `jarvis-docs-export/` folder deleted (stale drift vector). §3.3 verification date updated. Authored by Claude after OpenClaw workspace inventory.
- **2026-05-15** — Home-WiFi gate for screen-time tracking. Tasker-side change (Danny): the 6 entertainment Stop tasks now have `If %AtHome ~ 1` on the accumulator step, where `%AtHome` is driven by a new Tasker WiFi-Connected profile matching `<YOUR_HOME_WIFI>/<YOUR_HOME_WIFI_5G>`. Guitar unchanged. HA-side change (Claude): new `binary_sensor.jarvis_screen_counting_active` UI template helper (formula: `{{ states('sensor.danny_s23_wi_fi_connection') in ['<YOUR_HOME_WIFI>', '<YOUR_HOME_WIFI_5G>'] }}`, device_class connectivity), tile added to dashboard System health section at position 1. No automation/script/eval changes. End-to-end verified live with 5-step WiFi-toggle test: home → counts; WiFi off + mobile data → counter froze at 20.0 min despite a Tasker poll firing through Tailscale; WiFi reconnect → counting resumed. Authored by Claude after live MCP audit.
- **2026-05-13** — Kal-El maintenance round. Two issues investigated from Jarvis escalation.
  - **Thought Catcher activated as scheduled job.** Previously on-demand only (no cron). New cron job "Thought Catcher — Task Triage & Cleanup" added at 08:30 daily (Sonnet). Scans all 3 Google Tasks lists (Daily/Weekly/Monthly), cleans up garbled voice-dictated task titles, and moves tasks to the correct list. Runs 30 min before Morning Brief so the 9 AM brief reads clean tasks. Test run confirmed ok (~28s). Jarvis's original proposal (two-tier watcher/core with voice-note transcription synthesis) was rejected — the actual use case is simpler: tasks arrive pre-created from Google Assistant, just need title cleanup and list categorization.
  - **Subscription Sentinel error fixed.** Both jobs had `ERR_MODULE_NOT_FOUND: store.runtime-ePKOB3LA.js` due to partial OpenClaw npm update (stale chunk hashes). Fixed by OpenClaw update to 2026.5.7 + gateway restart (PID 18888, started 21:23 IST). Manual trigger of Watcher confirmed `status: ok`.
  - **Jo agent confirmed alive.** 3 Jo cron jobs (Refill water, Garbage collection, Water plants) verified as newly created (different IDs from the May 6 deleted ones), attached to the rebuilt Jo agent (`ollama/nemotron-3-super:cloud`, workspace `shared-house`). Not orphaned.
  - **Updated:** Contract §3.2 (module table, cron table, Thought Catcher description), `state/modules.json` (Thought Catcher note updated from on-demand to scheduled). Handoff §14 cron line, §15 changelog.
- **2026-05-10** — Live read-only audit by Claude (Opus 4.6 via HA MCP). No HA-side changes made.
  - **Snapshot refreshed** (Handoff §14): demerit 2/12 (red zone), exemption active (Saturday), screen 236/210 (over), gym done, guitar/tasks not done. All 12 automations enabled, all traces clean, all 5 OpenClaw cron jobs verified ok via `openclaw cron list`.
  - **10 optional fixes cataloged** (Handoff §13 "Optional fixes identified May 10"): OF-1 screen-time fail-silent default, OF-2 plaintext credentials, OF-3 Tasker dual-IP, OF-4 midnight reset race, OF-5 watchdog global cooldown, OF-6 unauthenticated webhooks, OF-7 dead code in mark_exemption_today, OF-8 input_number mode inconsistency, OF-9 automation description mismatch, OF-10 failed login investigation. All require explicit permission; none are currently breaking.
  - **Credentials redacted** from Handoff §2, §7.3, §8, and Cheatsheet infrastructure section. Docs now reference `secrets.yaml` instead of pasting tokens/passwords. The actual values are still inline in `configuration.yaml` (see OF-2).
  - **Tasker dual-IP documented** in Handoff §9: bulk webhook targets Tailscale IP `100.107.164.26`, late-phone targets LAN IP `192.168.0.124` (see OF-3).
  - **Cron job status re-verified:** All 5 jobs status ok, matching §3.2 table. Morning Brief 13h ago, Subscription Sentinel pair 4h ago, Smart Reminders pair 2h ago. No model column changes.
  - **Cross-reference updates:** Cheatsheet updated with optional-fix summary table and dual-IP note. Contract §9.1 updated. Routing Guide unchanged (templates and paths remain accurate).
- **2026-05-06** — Audit cleanup round, both agents.
  - **Claude side (HA):** (1) defensive defaults applied — `current_pts | int(12)` → `int(0)` in eval script, late-phone demerit, and pre_eval snapshot; rollback in `mark_exemption_today` defaults to current points (no-op fallback). (2) Dead `total_delta` / `would_be_pts` outer variables removed from `script.jarvis_compute_daily_eval`. (3) `binary_sensor.jarvis_tasks_view` created for symmetry with the other view wrappers (now 13 view sensors, 17 UI template helpers total). (4) Stale descriptions resynced on `script.jarvis_sync_adguard_rules` and `automation.jarvis_punishment_enforcer` to reflect May 3 exemption override. (5) Dashboard hardening: AdGuard Filtering tile changed from `tap_action: toggle` (one-tap silent disable) to `tap_action: more-info` + `hold_action: toggle` with confirmation dialog; tasks tile switched to `binary_sensor.jarvis_tasks_view`; screen-time tile name "(limit: see below)" removed. (6) Health Watchdog scope expanded to also alert on disabled monitored automations (third signal alongside Tasker/AdGuard staleness).
  - **Jarvis side (Kal-El):** OpenClaw cron inventory shrunk from 16 jobs (with 6 broken) to 5 working jobs — see updated §3.2 table. State files dropped from 8 to 4 after deleting `screen-time-alerts.json` (vestigial, no producer) and `pantry.json` (module disabled). The 3 ON-DEMAND ONLY modules are now annotated as such in `state/modules.json`. Periodic-audit trigger added to `Doc_Update_Triggers.md` so future drift is caught during routine audits. Routing Guide §15 disclaimer kept as-is (adequately explains `/`-prefix is spec convention, not real syntax).
  - **Cross-cutting:** AdGuard colocation on `ubuntu-media` VM (with OpenClaw/Plex/qBit/Ollama) is now explicitly documented in Handoff §2 and §13 — confirmed by Danny May 6. Local LLM plan abandoned the same day after benchmarks: N150 hits 0.75 tok/s on Qwen 2.5 7B (Morning Brief would take ~30 minutes vs 85s on Sonnet); Mac mini M4 Pro upgrade considered but not pursued for purely-LLM reasons. Cloud-only for cron jobs is the architectural decision going forward. Three naming inconsistencies (unprefixed `script.mark_*` scripts, `automation.jarvis_gym_visit_detected` legacy entity_id) consciously deferred as accepted technical debt — see Handoff §13.
  - Updated: Handoff §1, §2, §4, §5.7, §5.8, §5.9, §5.11, §6.1, §6.2, §6.3, §7, §10, §12, §13, §14, §15. Cheatsheet (header date, view sensors list, automations table for Watchdog scope, today modes, AdGuard chain). Contract §3.2, §3.3, §9.1. Routing Guide (`/habits` template uses new tasks view). Authored by Claude after live MCP audit; Jarvis-side changes by Kal-El.
- **2026-05-03 (later)** — Command set expanded per Option A. `holiday`, `tasks_done`, `health` moved from "not implemented" to "implemented" in §3.5. All HA-side scaffolding has been verified live (`script.jarvis_mark_holiday_today`, `script.mark_tasks_done`, and `sensor.jarvis_minutes_since_*` all exist and work). Jarvis still needs to wire the bare-word triggers + Jinja templates into `habits-commands.md` — implementation reference is in `OpenClaw_HA_Routing_Guide.md`. Also fixed in this round: removed stale `phone_chrome_usage` reference and replaced hardcoded `120` with `sensor.jarvis_screen_limit_today` in screen-related templates so they auto-scale on relaxed days. Plus inverted the `binary_sensor.jarvis_phone_late_view` template formula so it matches its documented "on = success" semantic — fixes wrong tick/cross in `/habits`, dashboard, and any downstream consumer that read this view.
- **2026-05-03** — Two HA changes verified live and propagated through canonical docs.
  1. **Exemption-unblock change.** `automation.jarvis_punishment_enforcer` gained a second state-change trigger on `input_boolean.exemption_today`. `script.jarvis_sync_adguard_rules` now computes effective zone as `green if exemption_today is on else states('sensor.demerit_zone')`. Net effect: declaring exemption lifts all AdGuard blocks for the day; midnight flip-off re-pushes correct rules per actual zone.
  2. **Tasks habit entity_id rename.** `input_boolean.tasks_completed_today_2` renamed back to `input_boolean.tasks_completed_today` to match every existing reference (script, midnight reset, eval, house-tasks prompt, routing templates, dashboard). Pre-fix, the entity at the referenced name didn't exist and the tasks habit was silently dead. The May 2 handoff had falsely claimed `..._2` was deleted; it actually only got renamed today.
  - Updated: Handoff §1, §3, §4, §5.9, §6.2, §6.3, §11, §13, §14, §15, §16, §17; Cheatsheet (Points & punishment, Today modes, automations table, scripts, AdGuard chain step 3); Routing Guide (`/status`, `/exempt`, `/exempt_status`); Contract §6.2. Authored by Claude after live MCP audit.
- **2026-05-02** — Initial version. Replaces the three earlier Jarvis-authored capability docs. Authored by Claude after live MCP audit, to be reviewed by Jarvis on its side.
- **2026-05-02 (21:25 IST)** — Jarvis review round 1. Corrected: (1) module taxonomy is two-tier (capability modules in `state/modules.json` + operational watchers in `escalations.json`); (2) command surface is natural language WITHOUT `/` prefix, not slash commands; (3) `help habits` exists; (4) `gog` build date dropped (kept v0.12.0); (5) `ha-token.txt` size (183 bytes) useful for verification; (6) model identifiers confirmed (`anthropic/claude-haiku-4-5` for Watcher, agent default Sonnet for Core). Added `input_*` reload services to §4.2. Clarified "same conversation" → "immediately preceding exchange" in §5 red line 3. Verified by Jarvis (OpenClaw) via live file/state inspection. Danny approved all corrections.
- **2026-05-02 (21:50 IST)** — Routing guide reconciliation. Removed all references to non-existent `OpenClaw_HA_Routing_Guide.md`. Confirmed `habits-commands.md` is the single authoritative source for command triggers. Listed 7 implemented commands in §3.5. Noted `holiday`, `tasks_done`, `health` were referenced in earlier draft but are not implemented (removed from contract). If needed in future, add to `habits-commands.md` first. Danny approved.
- **2026-05-02 (22:20 IST)** — Jarvis full capability audit. §3.2: replaced module list with verified operational table showing actual cron job status, delivery config, and known errors (6 of 10 module cron jobs failing due to missing `delivery.to`). Documented 3 on-demand-only modules (Home Pulse, Thought Catcher, Inbox Intel — enabled but no cron jobs). Added 6 standalone reminder cron jobs not linked to any module. §3.3: corrected from 12 to 8 state files after EOD task check-in cleanup; added per-file status table. Removed `AGENTS.md` House Tasks Handler section (unimplemented). Cleaned up 6 intermediate audit/report files from workspace. Danny approved.

---

**End of contract.**
