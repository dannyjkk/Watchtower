# Jarvis Habits System — Handoff Document

**Date:** May 17, 2026 (May 17 reconciliation: steps habit documented, AdGuard tiers corrected, house tasks buttons documented, credentials migration confirmed, 4 new entities added, OF-2 moved to resolved)
**Prior audits:** May 10 (snapshot refreshed, optional fixes documented), May 6 (defaults hardened, dead code removed, descriptions resynced, tasks view sensor added), May 3 (exemption-unblock, tasks fix), May 2 (initial)
**Last reconciled from live HA:** May 17, 2026 via MCP + configuration.yaml backup
**Author:** Claude (Anthropic) via HA MCP — full live audit
**Audience:** Next LLM picking this up

This document describes the complete state of Danny's "Jarvis Habits" self-accountability system. Everything was confirmed via live MCP queries on May 17, 2026, including direct probes of AdGuard's REST API and a configuration.yaml backup review. Notable changes since May 10:

- **Steps habit added** as a 6th habit — bonus-only (+2 if target met, 0 if missed) via `sensor.garmin_connect_steps` (Garmin Connect HACS integration). New tunable: `input_number.jarvis_steps_target` (default 8000). New daily result: `input_number.daily_steps_result`. Max daily gain is now +6 (was +4). See §4, §6.1, §11.
- **AdGuard domain tiers restructured.** Orange is now Netflix + Prime only. Hotstar/JioHotstar/Disney+ moved to red. TikTok, Twitch, Reddit, Snapchat removed from all tiers. See §6.2, §11.
- **House tasks prompt now sends inline keyboard buttons** via `rest_command.jarvis_send_message_keyboard` instead of a text reply prompt. See §5.6, §7.3.
- **Credentials migrated to `secrets.yaml`.** Bot token + chat_id bundled as `telegram_jarvis_send_url`, AdGuard auth as `adguard_basic_auth`. OF-2 is resolved. See §7.3, §8.
- **New entity: `binary_sensor.jarvis_screen_counting_active`** — Tasker data freshness indicator, shown on dashboard. See §4, §7.2.
- **New entity: `input_boolean.adguard_blocked`** — set by sync script, reflects whether AdGuard punishment is active. See §4, §6.2.

---

## 1. The use case

Danny is a smart-home power user in Bangalore running a small home lab. He wants a **demerit-based self-accountability system** that:

- Tracks six daily habits: **gym attendance, guitar practice, entertainment screen time, house tasks, phone bedtime, daily steps** (steps is bonus-only — rewards but never penalizes)
- Awards/deducts points based on whether habits were done
- Progressively punishes slippage by **DNS-blocking entertainment apps on his phone** via AdGuard Home
- Sends daily reports via his existing Telegram bot ("Jarvis")
- Supports **exemption days** (skip eval entirely AND lift all AdGuard blocks for the day, costs 1 from bank) and **holidays** (soft day, relaxed screen limit) — exemption days are earned by over-performing
- Self-monitors data flow health and alerts when Tasker or AdGuard sync goes stale

Core design philosophy: **HA is the single source of truth for state and business logic.** Jarvis on OpenClaw is a conversational frontend but should not re-implement habits logic. All scoring, punishment, and habit-evaluation logic lives in HA.

Architecture notes worth highlighting:
- **Eval logic is a pure function.** `script.jarvis_compute_daily_eval` reads state and returns a result via `response_variable` without mutating anything. The nightly automation calls it, then writes new state. This makes the math testable in isolation.
- **AdGuard is driven by `sensor.demerit_zone`, not raw points.** The Punishment Enforcer triggers on zone change OR exemption flip — fewer pointless rule pushes, and exemption transitions are first-class events.
- **Exemption is AdGuard-aware.** The sync script checks `input_boolean.exemption_today` and forces effective zone to green when exempt, so all blocks lift for the day. At midnight when exemption flips off, the enforcer re-fires and re-pushes rules per actual points.
- **Domain lists live in the sync script, not in rest_commands.** Adding/removing a blocked domain is a one-line edit in `script.jarvis_sync_adguard_rules`.
- **Stable view-sensor layer** (`sensor.jarvis_*_view`) wraps internals so the dashboard and OpenClaw routing templates don't break when underlying entities change.
- **Tunables are entities, not literals.** Six `input_number.jarvis_*` helpers expose all thresholds for live editing.
- **AdGuard is bidirectionally observable.** A generic `rest_command.adguard_get` lets HA (and any LLM driving HA) query AdGuard's REST API for clients, filtering status, query logs, and stats. See Section 17.

---

## 2. Infrastructure — what runs where

| Component | Where | Notes |
|---|---|---|
| **Home Assistant** | Dedicated VM on Proxmox | IP: `192.168.0.124:8123`. Has MCP server exposed for LLM admin. Integration with AdGuard Home already configured. |
| **AdGuard Home** | **Colocated on the OpenClaw VM (`ubuntu-media`).** Reachable at `192.168.0.122:80` (LAN) + `100.111.225.16` (Tailscale). | Version `v0.107.74`. Credentials: **see `secrets.yaml`** (basic-auth header stored there). Two switches matter: `switch.adguard_home_protection_2` (master kill switch) and `switch.adguard_home_filtering_2` (filtering subsystem, required for custom rules). Both MUST be ON. **Colocation note:** AdGuard shares a CPU with OpenClaw, Plex, qBittorrent, Ollama. Heavy CPU load on the VM (e.g., long Plex transcodes or local LLM inference) can lag DNS resolution for the household. |
| **OpenClaw (Jarvis host)** | Same VM as AdGuard (`ubuntu-media` on Proxmox), reachable at `192.168.0.201` | Hosts the Jarvis Telegram agent. Has an HA long-lived access token named "Jarvis". |
| **Phone (Samsung S23)** | Tailscale IP `100.70.157.25`, LAN IP `192.168.0.47` on WiFi "<YOUR_HOME_WIFI_5G>" | Tasker 6.4+ posts bulk usage stats to HA via polling webhook. Always on Tailscale. AdGuard sees both IPs and maps them to persistent client "Danny S23". |
| **Tailscale** | Everywhere | Routes home subnet. Phone can reach `192.168.0.124` (HA). |

---

## 3. Data flow — the full pipeline

### App usage (bulk polling)

```
1. Phone: Tasker polls usage stats every ~2 min.
2. Tasker POSTs to http://192.168.0.124:8123/api/webhook/<YOUR_BULK_WEBHOOK_ID>
   Flat JSON body: {youtube: N, instagram: N, netflix: N, prime: N,
                    hotstar: N, brave: N, guitar: N}  (values in minutes)
3. HA's "Jarvis - Phone Usage Stats Bulk Update" automation triggers.
4. For each key in app_map: if present in payload, overwrite the matching
   input_number counter. Missing keys are left untouched.
5. Each successful run also writes input_datetime.jarvis_last_tasker_poll.
6. sensor.phone_screen_time_total auto-recomputes (template sensor,
   sum of 6 apps: YT + IG + Netflix + Prime + Hotstar + Brave).
   Guitar is excluded.
```

### Late phone usage

```
Tasker fires POST /api/webhook/<YOUR_LATE_PHONE_WEBHOOK_ID> when screen turns on 23:30–04:59.
HA flips input_boolean.phone_used_late on (idempotent, condition-guarded).
```

### Daily eval cycle

```
22:30 IST — House tasks prompt. Telegram nudge if tasks not yet done
             AND not exempt AND not holiday. Encourages /tasks_done reply.

23:20 IST — Nightly report.
             1. Snapshots current points to pre_eval_points.
             2. If exempt today: send read-only stats summary, STOP.
             3. Else: calls jarvis_compute_daily_eval → gets eval_result.
             4. Applies overflow → exemption-day conversion math.
             5. Writes new demerit_points, overflow_points, exemption_days.
             6. Sends formatted Telegram report.

23:35 IST — Late phone demerit. Skips on exemption days. Else if late: -1 pt.

00:00 IST — Midnight reset. Zeros 7 usage counters + 5 daily booleans
             (incl. jarvis_holiday_today) + clears jarvis_gym_entered_at.
             Persists: demerit_points, overflow_points, exemption_days,
             pre_eval_points.
```

### Punishment enforcement

```
On state change of EITHER sensor.demerit_zone OR input_boolean.exemption_today:
  → automation.jarvis_punishment_enforcer
  → calls script.jarvis_sync_adguard_rules
  → script computes effective zone:
       if exemption_today is on:  effective zone = 'green' (all blocks lifted)
       else:                       effective zone = states('sensor.demerit_zone')
  → builds custom filtering rules from domain lists for effective zone
  → POST to AdGuard /control/filtering/set_rules
  → updates jarvis_last_adguard_sync

Every 15 minutes (drift correction):
  → automation.jarvis_adguard_periodic_sync
  → calls jarvis_sync_adguard_rules anyway (same exemption-aware logic)

AdGuard then matches DNS queries from the phone (by IP 192.168.0.47 on LAN
or 100.70.157.25 on Tailscale) to persistent client "Danny S23" and applies
the per-client custom rules. End-to-end verified May 2 2026; exemption
override verified May 3 2026.

Midnight transition: when input_boolean.exemption_today flips off as part
of the midnight reset, the enforcer fires (state change trigger) and the
sync script pushes rules for the actual current zone — so old blocks
return automatically if points are still low.
```

### Health monitoring

```
Every 30 min:
  → automation.jarvis_health_watchdog
  → if Tasker poll >15 min stale OR AdGuard sync >30 min stale:
     → Telegram alert (with 6h cooldown via jarvis_last_health_alert)
```

---

## 4. HA Entities — exhaustive inventory

### input_number helpers

