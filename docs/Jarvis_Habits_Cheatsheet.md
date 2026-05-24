# Jarvis Habits — Quick Reference

One-page lookup. For deep context see `Jarvis_Habits_Handoff.md`.

**Last verified:** May 17, 2026 (live MCP reconciliation — steps habit documented, AdGuard tiers corrected, house tasks buttons documented, credentials migration confirmed, 4 new entities added, OF-2 resolved)
**Prior:** May 10 (snapshot refreshed, optional fixes documented), May 6 (defaults hardened, dead code removed, tasks view sensor added, dashboard AdGuard tile hardened)

## Points & punishment

| Points | Zone | AdGuard custom rules pushed for "Danny S23" |
|---|---|---|
| 9–12 | green | none (full access) |
| 6–8 | yellow | YouTube + Instagram (7 domains) |
| 3–5 | orange | + Netflix, Prime Video (7 additional) |
| 0–2 | red | + Hotstar, JioHotstar, Disney+ (6 additional) |

Brave: tracked, never blocked. TikTok, Twitch, Reddit, Snapchat: not blocked at any tier (removed — never applicable). Always-allow carve-out: WhatsApp CDN (only emitted alongside block rules — i.e. not in green). `input_boolean.adguard_blocked` tracks whether punishment is active.

**Exemption override:** when `input_boolean.exemption_today` is on, sync forces effective zone to green regardless of points → all blocks lifted for the day. Midnight reset flips exemption off → enforcer re-fires → rules re-pushed for actual zone.

The blocking mechanism is **custom per-client filtering rules** (domain lists in `script.jarvis_sync_adguard_rules`), pushed via `rest_command.adguard_set_custom_rules`. AdGuard identifies the phone by IP (LAN `<YOUR_PHONE_LAN_IP>` or Tailscale `100.70.157.25`) and matches it to the persistent client "Danny S23". The four legacy per-zone rest_commands are gone.

## Daily math

| Habit | If done | If not |
|---|---|---|
| Gym (≥`jarvis_gym_min_minutes` in zone, no WiFi) | +1 | -1 |
| Guitar (≥`jarvis_guitar_target_minutes` JustinGuitar) | +1 | -1 |
| Screen time (≤`sensor.jarvis_screen_limit_today` total) | +1 | -1 |
| House tasks (manual via `/tasks_done`) | +1 | +0 |
| Steps (≥`jarvis_steps_target` via Garmin Connect) | +2 | +0 |
| Phone off by 11:30 PM | — | -1 |

Max +6/day (habits, incl. steps bonus), max -4/day (worst case). Points clamped 0–`jarvis_points_max` (12). Steps is bonus-only — rewards but never penalizes.
Overflow above max → `overflow_points`; `jarvis_points_per_exemption` (6) overflow → 1 exemption day auto-redeemed.

**All thresholds are tunable input_numbers** — change live, no restart.

## Today modes

Three modes affect the day:

| Mode | Effect | Set via |
|---|---|---|
| **Normal** | Standard rules | (default) |
| **Relaxed day** (auto: weekends; manual: `jarvis_holiday_today`) | Screen limit raises to 210 min. Gym/guitar/late phone unchanged. | `script.jarvis_mark_holiday_today` |
| **Exemption day** | Reward-only scoring (positive deltas applied, penalties zeroed). Screen warnings paused. Late phone check paused. **AdGuard blocks lifted** (sync forces effective zone to green). Costs 1 from exemption bank. | `script.mark_exemption_today` |

`binary_sensor.jarvis_relaxed_day` = on when weekend OR holiday flag is on.
`sensor.jarvis_screen_limit_today` = 210 if relaxed, else 120 (both tunable).

**Note:** exemption days use **reward-only scoring** — positive habit deltas are applied, negative deltas are zeroed out. Good habits still earn points and overflow toward new exemption days. AdGuard blocks are also lifted for the day. Sync script computes effective zone as `green if exemption_today is on else states('sensor.demerit_zone')`. At midnight the boolean flips off (midnight reset) → punishment enforcer fires (state-change trigger) → rules re-pushed for actual zone — so old blocks return automatically if points are still low. (Pre–May 24 2026: exemption skipped all point changes entirely; reward-only model adopted to incentivize effort on rest days.)

## Data ingestion — bulk polling model

Tasker polls usage stats and POSTs totals every ~2 min to:
`POST /api/webhook/<YOUR_BULK_WEBHOOK_ID>`

Payload is flat JSON. Only keys present are written; missing keys preserve existing values. Each successful poll updates `input_datetime.jarvis_last_tasker_poll` (Health Watchdog reads this).

