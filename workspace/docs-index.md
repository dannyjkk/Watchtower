# Docs Index — ~/.openclaw/docs/

Quick lookup so I only load the relevant doc(s) per question. **Do NOT load all docs** — pick the one that matches.

## 1. habits-commands.md
**When to read:** Danny says a habits command word (status, points, screen, habits, exempt, holiday, tasks_done, health, help habits) or asks about command syntax/triggers.
**What's in it:** Exact curl commands and Jinja templates for each habit command. HA connection details. Trigger word matching rules.
**Size:** ~11 KB

## 2. JARVIS_CLAUDE_CONTRACT.md
**When to read:** Questions about which agent (Jarvis vs Claude) owns what. Cross-agent boundaries. Who can edit HA, who can send Telegram, who has AdGuard access. Coordination rules during eval window (23:15-23:40 IST). Debug paths across agents.
**What's in it:** Full ownership map, red lines, MCP toolkit inventory, cron job inventory, module architecture, state files, coordination rules, change log.
**Size:** ~40 KB

## 3. Jarvis_Habits_Cheatsheet.md
**When to read:** Quick lookups — points/zone thresholds, daily math, entity names, AdGuard domain lists, common HA queries, automation list, script list, today modes, infrastructure IPs, webhook details.
**What's in it:** One-page reference for the entire habits system. Points table, daily math, entity inventory, automation table, scripts, rest commands, AdGuard verification steps, optional fixes list.
**Size:** ~21 KB

## 4. Jarvis_Habits_Handoff.md
**When to read:** Deep debugging, understanding full system internals, operational runbooks (add new app, add new habit, change threshold, debug data flow, debug punishment). Complete automation logic. Complete entity inventory with all fields. Tasker setup. Dashboard layout. Full change history.
**What's in it:** The exhaustive system reference. Every automation's trigger/condition/logic, every entity with min/max/unit, every script's full behavior, rest_command configs, infrastructure table, data flow pipelines, demerit math, known issues, runbooks.
**Size:** ~76 KB

## 5. OpenClaw_HA_Routing_Guide.md
**When to read:** How OpenClaw routes habit commands to HA. Template syntax for each command. Adding new routed commands. The /tasks_done enhanced flow (file I/O + HA script).
**What's in it:** Architecture diagram, routing table with full Jinja templates, implementation pseudocode, future-proofing guide.
**Size:** ~13 KB

---

## Decision tree

- **"What's my status/points/screen?"** → Execute per habits-commands.md (I have the commands memorized, no need to re-read unless something breaks)
- **"Why didn't X work?" / debugging** → Cheatsheet first (quick lookup), Handoff if deeper dive needed
- **"Can Jarvis do X?" / "Who handles Y?"** → Contract
- **"Add a new habit/app/domain"** → Handoff (runbooks in §16)
- **"How does the routing work?"** → Routing Guide
- **"What entities exist for Z?"** → Cheatsheet (compact list), Handoff (exhaustive with attributes)
- **"Jo" / house tasks** → Contract §6.6 + habits-commands.md (tasks_done flow)
