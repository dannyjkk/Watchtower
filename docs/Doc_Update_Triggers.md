# Jarvis Habits — Doc Update Triggers

**Purpose:** A task-centric lookup so Claude (HA-side) and Jarvis (OpenClaw-side) know **when to proactively flag Danny that a baseline doc needs updating** based on whatever tasks come in. This doc is procedure-only — no system facts, no configs. Just "if you did X, propose updating Y."

**Last updated:** May 3, 2026 (v1)
**Audience:** Both Claude and Jarvis. Same rules for both.

---

## How to use this doc

Both agents read this whenever they take action on the system. The flow is:

1. **Take the action** the user asked for (HA edit, Jarvis migration, cron change, Tasker fix, etc.)
2. **Cross-reference the action against the trigger table below**
3. **If a doc-update trigger fires:** propose the patch to Danny inline, in the same response. Don't wait for him to ask.
4. **If Danny approves:** apply the patch (Claude can produce updated files; Jarvis edits its workspace) and re-share the affected file(s).
5. **If no trigger fires:** say nothing. This doc exists to prevent both noise (over-flagging) and drift (under-flagging).

---

## The four baseline docs (reminder)

| Doc | Owns |
|---|---|
| `Jarvis_Habits_Handoff.md` | HA-side technical reality (entities, automations, scripts, math, infra, runbook) |
| `JARVIS_CLAUDE_CONTRACT.md` | Cross-agent boundaries, ownership, tool surfaces, cron/modules, change-log |
| `Jarvis_Habits_Cheatsheet.md` | One-page quick reference; whatever's in Handoff but optimized for at-a-glance lookup |
| `OpenClaw_HA_Routing_Guide.md` | Architecture spec for command routing + reference Jinja templates per command |

Plus this file (`Doc_Update_Triggers.md`) and Jarvis-side `habits-commands.md` (Jarvis's matcher config — Jarvis's domain).

---

## Trigger table

For every action category below: which docs need updating, and the typical sections.

### HA-side: structural changes

| Action | Docs to update | Sections |
|---|---|---|
| New automation created | Handoff, Cheatsheet | Handoff §5 (full entry), Cheatsheet automations table |
| Existing automation deleted | Handoff, Cheatsheet | Handoff §5 (remove entry), Cheatsheet automations table, Handoff §15 changelog |
| Automation logic/trigger materially changed | Handoff | Handoff §5 entry for that automation, Handoff §15 changelog if user-visible |
| Automation schedule changed (e.g. 22:30 → 22:00) | Handoff, Cheatsheet | Handoff §5 entry, Cheatsheet automations table |
| New script created | Handoff, Cheatsheet | Handoff §6, Cheatsheet scripts list |
| Existing script deleted | Handoff, Cheatsheet | Handoff §6, Cheatsheet, Handoff §15 changelog |
| Script logic materially changed | Handoff | Handoff §6 entry, Handoff §15 changelog if behavior-visible |
| New `input_number` / `input_boolean` / `input_datetime` / `input_text` helper | Handoff, Cheatsheet | Handoff §4 inventory, Cheatsheet entities list |
| Helper deleted | Handoff, Cheatsheet | Same; mark deletion in Handoff §4 cleanup notes + §15 changelog |
| Helper renamed (entity_id change) | Handoff, Cheatsheet, Routing Guide (if a template references it), Contract §9.1 | All affected sections; this is a refactor — verify all consumers |
| New template UI helper / YAML template sensor | Handoff, Cheatsheet | Handoff §4 + §7, Cheatsheet entities list |
| New view sensor (`sensor.jarvis_*_view`) | Handoff, Cheatsheet, Routing Guide | Handoff §4 view-sensor section, Cheatsheet, Routing Guide §"Future-proofing" if mentioned |
| New `rest_command` | Handoff | Handoff §7.3 + Cheatsheet "Rest commands" |
| Dashboard structural change (new section, removed tile) | Handoff | Handoff §10 |