| Payload key | HA entity |
|---|---|
| `youtube` | `input_number.phone_youtube_usage` |
| `instagram` | `input_number.phone_instagram_usage` |
| `netflix` | `input_number.phone_netflix_usage` |
| `prime` | `input_number.phone_prime_video_usage` |
| `hotstar` | `input_number.phone_jiohotstar_usage` |
| `brave` | `input_number.phone_brave_usage` |
| `guitar` | `input_number.phone_guitar_usage` |

`app_map` in the bulk-update automation is now exactly these 7 entries (the dead `chrome` row was removed in the May 2 cleanup).

**Tasker tracks app foreground time, not network success.** When YT is DNS-blocked, Tasker still counts minutes if the YT app is on screen. Expected behaviour.

Late phone webhook unchanged:
`POST /api/webhook/<YOUR_LATE_PHONE_WEBHOOK_ID>` — body `{event, time, device}`

Both webhooks: `local_only: false` (required for Tailscale).

## HA entities

### Points & exemption
- `input_number.demerit_points` (0–12)
- `input_number.exemption_days` (unbounded)
- `input_number.overflow_points` (0–5)
- `input_number.pre_eval_points` (snapshot before nightly eval, used for post-eval exemption rollback)
- `input_boolean.exemption_today`
- `sensor.demerit_zone` — text: green/yellow/orange/red. **Punishment Enforcer triggers off this**, not off raw points.

### Tunables (seven — edit on dashboard, no restart)
- `input_number.jarvis_points_max` (12)
- `input_number.jarvis_points_per_exemption` (6)
- `input_number.jarvis_screen_limit_normal` (120)
- `input_number.jarvis_screen_limit_relaxed` (210)
- `input_number.jarvis_gym_min_minutes` (20)
- `input_number.jarvis_guitar_target_minutes` (20)
- `input_number.jarvis_steps_target` (8000) — daily step count target for +2 bonus. Source: `sensor.garmin_connect_steps`

### Today-mode entities
- `input_boolean.jarvis_holiday_today` — soft day. Cleared at midnight.
- `binary_sensor.jarvis_relaxed_day` — on when weekend OR holiday.
- `sensor.jarvis_screen_limit_today` — current active limit (auto-scales).

### Habits
- `input_boolean.gym_visited_today`
- `input_datetime.jarvis_gym_entered_at` — entry timestamp (used by exit automation for restart-safe duration calc; cleared on exit)
- `input_number.phone_guitar_usage` (min)
- `sensor.phone_screen_time_total` (min, sum of 6 entertainment/browser apps — see formula below)
- `input_boolean.phone_used_late`
- `input_boolean.tasks_completed_today` — set via `script.mark_tasks_done` (called by `/tasks_done`)
- `sensor.garmin_connect_steps` — daily step count from Garmin Connect HACS integration. Read at eval time; no input_number counter.
- `input_number.daily_steps_result` — written by nightly report for history charting

### Usage counters (all `input_number`, unit: min)
- `phone_youtube_usage`, `phone_instagram_usage`, `phone_netflix_usage`
- `phone_prime_video_usage`, `phone_jiohotstar_usage`
- `phone_brave_usage`
- `phone_guitar_usage` (separate from screen total)
- ⚠ `phone_chrome_usage` does **not** exist (deleted). Tasker doesn't send the key. The automation's `app_map` no longer references it either.

### Stable view sensors (read-only abstraction layer for dashboard + OpenClaw)
These wrap the underlying entities with stable IDs, so dashboard/router templates don't break when internals change:
- `sensor.jarvis_demerit_points_view`, `sensor.jarvis_exemption_days_view`, `sensor.jarvis_overflow_points_view`
- `binary_sensor.jarvis_gym_status_view`, `sensor.jarvis_guitar_view`, `binary_sensor.jarvis_phone_late_view`, `binary_sensor.jarvis_tasks_view`
- `sensor.jarvis_youtube_view`, `sensor.jarvis_instagram_view`, `sensor.jarvis_netflix_view`
- `sensor.jarvis_prime_view`, `sensor.jarvis_hotstar_view`, `sensor.jarvis_brave_view`

**Where they live:** all 13 view sensors plus `binary_sensor.jarvis_relaxed_day`, `sensor.jarvis_screen_limit_today`, `binary_sensor.jarvis_screen_counting_active` (Tasker data freshness indicator, created ~May 15), and the two `sensor.jarvis_minutes_since_*` are **UI template helpers** (18 total, Settings → Devices & Services → Helpers → Template), NOT in `configuration.yaml`. The only YAML template sensors are `sensor.phone_screen_time_total` and `sensor.demerit_zone`.