#### Points & exemption
| Entity | Min | Max | Unit | Purpose |
|---|---|---|---|---|
| `input_number.demerit_points` | 0 | 12 | pts | Main point balance. |
| `input_number.exemption_days` | 0 | 999 | days | Unused exemption bank. Currently 4. |
| `input_number.overflow_points` | 0 | 5 | pts | Progress toward next exemption (6 → 1). |
| `input_number.pre_eval_points` | 0 | 12 | pts | Snapshot before nightly eval. Used by exemption script for post-eval rollback. |

#### Tunables (seven — edit live, no restart needed)
| Entity | Default | Unit | Purpose |
|---|---|---|---|
| `input_number.jarvis_points_max` | 12 | pts | Ceiling for demerit_points. Read by eval. |
| `input_number.jarvis_points_per_exemption` | 6 | pts | Overflow → exemption conversion ratio. |
| `input_number.jarvis_screen_limit_normal` | 120 | min | Screen-time limit on normal days. |
| `input_number.jarvis_screen_limit_relaxed` | 210 | min | Screen-time limit on relaxed days. |
| `input_number.jarvis_gym_min_minutes` | 20 | min | Min gym time to count as a visit. |
| `input_number.jarvis_guitar_target_minutes` | 20 | min | Min guitar time to earn +1. |
| `input_number.jarvis_steps_target` | 8000 | steps | Daily step count target for +2 bonus. Min 1000, max 30000, step 500. Source: `sensor.garmin_connect_steps` (Garmin Connect HACS integration). |

#### Usage counters (all 0–1440 min)
| Entity | Notes |
|---|---|
| `input_number.phone_youtube_usage` | YouTube minutes today |
| `input_number.phone_netflix_usage` | Netflix minutes today |
| `input_number.phone_prime_video_usage` | Prime Video minutes today |
| `input_number.phone_instagram_usage` | Instagram minutes today |
| `input_number.phone_jiohotstar_usage` | JioHotstar minutes today |
| `input_number.phone_brave_usage` | Brave minutes today (counts toward screen, never blocked) |
| `input_number.phone_guitar_usage` | JustinGuitar minutes today (goal: ≥`jarvis_guitar_target_minutes`) |