### HA-side: behavioral changes

| Action | Docs to update | Sections |
|---|---|---|
| Tunable threshold edit via dashboard (`input_number.jarvis_*`) | **None** — these are designed to be live-edited; no doc update | — |
| Tunable default value structurally changed (initial/min/max bounds) | Handoff, Cheatsheet | Handoff §4 tunables table, Cheatsheet "Tunables" |
| AdGuard domain list change (yellow/orange/red) | Handoff | Handoff §6.2 (if domains are listed in description), Handoff §11 if zone semantics shift |
| New AdGuard punishment tier added | Handoff, Cheatsheet | Handoff §11 zone table, §6.2, §13 if known issue, Cheatsheet "Points & punishment" |
| Math change (new habit delta, new bonus, new penalty) | Handoff, Cheatsheet | Handoff §11 + §6.1 (eval script), Cheatsheet "Daily math" |
| New "today mode" added (e.g. a new boolean like jarvis_holiday_today) | Handoff, Cheatsheet | Handoff §4 + §11, Cheatsheet "Today modes" |
| Telegram message body change with semantic shift (e.g. now mentions blocks lifted) | Handoff | Handoff §6 entry for the script |
| Telegram message body cosmetic edit (typo, emoji swap) | **None** | — |

### Jarvis-side / OpenClaw

| Action | Docs to update | Sections |
|---|---|---|
| New command added (e.g. new bare-word trigger) | Routing Guide, Contract, habits-commands.md (Jarvis), AGENTS.md (Jarvis) | Routing Guide new route section, Contract §3.5 implemented-commands list, Contract §9.1 changelog |
| Existing command removed | Routing Guide, Contract, habits-commands.md, AGENTS.md | Same sections, plus Contract §9.1 |
| Command template changed (e.g. add count display, change emoji) | Routing Guide, habits-commands.md | Routing Guide template body for that command |
| Cron job added | Contract | Contract §3.2 watchers table |
| Cron job removed | Contract | Contract §3.2 (move to "Removed since…" note) |
| Cron schedule change | Contract | Contract §3.2 schedule column |
| Module enabled/disabled in `state/modules.json` | Contract | Contract §3.2 capability modules table |
| State file added | Contract | Contract §3.3 state files table |
| State file removed | Contract | Contract §3.3 |
| Watcher → Core delivery flow change | Contract | Contract §3.2, Contract §6.5 (debug paths) if user-facing |

### Cross-cutting

| Action | Docs to update | Sections |
|---|---|---|
| New tool/capability added on Jarvis or Claude side | Contract | Contract §3.4 (Jarvis tools) or §4 (Claude tools) |
| Tool/capability removed | Contract | Same sections, Contract §9.1 changelog |
| New red line / new "explicit-permission" action | Contract | Contract §5 |
| Ownership boundary change | Contract | Contract §2 ownership map |
| New verified-correction (i.e. an old doc claim was wrong, verified true via MCP/XML/etc.) | The doc that had the wrong claim, plus Contract §9.1 if cross-agent | Whichever section had the bad claim |

### Tasker-side (phone)

| Action | Docs to update | Sections |
|---|---|---|
| New tracked app added (Tasker profile + HA helper + automation `app_map` + screen formula + midnight reset + view sensor + dashboard) | Handoff, Cheatsheet | Handoff §9 Profile 1 + Tracked packages, §3 Data flow, §16 runbook reference. Cheatsheet entities + ingestion table |
| Existing tracked app removed | Handoff, Cheatsheet | Same sections; mark removal in Handoff §15 changelog |
| Tasker poll interval changed | Handoff, Cheatsheet | Handoff §9 Profile 1 trigger description, Cheatsheet "Data ingestion" |
| Webhook URL changed (e.g. HA IP migration) | Handoff | Handoff §9 payload example |
| Tasker tracking mechanism change (e.g. event → polling, or vice versa) | Handoff | Handoff §9 mechanism description |
| Tasker profile fixed (e.g. broken App context re-added) | Handoff §13 | Move from Outstanding to Resolved in §13 known-issues table |