### Health monitoring
- `input_datetime.jarvis_last_tasker_poll` — written every Tasker poll
- `input_datetime.jarvis_last_adguard_sync` — written every AdGuard push
- `input_datetime.jarvis_last_health_alert` — cooldown for watchdog
- `sensor.jarvis_minutes_since_tasker_poll`, `sensor.jarvis_minutes_since_adguard_sync` (both UI helpers)

### Location
- `zone.gym` (<YOUR_GYM_LAT>, <YOUR_GYM_LNG>, r=49m)
- `person.danny`, `device_tracker.danny_s23`
- `sensor.danny_s23_wi_fi_connection` — used by gym entry as GPS drift guard

## HA automations (12 total, all prefixed `Jarvis -`)

| Automation | Trigger | What it does |
|---|---|---|
| Phone Usage Stats Bulk Update | POST `/api/webhook/<YOUR_BULK_WEBHOOK_ID>` | Overwrites counters from Tasker payload; updates last_tasker_poll. Queued, max 5. `app_map` = 7 keys. |
| Gym Entry Detected | Zone enter (person.danny → zone.gym) | WiFi guard → records entry timestamp |
| Gym Exit Detected | Zone leave (person.danny ← zone.gym) | Reads timestamp → if duration ≥ min → marks gym done. Restart-safe. |
| Late Phone Usage | POST `/api/webhook/<YOUR_LATE_PHONE_WEBHOOK_ID>` | Flips late flag (idempotent) |
| Screen Time Warnings | Template triggers at 50/75/92/100% of `jarvis_screen_limit_today` | Progressive Telegram alerts. Auto-scales for relaxed days. Skips exemption days. |
| House Tasks Prompt | 22:30 IST | Telegram message with **inline keyboard buttons** ("Tasks Done" / "Tasks Not Done") via `rest_command.jarvis_send_message_keyboard`. Skips on exemption/holiday/already-done. |
| Nightly Report 11:20 PM | 23:20 IST | Saves pre_eval snapshot → calls `script.jarvis_compute_daily_eval` (incl. steps) → applies overflow→exempt math → writes 6 daily result helpers → sends Telegram (steps shown with ⬜ icon). |
| Late Phone Demerit | 23:35 IST | -1 pt if late phone flag is on. Skips exemption days. |
| Punishment Enforcer | `sensor.demerit_zone` OR `input_boolean.exemption_today` state change | Calls `script.jarvis_sync_adguard_rules` (which computes effective zone with exemption override). |
| AdGuard Periodic Sync | Every 15 min | Re-pushes current zone's rules. Drift correction. |
| Health Watchdog | Every 30 min | Telegram alert if Tasker poll >15 min stale, AdGuard sync >30 min stale, **OR any monitored Jarvis automation is disabled** (state `off`). 11 monitored automations listed in `variables:`. 6h cooldown. |
| Midnight Reset | 00:00 IST | Zeros 7 usage counters + 5 daily booleans (incl. `jarvis_holiday_today`) + clears `jarvis_gym_entered_at`. Points/overflow/exemption/pre_eval persist. |

## Scripts

- `script.jarvis_compute_daily_eval` — **pure function**. Reads habit state + tunables (incl. steps from `sensor.garmin_connect_steps`), returns scoring deltas via `response_variable: eval_result`. Steps: +2 if target met, 0 if not. Does NOT mutate anything. Test in isolation: `ha_call_service('script', 'jarvis_compute_daily_eval', return_response=True)`. Defensive default (May 6): `current_pts` falls back to `0` (not `12`) on sensor unavailability — fail-loud.
- `script.jarvis_sync_adguard_rules` — pushes per-client custom filtering rules to AdGuard for current effective zone. Single source of truth: domain lists live inside the script. Reads BOTH `sensor.demerit_zone` AND `input_boolean.exemption_today` — when exempt, effective zone is forced to green and all blocks are lifted. Idempotent. Updates last_adguard_sync.
- `script.mark_exemption_today` — declares exemption. Refuses if already exempt or zero days. Post-eval rollback: if called after 23:20, restores points from `pre_eval_points` (defaults to current `demerit_points` value if pre_eval is unavailable — no-op fallback).
- `script.jarvis_mark_holiday_today` — declares soft day. Refuses if already holiday. Auto-clears at midnight.
- `script.mark_tasks_done` — confirms house tasks. Refuses if already on. Called by Jarvis routing on bare-word `tasks_done`.

⚠ **Naming inconsistency note:** `mark_exemption_today` and `mark_tasks_done` lack the `jarvis_` prefix used by everything else. Cosmetic; deferred as accepted technical debt (Handoff §13). Don't try to rename without coordinating with `habits-commands.md` on the Jarvis side.