#### Cleaned up (no longer exists)
- `input_number.phone_chrome_usage` — deleted. Matching `chrome` entry also removed from `app_map` in the bulk-update automation.
- `input_number.last_tracked_timestamp` — deleted.
- `input_text.last_tracked_app` — deleted.
- `input_boolean.tasks_completed_today_2` — was the entity_id under which the tasks helper was registered as of the May 2 audit. Helper id was always `tasks_completed_today` (immutable backing id) but the entity_id had been renamed at some point to `..._2`, leaving every reference (script, automations, eval, routing templates, dashboard) pointing to a non-existent `input_boolean.tasks_completed_today` and silently failing the tasks habit. Renamed back to `input_boolean.tasks_completed_today` on May 3, 2026 — entity now exists, defaults to `off`, all consumers work as written. (The May 2 handoff had falsely claimed `..._2` was deleted; that didn't happen — only this May 3 rename actually fixed the entity_id mismatch.)

### input_boolean helpers
| Entity | Purpose |
|---|---|
| `input_boolean.gym_visited_today` | Set by Gym Exit Detected if duration ≥ min. Midnight reset clears. |
| `input_boolean.phone_used_late` | Flipped on by late-phone webhook. Midnight reset clears. |
| `input_boolean.exemption_today` | Declared via `script.mark_exemption_today`. Skips eval + warnings + late demerit AND lifts all AdGuard blocks for the day (sync script forces effective zone to green). Midnight reset clears. |
| `input_boolean.tasks_completed_today` | Set via `script.mark_tasks_done` (called by `/tasks_done`). +1 if on, +0 if off. Midnight reset clears. |
| `input_boolean.jarvis_holiday_today` | Soft day. Raises screen limit. Other rules unchanged. Midnight reset clears. |
| `input_boolean.adguard_blocked` | Set by `script.jarvis_sync_adguard_rules` — `on` when effective zone is not green (i.e., AdGuard punishment is active). Used by dashboard zone card. NOT reset at midnight (persists until zone changes). |

### input_datetime helpers
| Entity | Purpose |
|---|---|
| `input_datetime.jarvis_gym_entered_at` | Set by Gym Entry, read by Gym Exit for duration. Reset to epoch on exit and at midnight. |
| `input_datetime.jarvis_last_tasker_poll` | Updated every successful bulk-update webhook. |
| `input_datetime.jarvis_last_adguard_sync` | Updated every successful AdGuard rules push. |
| `input_datetime.jarvis_last_health_alert` | Cooldown tracker for Health Watchdog. |

### Template sensors and binary sensors

**Important:** template sensors are defined in **two different places**. See Section 7 for the full breakdown.

| Entity | Defined in | Formula |
|---|---|---|
| `sensor.phone_screen_time_total` | `configuration.yaml` | Sum of **6** counters: YT + Netflix + Prime + IG + Hotstar + Brave. Unit: min. |
| `sensor.demerit_zone` | `configuration.yaml` | green (≥9) / yellow (≥6) / orange (≥3) / red (0–2). Drives Punishment Enforcer. **Fail-silent default:** `int(12)` — if `demerit_points` is unavailable, zone defaults to green (no blocks). This is intentional for the punishment path: a sensor outage should not accidentally block apps. Contrast with the eval script which defaults to `int(0)` (fail-loud for scoring). |
| `sensor.jarvis_screen_limit_today` | UI helper | `jarvis_screen_limit_relaxed` if `jarvis_relaxed_day` on, else `jarvis_screen_limit_normal`. Unit: min. |
| `binary_sensor.jarvis_relaxed_day` | UI helper | on if weekend OR `jarvis_holiday_today` on. |
| `sensor.jarvis_minutes_since_tasker_poll` | UI helper | `(now - jarvis_last_tasker_poll) / 60`, rounded. Unit: min. |
| `sensor.jarvis_minutes_since_adguard_sync` | UI helper | `(now - jarvis_last_adguard_sync) / 60`, rounded. Unit: min. |
| `binary_sensor.jarvis_screen_counting_active` | UI helper | `on` when Tasker data is fresh (last poll ≤15 min ago). Shown on dashboard as a data-freshness indicator. Created ~May 15, 2026. |

### Stable view sensors (read-only abstraction layer for dashboard + OpenClaw)

All 13 are **UI helpers** (Section 7), not yaml. Each wraps a raw entity with a stable ID:

| View entity | Wraps |
|---|---|
| `sensor.jarvis_demerit_points_view` | `input_number.demerit_points` |
| `sensor.jarvis_exemption_days_view` | `input_number.exemption_days` |
| `sensor.jarvis_overflow_points_view` | `input_number.overflow_points` |
| `binary_sensor.jarvis_gym_status_view` | `input_boolean.gym_visited_today` |
| `sensor.jarvis_guitar_view` | `input_number.phone_guitar_usage` |
| `binary_sensor.jarvis_phone_late_view` | `input_boolean.phone_used_late` (inverted: on means "phone off late" success) |
| `binary_sensor.jarvis_tasks_view` | `input_boolean.tasks_completed_today` |
| `sensor.jarvis_youtube_view` | `input_number.phone_youtube_usage` |
| `sensor.jarvis_instagram_view` | `input_number.phone_instagram_usage` |
| `sensor.jarvis_netflix_view` | `input_number.phone_netflix_usage` |
| `sensor.jarvis_prime_view` | `input_number.phone_prime_video_usage` |
| `sensor.jarvis_hotstar_view` | `input_number.phone_jiohotstar_usage` |
| `sensor.jarvis_brave_view` | `input_number.phone_brave_usage` |

When refactoring internals, the dashboard and OpenClaw templates keep working because they read from these views.

**Note on steps:** The steps habit reads directly from `sensor.garmin_connect_steps` (Garmin Connect HACS integration) — there is no `input_number` usage counter or view sensor for steps. The eval script reads the garmin sensor at eval time and writes the result to `input_number.daily_steps_result` for history charting only.

### Zone, person, device tracker
| Entity | Notes |
|---|---|
| `zone.gym` | lat <YOUR_GYM_LAT>, lng <YOUR_GYM_LNG>, radius 49m |
| `person.danny` | Tracked via `device_tracker.danny_s23` (HA companion app). |
| `device_tracker.danny_s23` | GPS source. Becomes "Gym" inside the zone. |
| `sensor.danny_s23_wi_fi_connection` | Current WiFi SSID. Used by Gym Entry as GPS-drift guard. |

### AdGuard switches and integration sensors
- `switch.adguard_home_protection_2` — master kill switch. If off, no DNS filtering at all.
- `switch.adguard_home_filtering_2` — filtering subsystem. If off, custom rules don't apply (rules are filtering rules, not blocked services). **Both must be ON.**
- `switch.adguard_home_query_log_2` — query log toggle. Must be ON for the query-log probes (Section 17) to work.
- `sensor.adguard_home_dns_queries_2` — total DNS queries (cumulative).
- `sensor.adguard_home_dns_queries_blocked_2` — blocked queries (cumulative).
- `sensor.adguard_home_dns_queries_blocked_ratio_2` — block rate %.
- `sensor.adguard_home_average_processing_speed_2` — ms.

These last four are aggregate stats from the HA AdGuard Home integration — useful at-a-glance health signals on the dashboard, but they don't tell you per-client behavior. For per-client info use the `adguard_get` rest_command (Section 17).

---

## 5. HA Automations — all 12 (verified May 17 2026)

All automations live under category `01KQ8475KY5WD3511F1HYD02KT`.

### 5.1 `automation.jarvis_phone_usage_stats_bulk_update`
- **Trigger:** webhook `<YOUR_BULK_WEBHOOK_ID>`, POST, `local_only: false`
- **Mode:** queued, max 5
- **Logic:** Iterates `app_map` (a `variables:` list of `{entity, key}` pairs). For each pair, if `trigger.json[key] is defined`, calls `input_number.set_value` on the entity. After loop, updates `input_datetime.jarvis_last_tasker_poll`.
- **Current `app_map` keys:** youtube, instagram, netflix, prime, hotstar, brave, guitar (7 entries — chrome was removed in the May 2 cleanup).
- **Polling interval:** Tasker fires every ~2 min (Tasker XML: `rep: 2`, `repval: 2`). The HA automation description still says "~90s" — see OF-9 in §13.
- **No payload validation:** values are passed through `float(0) | round(0)` but not range-checked. Out-of-range values will be rejected by HA's `input_number.set_value` (entities have min:0 / max:1440) but the rejection is silent — the automation logs an error and continues, and `jarvis_last_tasker_poll` still updates. A malformed payload would leave stale data while appearing healthy to the Watchdog.
- **Adding a new tracked app:** add one `{entity, key}` entry to `app_map`. (Plus the upstream Tasker change, plus add to screen-time formula if applicable.)

### 5.2 `automation.jarvis_gym_entry_detected`
- **Trigger:** zone enter — `person.danny` → `zone.gym`
- **Condition:** WiFi must be disconnected (`sensor.danny_s23_wi_fi_connection` in `['<not_connected>', 'unavailable', 'unknown']`). GPS-drift guard.
- **Logic:** Sets `input_datetime.jarvis_gym_entered_at` to current timestamp.
- **Restart-safe:** state survives HA restarts because it's in a helper.

### 5.3 `automation.jarvis_gym_exit_detected`
- **Trigger:** zone leave — `person.danny` ← `zone.gym`
- **Condition:** entry timestamp > 0 (otherwise nothing to compute against)
- **Logic:**
  - Computes `minutes_at_gym = (now - jarvis_gym_entered_at) / 60`.
  - If ≥ `jarvis_gym_min_minutes`: turn on `gym_visited_today`, send Telegram "💪 confirmed".
  - Else: send Telegram "🏃 too short, no credit".
  - Always: clear `jarvis_gym_entered_at` to epoch.

### 5.4 `automation.jarvis_late_phone_usage`
- **Trigger:** webhook `<YOUR_LATE_PHONE_WEBHOOK_ID>`, POST, `local_only: false`
- **Condition:** `phone_used_late` is off (idempotent)
- **Logic:** Flips `phone_used_late` on.

### 5.5 `automation.jarvis_screen_time_warnings`
- **Trigger:** four `template` triggers at 50% / 75% / 92% / 100% of `sensor.jarvis_screen_limit_today`. Edge-triggered (false → true), so each level alerts once per day.
- **Condition:** `exemption_today` off
- **Logic:** Choose-block by trigger ID, sends tiered Telegram warning. Includes "(relaxed day)" suffix when applicable.

### 5.6 `automation.jarvis_house_tasks_prompt`
- **Trigger:** time 22:30:00 IST
- **Conditions:** `exemption_today` off, `jarvis_holiday_today` off, `tasks_completed_today` off
- **Logic:** Sends Telegram message with **inline keyboard buttons** via `rest_command.jarvis_send_message_keyboard`. The message asks "Did you finish your house tasks?" and presents two buttons: **"Tasks Done"** and **"Tasks Not Done"**. Button callback data is routed by OpenClaw to `script.mark_tasks_done` (for "Tasks Done") or acknowledged with no state change (for "Tasks Not Done"). This replaced the older text-reply `/tasks_done` prompt.

### 5.7 `automation.jarvis_nightly_report_10_45_pm` (friendly name: "Nightly Report 11:20 PM")
- **Trigger:** time 23:20:00 IST
- **Logic:**
  1. Save current points to `pre_eval_points`.
  2. **Exemption branch** (if `exemption_today` on): call `jarvis_compute_daily_eval` for read-only stats, send "exemption used" Telegram, stop.
  3. **Normal branch:**
     - Call `script.jarvis_compute_daily_eval` → `r` (response_variable).
     - Read tunables: `jarvis_points_max`, `jarvis_points_per_exemption`.
     - `earned_overflow = max(0, r.would_be_pts - points_max)`
     - `new_pts = clamp(0, points_max, r.would_be_pts)`
     - `total_overflow = current_overflow + earned_overflow`
     - `exemptions_earned = total_overflow // points_per_exemption`
     - `new_overflow = total_overflow % points_per_exemption`
     - `new_exemption_days = current_exempt + exemptions_earned`
     - Write `demerit_points`, `overflow_points`, `exemption_days`.
     - Write **6 daily result helpers** for trend charting: `daily_gym_result`, `daily_guitar_result`, `daily_screen_result`, `daily_tasks_result`, `daily_steps_result`, `daily_total_delta`.
  4. Send formatted Telegram report including "🌴" badge if relaxed day. Steps shown with ⬜ icon (bonus-only habit).
- **Note:** The old hardcoded `2026-04-22` date override is GONE. Logic is clean.
- **Defensive default (May 6, 2026):** the `pre_eval_points` snapshot writes `int(0)` instead of `int(12)` when `demerit_points` is unavailable. Keeps the snapshot honest about state loss instead of recording a fake "max" reading.

### 5.8 `automation.jarvis_late_phone_demerit`
- **Trigger:** time 23:35:00 IST
- **Conditions:** `phone_used_late` on AND `exemption_today` off
- **Logic:** `new_pts = max(0, current - 1)`; write; Telegram.
- **Defensive default (May 6, 2026):** `current_pts` and `new_pts` defaults changed from `int(12)` → `int(0)`. If `demerit_points` is unavailable, the deduction lands at 0 (red zone, loud failure) rather than 11 (silent fake-good).

### 5.9 `automation.jarvis_punishment_enforcer`
- **Triggers (two, OR'd):** state change on `sensor.demerit_zone` AND state change on `input_boolean.exemption_today`. Zone-change covers normal points-driven re-blocks; exemption-flip covers both directions of the exemption boundary (declare → unblock; midnight reset → re-block per actual zone).
- **Logic:** Single action — call `script.jarvis_sync_adguard_rules`. The script reads both `sensor.demerit_zone` and `input_boolean.exemption_today` itself, and forces effective zone to green if exempt.

### 5.10 `automation.jarvis_adguard_periodic_sync`
- **Trigger:** time pattern `minutes: "/15"` (every 15 min)
- **Logic:** Re-pushes current zone's rules. Catches drift from AdGuard restarts, manual UI edits, or missed state changes.

### 5.11 `automation.jarvis_health_watchdog`
- **Trigger:** time pattern `minutes: "/30"` (every 30 min)
- **Monitors three things** (alerts if any are unhealthy):
  1. **Tasker poll staleness** — `sensor.jarvis_minutes_since_tasker_poll > 15`.
  2. **AdGuard sync staleness** — `sensor.jarvis_minutes_since_adguard_sync > 30`.
  3. **Disabled Jarvis automations** — any of the 11 monitored automations is in state `off`. The list is hard-coded in the automation's `variables:` block: bulk-update, gym entry, gym exit, late-phone webhook, screen-time warnings, house-tasks prompt, nightly report, late-phone demerit, punishment enforcer, AdGuard periodic sync, midnight reset.
- **Cooldown:** 6h between alerts (`jarvis_last_health_alert`). One alert per condition per 6h, so a Tasker outage won't spam the channel.
- **Logic:** Sends a Telegram alert listing whichever of the three signals is currently failing, with remediation hints. Updates `jarvis_last_health_alert`.
- **Note:** the disabled-automation check (added during the May 6 audit) caught a real risk — a one-tap dashboard switch could disable critical automations silently. The Watchdog now surfaces these within 30 minutes.

### 5.12 `automation.jarvis_midnight_reset`
- **Trigger:** time 00:00:00 IST
- **Logic:**
  - Zero seven `input_number` counters: YT, Netflix, Prime, IG, Hotstar, Guitar, Brave.
  - Turn off five booleans: `gym_visited_today`, `phone_used_late`, `exemption_today`, `jarvis_holiday_today`, `tasks_completed_today`.
  - Reset `input_datetime.jarvis_gym_entered_at` to epoch.
- **Carry-over:** `demerit_points`, `overflow_points`, `exemption_days`, `pre_eval_points`, all health datetimes.

---

## 6. HA Scripts

### 6.1 `script.jarvis_compute_daily_eval` (pure function)
- **Purpose:** Computes daily eval deltas without mutating any state. Returns full snapshot via `response_variable: eval_result`.
- **Inputs read:** `demerit_points`, `phone_guitar_usage`, `jarvis_guitar_target_minutes`, `gym_visited_today`, `jarvis_screen_limit_today`, `phone_screen_time_total`, `jarvis_relaxed_day`, `tasks_completed_today`, `sensor.garmin_connect_steps`, `jarvis_steps_target`, plus all 6 app counters for the breakdown.
- **Output dict (`eval_result`):**
  - `current_pts`, `gym_done`/`gym_delta`, `guitar_min`/`guitar_done`/`guitar_delta`, `screen_total`/`screen_limit`/`screen_ok`/`screen_delta`, `tasks_done`/`tasks_delta`, `steps_count`/`steps_target`/`steps_done`/`steps_delta`, `total_delta`, `would_be_pts`, `is_relaxed_day`, `breakdown` (per-app minutes).
- **Steps scoring:** `steps_delta = +2` if `steps_count >= steps_target`, else `0`. Bonus-only — never penalizes. `total_delta = gym + guitar + screen + tasks + steps`.
- **Test in isolation:** `ha_call_service('script', 'jarvis_compute_daily_eval', return_response=True)`.
- **Mode:** single.
- **Defensive default (May 6, 2026):** `current_pts` defaults to `0` (not `12`) when `input_number.demerit_points` is unavailable. Eval will then compute against zero baseline, yielding low `would_be_pts` and triggering punishment. Fail-loud over fail-silent.
- **Cleanup (May 6, 2026):** the redundant outer `total_delta` and `would_be_pts` variables were removed from the script's variables block. They had been dead code — only the equivalents inside `eval_result.*` are referenced by the caller. The script is now visibly the simple pure function it was always meant to be: 4 variable steps + 1 stop with response_variable.

### 6.2 `script.jarvis_sync_adguard_rules`
- **Purpose:** Single source of truth for AdGuard custom rules. Reads `sensor.demerit_zone` AND `input_boolean.exemption_today`, computes effective zone (green if exempt, else the actual zone), builds appropriate domain list, pushes to AdGuard via `rest_command.adguard_set_custom_rules`.
- **Effective zone computation (in script `variables:`):**
  ```jinja
  zone: "{% if is_state('input_boolean.exemption_today', 'on') %}green{% else %}{{ states('sensor.demerit_zone') | trim }}{% endif %}"
  ```
- **Domain lists (defined inside the script's `variables:`):**
  - **yellow_domains (7):** youtube.com, ytimg.com, googlevideo.com, youtu.be, instagram.com, cdninstagram.com, fbcdn.net
  - **orange_additions (7):** netflix.com, nflxvideo.net, nflxext.com, primevideo.com, amazonvideo.com, aiv-cdn.net, aiv-delivery.net
  - **red_additions (6):** hotstar.com, hotstarext.com, jiohotstar.com, disneyplus.com, disney-plus.net, dssott.com
  - **always_allow_patterns:** `/whatsapp-cdn.*\.fbcdn\.net/` (regex carve-out — fbcdn is otherwise blocked at yellow)
  - **Not blocked at any tier:** TikTok, Twitch, Reddit, Snapchat — removed from all lists (were never applicable to Danny's usage).
- **Generates:** Block lines `||domain^$client='Danny S23'` plus allow lines `@@regex$client='Danny S23'`.
- **Updates:** `input_datetime.jarvis_last_adguard_sync` and `input_boolean.adguard_blocked` (on if effective zone ≠ green, off otherwise).
- **Idempotent.** Mode: queued, max 5.
- **To change blocked domains:** edit the lists in this script. No automation/rest_command changes needed.
- **Verification:** `ha_call_service('rest_command', 'adguard_get', data={'path':'filtering/status'}, return_response=True)` returns `user_rules` — confirms what's actually loaded vs what was pushed.

### 6.3 `script.mark_exemption_today`
- **Purpose:** Declare today an exemption day.
- **Refuses if:** already exempt OR zero exemption days.
- **Actions:**
  - Turn on `exemption_today`, decrement `exemption_days`, send confirmation.
  - **Post-eval rollback:** if called after 23:20 IST, restore `demerit_points` from `pre_eval_points` and notify.
- **Mode:** single.
- **Note:** Exemption now pauses *evaluation* AND lifts AdGuard blocks for the day. The sync script forces effective zone to green when `exemption_today` is on, regardless of actual points. At midnight the boolean flips off (midnight reset), the punishment enforcer re-fires (state change trigger), and the sync pushes rules for the actual current zone — old blocks return automatically if points are still low. (Prior to May 3, 2026, exemption only paused eval; blocks remained in place. That behavior is gone.)
- **Defensive default (May 6, 2026):** the rollback now defaults to `states('input_number.demerit_points') | int(0)` (i.e. current value, no-op on failure) instead of `int(12)`. If `pre_eval_points` is somehow unavailable when the rollback fires, it leaves `demerit_points` alone instead of overwriting with a fake max value.
- **Known minor (non-blocking):** the post-eval check uses `{{ now().hour > 23 or (now().hour == 23 and now().minute >= 20) }}`. HA's native `condition: time, after: "23:20:00"` would be cleaner; logically equivalent, deferred as cosmetic.

### 6.4 `script.jarvis_mark_holiday_today`
- **Purpose:** Declare a soft day. Raises screen-time limit to `jarvis_screen_limit_relaxed` (210 min). Other rules unchanged.
- **Refuses if:** already holiday.
- **Actions:** Turn on `jarvis_holiday_today`, send confirmation.
- **Auto-clears:** at midnight reset.
- **Companion to** `mark_exemption_today` but distinct: holiday ≠ exemption. Holiday still scores you, just with a softer screen budget.

### 6.5 `script.mark_tasks_done`
- **Purpose:** Confirms house tasks done today. Idempotent.
- **Refuses if:** already on.
- **Actions:** Turn on `tasks_completed_today`, send confirmation.
- **Caller:** OpenClaw routing on `/tasks_done`. Also wired to a dashboard tile tap-action.

---

## 7. Where each template sensor and rest_command lives

This was a recurring point of confusion in earlier handoffs. The system has **20 template-derived sensors** for the habits module, but they're defined in two completely different places.

### 7.1 In `configuration.yaml` (the on-disk file Danny edits) — 2 template sensors

```yaml
template:
  - sensor:
      - name: "Phone Screen Time Total"
        unique_id: phone_screen_time_total
        unit_of_measurement: "min"
        state: >
          {{ (states('input_number.phone_youtube_usage') | float(0)
            + states('input_number.phone_netflix_usage') | float(0)
            + states('input_number.phone_prime_video_usage') | float(0)
            + states('input_number.phone_instagram_usage') | float(0)
            + states('input_number.phone_jiohotstar_usage') | float(0)
            + states('input_number.phone_brave_usage') | float(0)) | round(0) }}

      - name: "Demerit Zone"
        # green ≥9, yellow ≥6, orange ≥3, red 0-2
```

### 7.2 As UI template helpers — 18 entries

Created via **Settings → Devices & Services → Helpers → Create helper → Template**. Stored as `domain=template` config entries (in HA's storage backend, included in normal HA backups). Do **not** appear in any yaml file. To inspect or edit any of them: Settings → Devices & Services → Helpers → search "Jarvis" → click → Configure.

*Functional templates (5):*
- `binary_sensor.jarvis_relaxed_day` — title "Jarvis Relaxed Day"
- `sensor.jarvis_screen_limit_today` — title "Jarvis Screen Limit Today"
- `sensor.jarvis_minutes_since_tasker_poll` — title "Jarvis Minutes Since Tasker Poll"
- `sensor.jarvis_minutes_since_adguard_sync` — title "Jarvis Minutes Since AdGuard Sync"
- `binary_sensor.jarvis_screen_counting_active` — title "Jarvis Screen Counting Active". Tasker data freshness indicator (`on` when last poll ≤15 min ago). Created ~May 15, 2026.

*View wrappers (13):*
- `sensor.jarvis_demerit_points_view`, `sensor.jarvis_exemption_days_view`, `sensor.jarvis_overflow_points_view`
- `binary_sensor.jarvis_gym_status_view`, `sensor.jarvis_guitar_view`, `binary_sensor.jarvis_phone_late_view`, `binary_sensor.jarvis_tasks_view`
- `sensor.jarvis_youtube_view`, `sensor.jarvis_instagram_view`, `sensor.jarvis_netflix_view`, `sensor.jarvis_prime_view`, `sensor.jarvis_hotstar_view`, `sensor.jarvis_brave_view`

If you need to see the formula behind a UI helper without opening the UI, you can query it via MCP: `ha_get_integration(domain="template")` lists every entry; passing a specific `entry_id` with `include_schema=True` returns the formula stored in `options_schema.data_schema`.

### 7.3 rest_commands (in `configuration.yaml`)

All credentials are stored in `secrets.yaml` via `!secret` references (migrated as of May 2026). The Telegram bot token and chat ID are bundled into a single secret `telegram_jarvis_send_url` (the full API URL). AdGuard basic-auth is stored as `adguard_basic_auth`.

```yaml
rest_command:
  jarvis_send_message:
    url: !secret telegram_jarvis_send_url
    method: POST
    payload: '{"text": "{{ message }}", "parse_mode": "Markdown"}'
    content_type: "application/json"

  jarvis_send_message_keyboard:
    url: !secret telegram_jarvis_send_url
    method: POST
    payload: '{"text": "{{ message }}", "parse_mode": "Markdown", "reply_markup": {{ reply_markup }}}'
    content_type: "application/json"
    # Used by house tasks prompt (§5.6) for inline keyboard buttons.

  adguard_set_custom_rules:
    url: "http://192.168.0.122/control/filtering/set_rules"
    method: POST
    headers:
      Authorization: !secret adguard_basic_auth
      Content-Type: "application/json"
    payload: '{"rules": {{ rules | tojson }}}'
    content_type: "application/json"

  adguard_get:
    url: "http://192.168.0.122/control/{{ path }}"
    method: GET
    headers:
      Authorization: !secret adguard_basic_auth
```

Six rest_commands total: `jarvis_send_message`, `jarvis_send_message_keyboard`, `adguard_set_custom_rules`, `adguard_get`, plus two unrelated (`adguard_block_maria_ipad`, `adguard_unblock_maria_ipad`) for the iPad battery automation. The four legacy zone-specific rest_commands (`adguard_block_yellow / _orange / _red / _unblock_all`) are confirmed gone.

`adguard_get` is the read counterpart to `adguard_set_custom_rules`. See Section 17 for usage.

**YAML gotcha (lesson learned, May 2):** when adding a new entry to `rest_command:`, indent it at exactly 2 spaces (sibling level), with its inner fields at 4 spaces. Indenting at 4 spaces makes it a sub-key of the previous command, and the entire `rest_command:` integration fails to load — silently breaking `jarvis_send_message`, `adguard_set_custom_rules`, and the iPad block/unblock commands all at once. If Telegram messages stop arriving and AdGuard sync starts failing simultaneously, check `ha_get_logs(source="system", level="ERROR")` for `Setup failed for 'rest_command'`.

---

## 8. Telegram / Jarvis setup

- **Bot token + chat ID:** bundled into `secrets.yaml` as `telegram_jarvis_send_url` (the full `https://api.telegram.org/bot.../sendMessage?chat_id=...` URL). Referenced by `rest_command.jarvis_send_message` and `rest_command.jarvis_send_message_keyboard` via `!secret`. **Do not paste tokens or chat IDs into documentation or shared files.**
- **AdGuard auth:** stored in `secrets.yaml` as `adguard_basic_auth`. Referenced by `rest_command.adguard_set_custom_rules` and `rest_command.adguard_get`.
- Only ONE polling client per token — OpenClaw polls. HA sends only.

---

## 9. Tasker setup on the S23

### Profile 1: Bulk Usage Polling
- **Trigger:** Periodic (~120s — observed via trace timestamps)
- **Task:** Collects usage stats for tracked apps, POSTs to `/api/webhook/<YOUR_BULK_WEBHOOK_ID>` with flat JSON. Keys: `youtube`, `instagram`, `netflix`, `prime`, `hotstar`, `brave`, `guitar`. Values in minutes.

### Profile 2: Late Phone Usage Alert
- **Triggers:** Display On + Time context 23:30–04:59
- **Task:** POST to `/api/webhook/<YOUR_LATE_PHONE_WEBHOOK_ID>` with `{"event":"screen_on_late","time":"%TIME","device":"danny_s23"}`.

### Tracked packages (for reference when extending)
| App | Package |
|---|---|
| YouTube | `com.google.android.youtube` |
| Instagram | `com.instagram.android` |
| Netflix | `com.netflix.mediaclient` |
| Prime Video | `com.amazon.avod` |
| JioHotstar | `in.startv.hotstar` |
| Brave | `com.brave.browser` `[INFER]` |
| JustinGuitar | `net.musopia.fourchordsjustin` |

(Chrome was previously tracked but the entity was removed; Tasker no longer sends the key.)

**⚠️ Dual-IP inconsistency (identified May 10):** The Tasker XML reveals the bulk usage webhook (`Send All to HA`) posts to Tailscale IP `100.107.164.26:8123`, while the late phone webhook (`Send Late Phone Alert`) posts to LAN IP `192.168.0.124:8123`. If Tailscale drops while on home WiFi, bulk usage stops flowing but late-phone still works (or vice versa). Recommend standardizing both to one IP (Tailscale preferred for off-network coverage). This is an optional fix — see §13.

**Important caveat about screen-time accounting:** Tasker tracks **app foreground time**, not network success. If Danny opens YouTube while in red zone, the DNS query fails (verified — see Section 17), the app fails to load video, but the app is still on screen so Tasker counts the minutes. So `phone_youtube_usage` going up when YT is blocked is expected and correct — it reflects "time staring at a broken app", which is itself a form of time wasted. The system is designed around this.

---

## 10. Dashboard — `jarvis-habits`

URL path `/jarvis-habits`. Sidebar title "Habit Tracker", icon `mdi:shield-account`. Single view with seven sections:

1. **Demerit points** — gauge from `sensor.jarvis_demerit_points_view` (severity green ≥9, yellow ≥6, red ≥3); zone tile.
2. **Exemptions** — `jarvis_exemption_days_view`, `jarvis_overflow_points_view` tiles.
3. **Today's habits** — gym, guitar, screen-time, phone-late, house-tasks tiles. All five now read from `*_view` sensors (the tasks tile uses `binary_sensor.jarvis_tasks_view` as of May 6, 2026 — symmetric with the others). The tasks tile keeps its existing `tap_action: script.mark_tasks_done` for one-tap confirmation; long-press shows entity info.
4. **App usage breakdown** — six `*_view` tiles (YT, IG, Netflix, Prime, Hotstar, Brave).
5. **Today mode** — `jarvis_holiday_today` (tap → `script.jarvis_mark_holiday_today`), `exemption_today` (tap → `script.mark_exemption_today`), `jarvis_relaxed_day` status, `jarvis_screen_limit_today` value.
6. **System health** — `switch.adguard_home_filtering_2` (must be ON; `tap_action: more-info`, `hold_action: toggle` with confirmation dialog as of May 6, 2026 — a single accidental tap can no longer silently disable all punishment blocks), Tasker poll age, AdGuard sync age, last health alert.
7. **Tunables (edit live, no restart)** — all six `input_number.jarvis_*` threshold helpers.

---

## 11. Demerit math — exhaustive

All thresholds are read from tunable entities at eval time, not hardcoded.

### Daily evaluation (at 23:20 IST)

```
gym_delta    = +1 if gym_visited_today else -2
guitar_delta = +1 if phone_guitar_usage >= jarvis_guitar_target_minutes else -1
screen_delta = +1 if phone_screen_time_total <= jarvis_screen_limit_today else -2
tasks_delta  = +1 if tasks_completed_today else 0
steps_delta  = +2 if garmin_connect_steps >= jarvis_steps_target else 0   # bonus-only
total_delta  = gym_delta + guitar_delta + screen_delta + tasks_delta + steps_delta

would_be_pts    = current_pts + total_delta
earned_overflow = max(0, would_be_pts - jarvis_points_max)
new_pts         = clamp(0, jarvis_points_max, would_be_pts)

total_overflow      = current_overflow + earned_overflow
exemptions_earned   = total_overflow // jarvis_points_per_exemption
new_overflow        = total_overflow % jarvis_points_per_exemption
new_exemption_days  = current_exemption + exemptions_earned
```

### Late phone (at 23:35 IST)
```
if phone_used_late AND NOT exemption_today:
  demerit_points -= 1   # floors at 0
```

### Daily range
- **Max daily gain: +6** (gym +1, guitar +1, screen +1, tasks +1, steps +2). Late phone can only deduct.
- **Max daily loss: -6** (gym -2, guitar -1, screen -2, late -1). Tasks and steps never penalize.
- On a relaxed day, `screen_delta` is more forgiving because the limit is higher (210 vs 120).

### Zones (drives AdGuard via Punishment Enforcer)
| Points | Zone | Custom rules pushed for "Danny S23" |
|---|---|---|
| 9–12 | green | none |
| 6–8 | yellow | YouTube + Instagram domains (7 domains) |
| 3–5 | orange | + Netflix, Prime Video (7 additional domains) |
| 0–2 | red | + Hotstar, JioHotstar, Disney+ (6 additional domains) |

Plus: WhatsApp CDN is always allowed (carve-out from fbcdn block) — but only emitted when there are block rules to apply (the script returns an empty rule set on green, so the carve-out only appears in yellow/orange/red).

**Exemption override:** when `input_boolean.exemption_today` is on, the sync script forces effective zone to green regardless of actual points/zone — *all* blocks lifted for the day. At midnight when exemption flips off, the punishment enforcer fires and re-pushes rules for the actual zone.

---

## 12. OpenClaw routing status

Active. Jarvis short-circuits **bare-word natural-language triggers** by calling HA's `/api/template` (read commands) or `/api/services/script/<name>` (write commands) directly, bypassing Claude. The 10 implemented triggers are: `status`, `points`, `screen`, `habits`, `exempt`, `exempt status`, `holiday`, `tasks_done`, `health`, `help habits` (plus natural variations like "what's my status", "show points", "soft day", "system health"). Note these are **bare words, NOT slash commands** — `/`-prefixed forms clash with OpenClaw built-ins like `/exec` and `/elevated`. The Routing Guide (`OpenClaw_HA_Routing_Guide.md`) uses `/`-prefixes as section headers / spec convention only; the actual matcher source is Jarvis-side `habits-commands.md`.

To test: send `status` to Jarvis on Telegram. Instant reply with the dashboard summary = routing is active.

The routing templates use `sensor.jarvis_*_view` entities throughout for refactor-stability (including `binary_sensor.jarvis_tasks_view` as of May 6, 2026).

---

## 13. Known issues & gotchas

| Issue | Status | Fix |
|---|---|---|
| Plex never implemented | **Outstanding** | Need to add Plex domains to `red_additions` (or a new tier) inside `script.jarvis_sync_adguard_rules`. |
| Brave package name unverified | **Outstanding** | Assumed `com.brave.browser` — verify on phone. |
| `switch.adguard_home_filtering_2` must be ON | **Operational** | The custom-rules mechanism uses filtering rules. If filtering is off, blocks don't apply even if protection is on. The Health Watchdog now alerts if any monitored automation is disabled, but this is a *switch*, not an automation — staleness on `jarvis_last_adguard_sync` won't fire either because the periodic sync still succeeds (rules push but don't apply). The dashboard tile is now hardened (long-press + confirmation) so this should not happen accidentally; document it as an accepted residual risk. |
| ~~Plaintext credentials in `configuration.yaml`~~ | **Resolved (May 17)** | All credentials migrated to `secrets.yaml` via `!secret` references. See §7.3, §8. |
| Phone may bypass AdGuard via Android Private DNS | **Latent risk** | If the phone's "Private DNS" is set to a public DoH (Cloudflare 1.1.1.1, AdGuard public, etc.) instead of "off" or pointing to AdGuard, queries skip AdGuard entirely and our rules are no-ops. Verify on phone: Settings → Connections → More connection settings → Private DNS → should be "Off" or set to your AdGuard hostname. |
| AdGuard colocation with OpenClaw / Plex / qBit | **Architectural / known** | All four services share the `ubuntu-media` VM's CPU. Heavy CPU work on that VM (e.g. long Plex transcodes, qBit hashing, any local LLM inference) can lag DNS resolution for the household. Local-LLM plan was abandoned May 6 after N150 benchmarks (0.75 tok/s on Qwen 2.5 7B); see §15 changelog. If contention symptoms appear, isolate AdGuard to its own VM or LXC. |

### Accepted technical debt (cosmetic; not blocking)

These were flagged in the May 6 audit and consciously deferred — fixing them would require coordinated edits to Jarvis-side files (`habits-commands.md`) at the same time as HA renames, and the upside is naming consistency only. Document and live with them.

| Item | Why it's debt | Why we're keeping it |
|---|---|---|
| `script.mark_exemption_today` lacks the `jarvis_` prefix used by every other script and automation in this system | Naming inconsistency | Renaming touches `habits-commands.md` (Jarvis-side), the dashboard tap_action, and the routing guide simultaneously. Risk > reward for a cosmetic fix. |
| `script.mark_tasks_done` lacks the `jarvis_` prefix | Same as above | Same as above |
| `automation.jarvis_gym_visit_detected` has a stale entity_id (should be `_gym_entry_detected` to match its friendly name and pair with `_gym_exit_detected`) | Leftover from when entry+exit were one combined automation | Renaming would touch Health Watchdog's `monitored_automations` list and break trace history. Cosmetic only. |

If we ever do a coordinated rename session, all three should be done together.

### Optional fixes identified May 10 (require explicit permission)

The following issues were identified during the May 10 live audit. **None are currently breaking** — the system works correctly under normal operating conditions. Each fix requires Danny's explicit approval before implementation because they involve either behavioral changes, credential rotation, or Tasker-side edits that Claude cannot make alone.

| # | Issue | Severity | What's happening | Recommended fix | Who needs to act |
|---|---|---|---|---|---|
| OF-1 | **Screen time fail-silent default in eval** | Design flaw | `screen_total` in `jarvis_compute_daily_eval` defaults to `int(0)` if sensor is unavailable. This means a broken `phone_screen_time_total` sensor would give `screen_ok=True` and `screen_delta=+1` — you'd be **rewarded** for a broken sensor. This contradicts the May 6 "fail-loud over fail-silent" philosophy applied to `current_pts`. | Change `screen_total` default from `int(0)` to `int(9999)` (always over limit on failure = fail-loud). Consider also defaulting `screen_limit` to `int(0)`. | Claude (HA script edit) |
| ~~OF-2~~ | ~~**Credentials in plaintext**~~ | ~~Security hygiene~~ | ~~Resolved May 17.~~ All credentials migrated to `secrets.yaml`. Bot token + chat ID bundled as `telegram_jarvis_send_url`, AdGuard auth as `adguard_basic_auth`. See §7.3, §8. | — | — |
| OF-3 | **Tasker dual-IP inconsistency** | Reliability risk | `Send All to HA` posts to Tailscale IP `100.107.164.26`, `Send Late Phone Alert` posts to LAN IP `192.168.0.124`. If either network path drops, one webhook works and the other fails silently. | Standardize both Tasker tasks to the same IP. Tailscale IP recommended for off-network coverage. | Danny (Tasker edit on phone) |
| OF-4 | **Tasker midnight reset race condition** | Data integrity (~3% nightly probability) | Tasker's "Midnight Reset" profile fires 23:58–00:03. HA's midnight reset fires at 00:00:00. If Tasker sends a bulk update with zeroed values at 23:59, HA counters get prematurely zeroed. If Tasker sends stale pre-reset values at 00:01, yesterday's totals overwrite today's zeroed counters. | Move Tasker's midnight reset to 00:05 IST (safely after HA's reset), OR remove Tasker reset entirely and let HA be the sole authority for counter resets (Tasker would just report cumulative values, and the bulk-update automation would store the latest). | Danny (Tasker edit on phone) |
| OF-5 | **Health Watchdog global cooldown** | Design limitation | The 6h cooldown timer (`jarvis_last_health_alert`) is global across all 3 monitored signals (Tasker stale, AdGuard stale, disabled automations). If signal A triggers an alert, signals B and C are suppressed for 6h even if they fail independently during that window. | Add per-signal cooldown: `jarvis_last_tasker_alert`, `jarvis_last_adguard_alert`, `jarvis_last_automation_alert`. Adds 2 input_datetime helpers and 3 separate cooldown conditions. | Claude (HA automation + helper edits) |
| OF-6 | **Webhook IDs are unauthenticated** | Security gap | `<YOUR_BULK_WEBHOOK_ID>` and `<YOUR_LATE_PHONE_WEBHOOK_ID>` webhooks accept unauthenticated POSTs from any source on the network. Anyone who discovers the webhook ID (documented in this file and Tasker XML) can inject fake usage data or trigger false late-phone flags. | Rotate webhook IDs to long random strings (HA generates these when creating via UI). Treat webhook IDs like passwords — don't document them in plaintext. Add a shared secret in the payload that the automation validates. | Danny (Tasker edit) + Claude (HA automation edit) |
| OF-7 | **`mark_exemption_today` dead code** | Cosmetic | `{{ now().hour > 23 }}` in the post-eval rollback condition is always `false` (hours are 0–23, never >23). The condition still works because `(now().hour == 23 and now().minute >= 20)` covers the real window. | Remove the dead `now().hour > 23 or` prefix, leaving just the `hour == 23 and minute >= 20` check. Alternatively, replace with HA native `condition: time, after: "23:20:00"`. | Claude (HA script edit) |
| OF-8 | **`phone_prime_video_usage` and `phone_brave_usage` input_number mode** | Cosmetic | These two usage counters have `mode: slider` while all other 5 counters have `mode: box`. Inconsistent dashboard appearance. | Change both to `mode: box` via Settings → Helpers. | Claude (HA helper edit) |
| OF-9 | **Bulk update description says "every ~90s"** | Doc/code mismatch | The HA automation description says "Tasker polls usage stats every ~90s" but the Tasker XML configures a 2-minute interval (`rep: 2`, `repval: 2`), and live trace timestamps confirm ~2 min spacing. | Update the automation description from "~90s" to "~2 min". | Claude (HA automation description edit) |
| OF-10 | **Failed login notification from 192.168.0.122** | Investigate | HA has an active persistent notification: "Login attempt or request with invalid authentication from 192.168.0.122" dated May 6. This is the AdGuard/OpenClaw VM. Could be a stale/misconfigured Jarvis long-lived token, or something else on that VM attempting HA access. | Check `ha-token.txt` on the OpenClaw VM. Verify it matches a valid HA long-lived token. Dismiss the notification after resolving. | Danny (VM-side check) |

### Resolved since previous handoff (May 6–17 audit rounds)

- ✅ **OF-2: Credentials migrated to `secrets.yaml`.** Telegram bot token + chat ID bundled as `telegram_jarvis_send_url`, AdGuard basic-auth as `adguard_basic_auth`. All `rest_command` entries now use `!secret` references. No plaintext credentials remain in `configuration.yaml`. Confirmed via backup review May 17, 2026.
- ✅ **Defensive defaults on points reads.** `current_pts | int(12)` → `int(0)` in `script.jarvis_compute_daily_eval`, `automation.jarvis_late_phone_demerit`, and the `pre_eval_points` snapshot in `automation.jarvis_nightly_report_*`. The exemption-rollback in `script.mark_exemption_today` now defaults to current `demerit_points` (no-op fallback) instead of 12. Previously a sensor failure would silently land the user at max points; now it lands at 0 (red zone) and surfaces immediately. Probability of trigger is low (helpers rarely go unavailable) but the design choice now matches accountability-system intent.
- ✅ **Dead code removed from `jarvis_compute_daily_eval`.** The outer-scope `total_delta` and `would_be_pts` variables that mirrored the values inside `eval_result.*` are gone. The script now reads as the simple pure function it always was.
- ✅ **Dashboard AdGuard Filtering tile hardened.** Was `tap_action: toggle` — one accidental tap would silently disable all punishment blocks. Now `tap_action: more-info` + `hold_action: toggle` with a confirmation dialog warning about silent block disabling. The Health Watchdog wouldn't have caught a manual filter-off (sync still runs and updates the timestamp; rules just don't apply), so this was real exposure.
- ✅ **`binary_sensor.jarvis_tasks_view` added.** The dashboard tasks tile was the only habit reading directly from `input_boolean.tasks_completed_today` instead of via a `*_view` wrapper. Symmetry restored. Routing Guide `/habits` template updated to consume the view.
- ✅ **Stale descriptions resynced.** `script.jarvis_sync_adguard_rules` and `automation.jarvis_punishment_enforcer` descriptions had been written before the May 3 exemption-override change and still claimed `sensor.demerit_zone` was the "single source of truth". Updated to reflect the actual two-input model (zone + exemption flag).
- ✅ **Health Watchdog scope expanded.** Now monitors three signals (Tasker staleness + AdGuard sync staleness + any disabled Jarvis automation), up from two. Catches the failure mode where a critical automation gets accidentally toggled off.
- ✅ **Dashboard tile name fix.** "Screen time (limit: see below)" → "Screen time". The reference to "see below" hardcoded an assumption about section ordering that would break on dashboard reorganization.

### Resolved in earlier audit rounds (May 2–3, 2026)

- Exemption days now lift AdGuard blocks (May 3) — see §11.
- `input_boolean.tasks_completed_today_2` renamed back to `tasks_completed_today` (May 3) — entity_id mismatch had silently broken the tasks habit for weeks.
- `binary_sensor.jarvis_phone_late_view` formula inverted to match documented "on = success" semantic (May 3).
- Hardcoded `2026-04-22` date override removed from nightly report (May 2).
- Stale entities deleted: `last_tracked_app`, `last_tracked_timestamp`, `phone_chrome_usage` (May 2).
- Stale `chrome` entry removed from `app_map` (May 2).
- Hotstar blocking moved from `disney_plus` proxy to explicit domains (May 2).
- AdGuard end-to-end verified: client mapping, rule push, query log all work (May 2).
- `rest_command.adguard_get` added for read-side visibility (May 2). See §17.

---

## 14. Current state snapshot (May 17 2026, ~17:35 IST)

- **Demerit points: 11/12** → **green zone** → no AdGuard blocks active. `input_boolean.adguard_blocked` = off.
- **Today: Sunday → relaxed day (weekend + holiday declared) → screen limit 210 min.**
- **Holiday today: ON** (declared ~01:06 IST). Exemption today: OFF. Eval will run tonight.
- **Exemption days available: 5.** Overflow 4/6.
- **Pre-eval points: 12** (snapshot from May 16 nightly).
- **Habits today (so far):** gym ❌, guitar 0 min ❌, tasks ❌, steps 2597/8000 ❌, screen 17/210 min (under — YT 0, IG 0, NF 0, Prime 0, Hotstar 0, Brave 17). Phone used late: no ✅.
- **Screen time sensor math verified:** 0+0+0+0+0+17 = 17. Matches `sensor.phone_screen_time_total` = 17. ✅
- **AdGuard:** protection ON, filtering ON. Last sync 5 min ago. Tasker last poll 1 min ago.
- **All 12 automations enabled** (state `on`).
- **Points trajectory (May 10→17):** Recovered from red (2/12 on May 10) to green (11/12 on May 17). Strong upward trend over the past week.

**Two input_number entities have inconsistent UI mode** (cosmetic): `phone_prime_video_usage` and `phone_brave_usage` use `mode: slider` while all other usage counters use `mode: box`. See §13 optional fixes.

---

## 15. Changes since previous handoff (Apr 23 → May 6)

### May 10, 2026 (live audit — read-only, no HA changes)
| Change | Details |
|---|---|
| **Section 14 snapshot refreshed** | Full live-data refresh against HA MCP. Demerit 2/12 (red), exemption active, relaxed Saturday, screen 236/210 min (over), gym done, guitar/tasks not done, would_be_pts=0. All 12 automations enabled, all traces clean, all 5 cron jobs ok, all 13 view sensors verified correct. |
| **10 optional fixes documented (§13)** | OF-1 through OF-10 cataloged in new "Optional fixes" subsection. Covers: screen-time fail-silent default, plaintext credentials, Tasker dual-IP, midnight reset race, watchdog global cooldown, unauthenticated webhooks, dead code in mark_exemption_today, input_number mode inconsistency, automation description mismatch, failed login investigation. All require explicit permission. None are currently breaking. |
| **Credentials redacted from docs** | Bot token, chat ID, and AdGuard basic-auth header replaced with `secrets.yaml` references in §2, §7.3, §8. Credentials are still inline in `configuration.yaml` (see OF-2); this change only affects the documentation. |
| **Tasker dual-IP documented (§9)** | Discovered that `Send All to HA` posts to Tailscale `100.107.164.26` while `Send Late Phone Alert` posts to LAN `192.168.0.124`. Flagged as OF-3 with recommendation to standardize. |
| **Points trajectory documented** | May 6→10: 6→2 (red). Root cause: guitar (0 min for 4+ days) and tasks (off for 3+ days) impose a fixed -1 to -2 pts/day drain. System is working as designed — the punishment math is correct. |
| **No HA-side changes made** | This audit was read-only. All live MCP calls were either reads or the `jarvis_compute_daily_eval` pure-function test (no mutation). No automation, script, helper, or dashboard edits were performed. |

### May 6, 2026 (audit cleanup round)
| Change | Details |
|---|---|
| **Dashboard AdGuard tile hardened** | `tap_action: toggle` → `tap_action: more-info` + `hold_action: toggle` with confirmation dialog. A single accidental tap was previously enough to silently disable the entire punishment mechanism — Health Watchdog wouldn't catch it because the periodic sync still succeeded (rules pushed, just didn't apply). Highest-severity finding from the May 6 audit. |
| **Defensive defaults on points reads** | 4 touch points changed from `int(12)` (max) → `int(0)` (min). `script.jarvis_compute_daily_eval`, `automation.jarvis_late_phone_demerit` (both `current_pts` and `new_pts`), `automation.jarvis_nightly_report_*` (pre_eval snapshot). The exemption rollback in `script.mark_exemption_today` now defaults to current points (no-op fallback). Net effect: a sensor outage now lands at red zone (loud failure) instead of pretending everything is fine. |
| **Dead vars removed from eval script** | The outer `total_delta` and `would_be_pts` variables in `script.jarvis_compute_daily_eval` were never read — the equivalents inside `eval_result.*` are what the caller uses. Cleanup-only; no behavioral change. |
| **Health Watchdog scope expanded** | Now monitors three signals: Tasker staleness (>15 min), AdGuard sync staleness (>30 min), AND any disabled Jarvis automation (state == 'off'). The 11 monitored automations are listed inline in the automation's `variables:`. Catches the failure mode where a critical automation gets accidentally toggled off. |
| **`binary_sensor.jarvis_tasks_view` added** | The dashboard tasks tile was the only habit reading directly from `input_boolean.tasks_completed_today` instead of via a `*_view` wrapper. Symmetry restored — view sensors now wrap all 5 daily-habit booleans/numbers + 6 app counters + 3 points-related numbers = 13 view wrappers total. Routing Guide `/habits` template updated to consume the new view. |
| **Stale descriptions resynced** | `script.jarvis_sync_adguard_rules` and `automation.jarvis_punishment_enforcer` descriptions had been written before the May 3 exemption-override change. Updated to mention the override behavior explicitly. |
| **Dashboard tile name fix** | Section 3 screen-time tile: "Screen time (limit: see below)" → "Screen time". The hardcoded "see below" assumed a section ordering that would break on layout changes. |
| **OpenClaw cleanup (Kal-El, May 6)** | Cron job inventory shrunk from 16 (with 6 broken) to 5 working jobs. State files shrunk from 8 to 4 after deleting `screen-time-alerts.json` (vestigial — no live producer). Phantom modules `home_pulse`, `thought_catcher`, `inbox_intel` annotated "ON-DEMAND ONLY: no scheduled watcher" in `state/modules.json`. Periodic-audit trigger added to `Doc_Update_Triggers.md` so future drift is caught during routine audits, not when something breaks. |
| **AdGuard colocation documented** | AdGuard Home is on the same `ubuntu-media` VM as OpenClaw, Plex, qBittorrent, Ollama. Reachable at `192.168.0.122:80`. CPU contention on the VM can lag DNS for the household. Local LLM plan was abandoned May 6 after N150 benchmarks (Qwen 2.5 7B = 0.75 tok/s baseline; Morning Brief would take 30+ minutes vs 85s on Sonnet). Cloud-only for cron jobs is the architectural decision going forward. |
| **Accepted technical debt documented** | Three naming inconsistencies (`script.mark_exemption_today`, `script.mark_tasks_done`, `automation.jarvis_gym_visit_detected`) deferred — they require coordinated edits across HA + `habits-commands.md` for cosmetic gain. See §13. |

### May 3, 2026 (exemption-unblock + tasks fix round)
| Change | Details |
|---|---|
| **Exemption now lifts AdGuard blocks** | Punishment Enforcer gained a second trigger on `input_boolean.exemption_today` state change. Sync script computes effective zone as `green if exempt else states('sensor.demerit_zone')`. Net effect: declaring exemption pushes empty rule set; midnight flip-off re-pushes correct rules. Old behavior (exemption pauses eval only, blocks remain) is gone. |
| **Tasks habit entity_id rename** | Renamed `input_boolean.tasks_completed_today_2` back to `input_boolean.tasks_completed_today` to match the references everywhere in the system. The mismatched entity_id had silently broken the tasks habit since at least May 2 (Telegram confirmation lied about "+1 will apply"; eval read `unknown` → tasks_delta = 0). |
| **`jarvis_phone_late_view` formula inverted** | View sensor template flipped from `is_state(..., 'on')` to `is_state(..., 'off')` so it actually matches its documented "on = phone-off-late = success" semantic. Pre-fix it was a mirror, so every consumer template (cheatsheet, `/habits`, dashboard) showed the inverse of reality. Post-fix all consumers are correct without further edits. |

### Earlier rounds (Apr 23 → May 2)
| Change | Details |
|---|---|
| **AdGuard mechanism rewritten** | Old: 4 zone-specific rest_commands using AdGuard built-in service IDs. New: single `rest_command.adguard_set_custom_rules` driven by `script.jarvis_sync_adguard_rules` which pushes per-client custom filtering rules. Domain lists live in the script. |
| **Punishment Enforcer trigger changed** | Was: state change on `demerit_points` (fires on every -1/+1). Now: state change on `sensor.demerit_zone` (fires only on zone change). Less wasteful. |
| **AdGuard Periodic Sync added** | Re-pushes rules every 15 min. Drift correction for AdGuard restarts/manual UI edits. |
| **Health Watchdog added** | Original scope: alert if Tasker or AdGuard sync goes stale. 6h cooldown. (Expanded May 6 — see above.) |
| **Gym detection split** | Old: single automation with `wait_for_trigger` (timed out at 3h, lost state on restart). New: Entry sets a timestamp helper; Exit reads it and computes duration. Restart-safe. |
| **Eval logic extracted to pure function** | `script.jarvis_compute_daily_eval` returns a snapshot via `response_variable`. The nightly automation calls it then writes state. Testable in isolation. |
| **Six tunable input_numbers added** | All thresholds (points cap, screen limits, gym/guitar minutes, exemption ratio) are now editable entities, not hardcoded literals. |
| **Relaxed day system added** | `jarvis_holiday_today` boolean + `jarvis_relaxed_day` binary_sensor. Screen limit auto-scales via `sensor.jarvis_screen_limit_today`. New `script.jarvis_mark_holiday_today`. |
| **House tasks prompt added** | New 22:30 IST automation. New `script.mark_tasks_done`. Tasks tile on dashboard has tap-action. |
| **Stable view-sensor layer added** | Initially 12 `sensor.jarvis_*_view` / `binary_sensor.jarvis_*_view` entities wrap raw entities. (Now 13 after the May 6 tasks_view addition.) |
| **Hardcoded 2026-04-22 date override removed** | Old screen-delta hack is gone. |
| **Stale entities deleted (May 2)** | `last_tracked_app`, `last_tracked_timestamp`, `phone_chrome_usage`. |
| **Stale `chrome` entry removed from `app_map`** | The bulk-update automation no longer carries the dead chrome row. `app_map` is now 7 entries: youtube, instagram, netflix, prime, hotstar, brave, guitar. |
| **Screen warnings percentage-based** | Trigger at 50/75/92/100% of `jarvis_screen_limit_today`. Auto-scales for relaxed days. |
| **Dashboard expanded** | "Today mode", "System health", "Tunables" sections. |
| **Hotstar explicit blocking** | Explicit domains in `orange_additions` instead of `disney_plus` proxy. |
| **WhatsApp CDN carve-out** | `always_allow_patterns` regex allows WhatsApp CDN even when fbcdn is blocked at yellow. |
| **AdGuard read access** | New `rest_command.adguard_get` makes AdGuard's REST API queryable from HA (and via MCP). See Section 17. |
| **End-to-end AdGuard verification** | All four links confirmed: HA→AdGuard rule push works; persistent client "Danny S23" mapped to both phone IPs; phone DNS reaches AdGuard tagged correctly; per-client rules fire on matching queries. |

---

## 16. Operational runbook

### Add a new tracked app
1. Create `input_number.phone_<app>_usage` helper.
2. Add a `{entity, key}` entry to `app_map` in `automation.jarvis_phone_usage_stats_bulk_update`.
3. Add to the screen time template sensor formula in `configuration.yaml` (if it should count toward screen total).
4. Add to midnight reset's target list.
5. Update Tasker to include the new app's stats in the bulk payload.
6. (Optional) Add a `sensor.jarvis_<app>_view` UI template helper wrapper.
7. Add a tile to the dashboard.
8. (Optional) If blockable, add domains to the appropriate tier in `script.jarvis_sync_adguard_rules`.

### Add a new habit
1. Create tracking entity (input_boolean or input_number).
2. Add to the read-and-compute step in `script.jarvis_compute_daily_eval`. Add a delta variable. Include in `total_delta`. Add to the response dict.
3. Update the nightly report's Telegram message template to show the new habit.
4. Add to midnight reset.
5. (Optional) Add a view sensor as a UI template helper.
6. Add to dashboard.
7. Update handoff docs.

### Change a threshold
Just edit the `input_number.jarvis_*` value on the dashboard. No restart, no code change.

### Add or remove a blocked domain
Edit the corresponding list in `script.jarvis_sync_adguard_rules` (yellow_domains, orange_additions, red_additions, or always_allow_patterns). Force a sync via `ha_call_service('script', 'jarvis_sync_adguard_rules')` or wait up to 15 min for periodic sync. Verify the new state with `adguard_get path=filtering/status` (Section 17).

### Edit a UI template sensor (e.g. a `*_view` wrapper or `jarvis_relaxed_day`)
Settings → Devices & Services → Helpers → search "Jarvis" → click the entry → Configure. Or via MCP: `ha_get_integration(domain="template")` lists all entries; `ha_set_config_entry_helper(helper_type="template", entry_id=..., config={...})` updates one.

### Debug "data not flowing"
1. Check `sensor.jarvis_minutes_since_tasker_poll`. If >10 min and growing, Tasker isn't firing.
2. Check Health Watchdog — should have alerted by 15 min mark (6h cooldown after first alert).
3. Inspect bulk-update automation traces. `finished` runs = data arriving.
4. Verify Tasker profile is enabled on phone.

### Debug "punishment not happening"
1. Check if today is an exemption day: `ha_get_state(entity_id="input_boolean.exemption_today")`. If on, blocks are intentionally lifted — the sync script forces effective zone to green. Expected behavior.
2. `switch.adguard_home_protection_2` AND `switch.adguard_home_filtering_2` must both be ON.
3. Check `sensor.jarvis_minutes_since_adguard_sync`. If stale, Health Watchdog should alert.
4. Manually trigger sync: `ha_call_service('script', 'jarvis_sync_adguard_rules')`.
5. Confirm rules loaded: `ha_call_service('rest_command', 'adguard_get', data={'path':'filtering/status'}, return_response=True)` — look for `user_rules` containing the expected domains. **If exempt today, expect `user_rules=[]`.**
6. Confirm phone DNS arriving at AdGuard tagged correctly: `adguard_get path=querylog?limit=50&search=Danny%20S23` — should show recent queries with `client_info.name: "Danny S23"`. Empty result means the phone isn't using AdGuard for DNS.
7. If empty, suspect Android Private DNS bypass (Section 13) or phone not on Tailscale/home WiFi.

### Debug eval result
Just call the pure function:
```
ha_call_service('script', 'jarvis_compute_daily_eval', return_response=True)
```
Returns the full computation without mutating anything. Useful for "what would happen tonight if eval ran now?"

### Debug "rest_command unexpectedly broken"
Symptom: Telegram messages stop arriving, AdGuard sync starts failing. Check:
```
ha_get_logs(source="system", level="ERROR", search="rest_command")
```
If you see `Setup failed for 'rest_command': Invalid config.`, the whole integration failed to load — usually due to a yaml indentation slip in `configuration.yaml` (a new entry got nested under an existing one instead of becoming a sibling). Fix the indent, then Developer Tools → YAML → Reload Rest Commands.

---

## 17. Reading AdGuard live via `adguard_get`

The system can now query AdGuard's REST API directly from HA. The generic `rest_command.adguard_get` (Section 7.3) accepts a `path` parameter and returns the parsed JSON response.

### Calling pattern

```python
ha_call_service(
    domain="rest_command",
    service="adguard_get",
    data={"path": "<endpoint>?<query_string>"},
    return_response=True
)
```

The response under `service_response.content` is the parsed JSON body. `service_response.status` is the HTTP status code.

### Useful endpoints

| Path | Returns | Use case |
|---|---|---|
| `status` | Server version, DNS addresses, ports, protection state | Sanity check that AdGuard is up and reachable. |
| `clients` | Persistent client list with IDs (IPs/ClientIDs) and per-client settings; also `auto_clients` (recent IPs seen via ARP). | Verify "Danny S23" is registered with the right IPs. |
| `filtering/status` | Active filter lists + `user_rules` array (the per-client rules the sync script pushed). | Verify the rule push landed. Compare `user_rules` length and contents against what the script generated. |
| `querylog?limit=N` | Most recent N DNS queries with client info, question, answer, status, and matched rule. | See raw activity. Default ordering is newest first. |
| `querylog?limit=N&search=Danny%20S23` | Same, filtered to entries where any field matches "Danny S23". | The fastest way to confirm the phone is reaching AdGuard tagged correctly. |
| `stats` | Aggregate counters and per-client breakdown. | Block-rate and top-clients view. |

### Worked example: verifying the chain end-to-end

```python
# 1. Check AdGuard reachable and protection on
ha_call_service("rest_command", "adguard_get",
                data={"path": "status"}, return_response=True)
# → expect content.protection_enabled == true, content.running == true

# 2. Confirm Danny S23 client exists with both IPs
ha_call_service("rest_command", "adguard_get",
                data={"path": "clients"}, return_response=True)
# → look in content.clients[] for {name: "Danny S23", ids: [...]} 
#   ids should include both 100.70.157.25 (Tailscale) and 192.168.0.47 (LAN)

# 3. Confirm rules loaded
ha_call_service("rest_command", "adguard_get",
                data={"path": "filtering/status"}, return_response=True)
# → If NOT exempt today: content.user_rules should be a list of 21 entries 
#   (7 yellow + 7 orange + 6 red + 1 WhatsApp allow), formatted as 
#   ||domain^$client='Danny S23' or @@regex$client='Danny S23'
# → If exempt today: content.user_rules should be [] (sync forces zone=green; 
#   the script returns no rules in green, and the WhatsApp carve-out is 
#   gated on having block rules to apply)

# 4. Confirm queries arriving and being filtered
ha_call_service("rest_command", "adguard_get",
                data={"path": "querylog?limit=50&search=Danny%20S23"},
                return_response=True)
# → content.data[] should contain recent queries with 
#   client_info.name == "Danny S23"
# → blocked entertainment domains should show:
#   reason: "FilteredBlackList"
#   filter_list_id: 0  (= user rules)
#   rule: "||youtube.com^$client='Danny S23'"  (or similar)
```

If step 4 returns an empty array but steps 1–3 all look correct, the phone isn't using AdGuard for DNS. Most common cause: Android Private DNS bypass (Section 13).

### Why this matters for the next LLM

Before the May 2 audit, "Phone DNS routing" had been on the Outstanding list for weeks. Nobody could verify whether the entire punishment system was a no-op. With `adguard_get`, that loop is closeable in seconds. Run the four-step sequence above whenever the system gets meaningfully changed, the phone gets reset, AdGuard gets upgraded, or anything else that could break per-client identification.