---

### Periodic audit

| Action | Docs to update | Sections |
|---|---|---|
| Periodic audit reveals doc drift (e.g. cron count, state file count, automation behavior no longer matching docs) | Whichever doc is stale | The drifted sections. This is exactly how items like "cron list shrunk from 16 to 5 but Contract still says 16" get caught. |
| Audit cadence: quarterly minimum, or after any batch of system changes (e.g. agent removal, cron cleanup, HA restructure) | All four baseline docs | Spot-check: §3.2 cron table vs `openclaw cron list`, §3.3 state files vs `ls state/`, §5.11 watchdog description vs live automation, modules.json `enabled` flags vs actual scheduled watchers |

---

## What does NOT trigger a doc update (anti-noise)

Don't propose updates for any of the following — they're routine operation, not facts the docs need to track:

- Daily state changes (points going up/down, exemption days banked/used, screen-time accumulating, gym visits marked, tasks completed)
- Live tunable edits via the dashboard (`input_number.jarvis_*` threshold tweaks)
- Manual toggles of `exemption_today`, `jarvis_holiday_today`, `tasks_completed_today`
- Health Watchdog firings, AdGuard periodic syncs, midnight resets, nightly evals — all expected periodic behavior
- Telegram message cosmetic edits (typo fixes, emoji swaps, no semantic change)
- Verification audits with no findings (a clean audit is a non-event; just report and move on)
- Reading state via MCP (queries are not changes)
- Routine command invocations (Danny sending `status`, `points`, `habits`, etc.)
- Test runs of pure functions (`jarvis_compute_daily_eval` with `return_response=True`)

---

## Flagging protocol

**Both agents:** when an action you take or are asked to take fires a trigger from the table above:

1. **In the same response that announces the action**, add a doc-update note. Format:
   > **Doc-update flag:** This change touches `<doc-name>` §X (`<reason>`). Want me to draft the patch?

2. **If Danny approves the patch:** apply it. Claude produces the updated file via str_replace and re-exports. Jarvis edits its workspace copy.

3. **If Danny declines / defers:** drop it. He'll come back to it or won't. Don't nag.

4. **For multi-doc updates:** propose them all at once in the same flag. Don't drip them across multiple turns.

5. **Add a `§9.1` Contract changelog line** if the change is cross-agent or affects how Claude and Jarvis interact. Internal changes to one side don't require a Contract entry.

---

## Where this doc fits with existing protocol

- **Contract §9** governs Contract-specific updates (changelog format, sync to workspaces, deletion of superseded docs). This file does not duplicate that — Contract §9 still applies for any Contract changes.
- **Handoff §16 "Operational runbook"** has process steps for "Add a new tracked app" / "Add a new habit" / etc. Those steps include doc updates at the end. This file is the **lookup table** for those steps; the Handoff is the **how-to** for the underlying HA changes. Both stay.
- **Routing Guide §"Future-proofing"** has a 3-step recipe for adding a new module that ends with "Done. No Claude tokens, no HA routing changes." This file extends that with explicit doc-update triggers — when the module change is significant enough to need flagging beyond the Routing Guide's own update.

---

## Changelog

- **2026-05-06** — Added "Periodic audit" trigger section. Items #3, #10, #11 from the May 6 audit were exactly the kind of drift a scheduled audit-cadence trigger would have caught. Quarterly minimum recommended, plus after any batch of system changes.
- **2026-05-03** — v1. Created after Danny asked for a unified update-triggers reference. Authored by Claude based on combined experience from May 2-3 audit cycles. Reviewed scope against existing Contract §9, Handoff §16, and Routing Guide future-proofing section to avoid duplication.