## Rest commands (full configs: Handoff §7.3)

All credentials use `!secret` references (`telegram_jarvis_send_url`, `adguard_basic_auth`).

- `jarvis_send_message` — Telegram send via bot API. Takes `{{ message }}`.
- `jarvis_send_message_keyboard` — Telegram send with inline keyboard buttons. Takes `{{ message }}` + `{{ reply_markup }}`. Used by house tasks prompt.
- `adguard_set_custom_rules` — POSTs filtering rules to `/control/filtering/set_rules`. Takes `{{ rules }}` (list of `||domain^$client='Danny S23'` lines).
- `adguard_get` — generic GET. Takes `{{ path }}`. Use with `return_response=True` to read clients, filtering/status, querylog, stats.
- `adguard_block_maria_ipad` / `adguard_unblock_maria_ipad` — unrelated iPad battery automation.

The four legacy zone-specific rest_commands are gone. **YAML gotcha** (full debug runbook in Handoff §7.3 + §16): new entries under `rest_command:` need 2-space indent (sibling level). 4-space nests them under the previous command and breaks the entire integration silently — Telegram and AdGuard sync both fail. Symptom: `ha_get_logs(source="system", level="ERROR", search="rest_command")` shows `Setup failed for 'rest_command'`.

## Common live queries

**Snapshot:**
```jinja
Pts {{ states('input_number.demerit_points') | int }}/{{ states('input_number.jarvis_points_max') | int }} ({{ states('sensor.demerit_zone') }}) | Screen {{ states('sensor.phone_screen_time_total') | int }}/{{ states('sensor.jarvis_screen_limit_today') | int }} | Gym {{ states('input_boolean.gym_visited_today') }} | Guitar {{ states('input_number.phone_guitar_usage') | int }} | Tasks {{ states('input_boolean.tasks_completed_today') }} | Steps {{ states('sensor.garmin_connect_steps') }}/{{ states('input_number.jarvis_steps_target') | int }} | Exempt days {{ states('input_number.exemption_days') | int }} | Overflow {{ states('input_number.overflow_points') | int }}/{{ states('input_number.jarvis_points_per_exemption') | int }} | Relaxed {{ states('binary_sensor.jarvis_relaxed_day') }}
```

**App breakdown:**
```jinja
YT {{ states('input_number.phone_youtube_usage') | int }} | IG {{ states('input_number.phone_instagram_usage') | int }} | NF {{ states('input_number.phone_netflix_usage') | int }} | Prime {{ states('input_number.phone_prime_video_usage') | int }} | Hotstar {{ states('input_number.phone_jiohotstar_usage') | int }} | Brave {{ states('input_number.phone_brave_usage') | int }}
```

**Health:**
```jinja
Tasker last poll: {{ states('sensor.jarvis_minutes_since_tasker_poll') }} min ago | AdGuard last sync: {{ states('sensor.jarvis_minutes_since_adguard_sync') }} min ago | Filtering: {{ states('switch.adguard_home_filtering_2') }} | Protection: {{ states('switch.adguard_home_protection_2') }}
```

## Common actions

**Force reset points (emergency):**
```
ha_call_service("input_number", "set_value", "input_number.demerit_points", {"value": 12})
```

**Declare exemption today:**
```
ha_call_service("script", "mark_exemption_today")
```

**Declare holiday (relaxed limits) today:**
```
ha_call_service("script", "jarvis_mark_holiday_today")
```

**Force re-push current AdGuard rules (drift correction):**
```
ha_call_service("script", "jarvis_sync_adguard_rules")
```

**Mark house tasks done:**
```
ha_call_service("script", "mark_tasks_done")
```

**Test eval logic without mutating anything:**
```
ha_call_service("script", "jarvis_compute_daily_eval", return_response=True)
```

**Inspect a UI template helper formula via MCP:**
```
ha_get_integration(domain="template")            # list all 18 jarvis UI helpers
ha_get_integration(entry_id=..., include_schema=True)   # see formula
```

## AdGuard read-side: `adguard_get` (full worked example: Handoff §17)

Generic GET against AdGuard's API:
```
ha_call_service("rest_command", "adguard_get",
                data={"path": "<endpoint>"}, return_response=True)
```
Response at `service_response.content`.

| `path` | Returns |
|---|---|
| `status` | Server version, DNS addresses, ports, protection state |
| `clients` | Persistent clients (Danny S23, Maria's iPad) + auto_clients (recent ARP) |
| `filtering/status` | Active filter lists + `user_rules` array (per-client rules pushed by sync script) |
| `querylog?limit=50` | Recent queries with client info, question, answer, matched rule |
| `querylog?limit=50&search=Danny%20S23` | Same, filtered to phone-related entries |
| `stats` | Aggregate counters and per-client breakdown |

**4-step end-to-end verification:**
1. `path=status` → expect `protection_enabled=true`, `running=true`
2. `path=clients` → expect `{name: "Danny S23", ids: [100.70.157.25, <YOUR_PHONE_LAN_IP>]}`
3. `path=filtering/status` → if NOT exempt today, `user_rules` should contain 21 entries (7 yellow + 7 orange + 6 red + 1 WhatsApp allow); if exempt today, `user_rules` should be `[]`
4. `path=querylog?limit=50&search=Danny%20S23` → recent entries with `client_info.name == "Danny S23"`; blocks show `reason: "FilteredBlackList"` and `filter_list_id: 0`

If 1–3 pass but 4 returns empty: phone isn't using AdGuard for DNS — most likely Android Private DNS bypass.

## Infrastructure (full table: Handoff §2)

HA `192.168.0.124:8123` · AdGuard `192.168.0.122:80` (v0.107.74, **colocated on the OpenClaw VM** with Plex/qBit/Ollama) · OpenClaw VM `ubuntu-media` at `192.168.0.201` · Phone S23 LAN `<YOUR_PHONE_LAN_IP>` / Tailscale `100.70.157.25` · All credentials in `secrets.yaml` (`telegram_jarvis_send_url`, `adguard_basic_auth` — see Handoff §7.3, §8). Heavy CPU on the VM can lag DNS for the household — see Handoff §13.

**⚠️ Tasker dual-IP (May 10):** Bulk usage posts to Tailscale `100.107.164.26`, late phone posts to LAN `192.168.0.124`. See Handoff §9 / OF-3.

## AdGuard switches (both must be ON)

`switch.adguard_home_protection_2` (master kill) and `switch.adguard_home_filtering_2` (filtering subsystem — required for the custom-rules mechanism). `switch.adguard_home_query_log_2` must also be ON for the `adguard_get path=querylog` probes to work. Dashboard "System Health" tile points at `_filtering_2` because that's the one most likely to silently break the new mechanism. As of May 6, the tile uses `tap_action: more-info` + `hold_action: toggle` with a confirmation dialog — a single accidental tap can no longer disable all blocks.

## Webhooks (full schemas: Handoff §3, §9)

Both have `local_only: false` (required for Tailscale).
- `POST /api/webhook/<YOUR_BULK_WEBHOOK_ID>` — flat JSON, only-present-keys-overwrite. Keys: `youtube`, `instagram`, `netflix`, `prime`, `hotstar`, `brave`, `guitar` (minutes).
- `POST /api/webhook/<YOUR_LATE_PHONE_WEBHOOK_ID>` — body `{event, time, device}`.

## What's outstanding

- **Plex blocking** — never implemented.
- **Brave package name** (`com.brave.browser`) — unverified on phone.
- **Android Private DNS** — latent risk: if the phone's Private DNS gets pointed at a public DoH, it bypasses AdGuard and our blocks become no-ops. Verified working on May 2; check periodically by running step 4 of the AdGuard chain verification (above).

## Optional fixes (May 10 audit — see Handoff §13 for full details)

All require Danny's explicit permission. None are currently breaking.

| # | Issue | Severity |
|---|---|---|
| OF-1 | Screen time defaults to 0 on sensor failure → rewards broken sensor (contradicts fail-loud policy) | Design flaw |
| ~~OF-2~~ | ~~Telegram token + AdGuard credentials hardcoded~~ — **Resolved May 17.** All migrated to `secrets.yaml`. | — |
| OF-3 | Tasker posts bulk to Tailscale IP but late-phone to LAN IP | Reliability risk |
| OF-4 | Tasker midnight reset (23:58–00:03) races with HA midnight reset (00:00) | Data integrity |
| OF-5 | Health Watchdog cooldown is global (one signal suppresses all 3 for 6h) | Design limitation |
| OF-6 | Webhook IDs unauthenticated — anyone on network can inject data | Security gap |
| OF-7 | `now().hour > 23` dead code in `mark_exemption_today` | Cosmetic |
| OF-8 | `phone_prime_video_usage` and `phone_brave_usage` have `mode: slider` instead of `box` | Cosmetic |
| OF-9 | Bulk-update automation description says "~90s" but actual interval is ~2 min | Doc/code mismatch |
| OF-10 | Failed login notification from 192.168.0.122 (OpenClaw VM, May 6) — investigate | Investigate |
