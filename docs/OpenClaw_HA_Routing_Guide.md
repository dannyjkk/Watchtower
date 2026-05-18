# OpenClaw → HA Routing Guide

**Last updated:** May 17, 2026 (steps habit added to /status and /habits templates; tasks_done updated to enhanced flow with house_tasks.json integration)

> **Convention note:** This guide uses `/`-prefixed names (`/status`, `/exempt`, etc.) as **section headers and spec convention only**. The actual triggers Jarvis matches are bare words ("status", "exempt", "soft day", "system health") — `/`-prefixed forms clash with OpenClaw built-ins like `/exec`. The single authoritative source for what Jarvis actually matches is `habits-commands.md` (Jarvis-side workspace). Templates and POST paths in this guide are accurate and current; only the heading style is convention.

## Architecture

```
User sends Telegram message → Jarvis polls → Jarvis inspects message:

┌─ Starts with /? ─ yes ─→ Pattern match against routing table
│                           ├─ match ─→ Call HA API directly (NO Claude)
│                           └─ no match ─→ Fall through to Claude
│
└─ no ─────────────────────→ Fall through to Claude (conversational)
```

**HA stays pristine.** All state, logic, business rules live there. OpenClaw is a thin router that decides "handle this natively vs invoke Claude". New habit modules never require HA-side routing changes — just add templates here.

**Templates use the stable view sensor layer** (`sensor.jarvis_*_view`, `binary_sensor.jarvis_*_view`) so refactors of underlying entities don't break the router. When in doubt, prefer view sensors over raw `input_number.*` references.

---

## HA API endpoints Jarvis will use

Base: `http://192.168.0.124:8123`
Auth: `Authorization: Bearer <JARVIS_LLAT>` (long-lived token stored in `ha-token.txt` on the OpenClaw VM, 183 bytes — see Contract §3.4)

### The workhorse: `/api/template`
```
POST /api/template
Content-Type: application/json
Body: {"template": "<jinja string>"}
Response: rendered string (text/plain), no size limit
```

Used for all read-only queries. Jarvis sends a Jinja template, HA evaluates against live state, returns text. Jarvis forwards verbatim to user.

### For write operations: `/api/services/<domain>/<service>`
```
POST /api/services/script/mark_exemption_today
Content-Type: application/json
Body: {}   (script needs no params)
```

---

## Routing table for the habits module

### `/status` — full status briefing

**Action:** POST `/api/template`
**Body template:**
```jinja
📊 *Status*

Points: {{ states('sensor.jarvis_demerit_points_view') | int }}/{{ states('input_number.jarvis_points_max') | int }} ({{ states('sensor.demerit_zone') }})
{% if is_state('input_boolean.exemption_today', 'on') %}🛋️ Exempt day — no eval tonight, all AdGuard blocks lifted
{% elif is_state('binary_sensor.jarvis_relaxed_day', 'on') %}🌴 Relaxed day — screen limit {{ states('sensor.jarvis_screen_limit_today') | int }} min
{% endif %}Screen: {{ states('sensor.phone_screen_time_total') | int }}/{{ states('sensor.jarvis_screen_limit_today') | int }} min
Gym: {{ 'done ✅' if is_state('binary_sensor.jarvis_gym_status_view', 'on') else 'pending ⏳' }}
Guitar: {{ states('sensor.jarvis_guitar_view') | int }}/{{ states('input_number.jarvis_guitar_target_minutes') | int }} min
Tasks: {{ 'done ✅' if is_state('binary_sensor.jarvis_tasks_view', 'on') else 'pending ⏳' }}
Steps: {{ states('sensor.garmin_connect_steps') | int }}/{{ states('input_number.jarvis_steps_target') | int }} {{ '✅ bonus' if states('sensor.garmin_connect_steps') | int >= states('input_number.jarvis_steps_target') | int else '⏳' }}
Exemption days: {{ states('sensor.jarvis_exemption_days_view') | int }}
Overflow: {{ states('sensor.jarvis_overflow_points_view') | int }}/{{ states('input_number.jarvis_points_per_exemption') | int }}
```
**Response handling:** Forward verbatim with `parse_mode: markdown`

---

### `/points` — points + zone

**Action:** POST `/api/template`
**Body template:**
```jinja
Points: {{ states('sensor.jarvis_demerit_points_view') | int }}/{{ states('input_number.jarvis_points_max') | int }} — *{{ states('sensor.demerit_zone') }}* zone.
Exemption days: {{ states('sensor.jarvis_exemption_days_view') | int }}.
Overflow: {{ states('sensor.jarvis_overflow_points_view') | int }}/{{ states('input_number.jarvis_points_per_exemption') | int }} toward next exemption.
```

---

### `/screen` — screen time breakdown

**Action:** POST `/api/template`
**Body template:**
```jinja
📱 Screen time {{ states('sensor.phone_screen_time_total') | int }}/{{ states('sensor.jarvis_screen_limit_today') | int }} min{% if is_state('binary_sensor.jarvis_relaxed_day', 'on') %} (relaxed){% endif %}

YouTube: {{ states('sensor.jarvis_youtube_view') | int }}
Instagram: {{ states('sensor.jarvis_instagram_view') | int }}
Netflix: {{ states('sensor.jarvis_netflix_view') | int }}
Prime: {{ states('sensor.jarvis_prime_view') | int }}
Hotstar: {{ states('sensor.jarvis_hotstar_view') | int }}
Brave: {{ states('sensor.jarvis_brave_view') | int }}
```

(Chrome was removed from tracking — entity no longer exists.)

---

### `/habits` — today's checkbox view

**Action:** POST `/api/template`
**Body template:**
```jinja
🎯 *Today's habits*

{{ '✅' if is_state('binary_sensor.jarvis_gym_status_view', 'on') else '❌' }} Gym
{{ '✅' if states('sensor.jarvis_guitar_view') | int >= states('input_number.jarvis_guitar_target_minutes') | int else '❌' }} Guitar ({{ states('sensor.jarvis_guitar_view') | int }}/{{ states('input_number.jarvis_guitar_target_minutes') | int }} min)
{{ '✅' if states('sensor.phone_screen_time_total') | int <= states('sensor.jarvis_screen_limit_today') | int else '❌' }} Screen time ({{ states('sensor.phone_screen_time_total') | int }}/{{ states('sensor.jarvis_screen_limit_today') | int }} min){% if is_state('binary_sensor.jarvis_relaxed_day', 'on') %} 🌴{% endif %}
{{ '✅' if is_state('binary_sensor.jarvis_tasks_view', 'on') else '❌' }} House tasks
{{ '✅' if is_state('binary_sensor.jarvis_phone_late_view', 'on') else '❌' }} Phone off by 11:30 PM
{{ '✅' if states('sensor.garmin_connect_steps') | int >= states('input_number.jarvis_steps_target') | int else '❌' }} Steps ({{ states('sensor.garmin_connect_steps') | int }}/{{ states('input_number.jarvis_steps_target') | int }}) — bonus only
```

Notes:
- `binary_sensor.jarvis_phone_late_view` is the *inverted* form — `on` means "phone off late" succeeded.
- `binary_sensor.jarvis_tasks_view` was added May 6, 2026 to bring tasks into the view-sensor abstraction layer (was reading `input_boolean.tasks_completed_today` directly before that). Functionally equivalent; refactor-safer.

---

### `/exempt` — declare today an exemption day

**Action:** POST `/api/services/script/mark_exemption_today`
**Body:** `{}`
**Response handling:** Ignore — the script sends its own Telegram confirmation.

**Effect** (per Handoff §6.3): pauses tonight's eval, pauses screen-time warnings + late-phone demerit, **lifts all AdGuard blocks for the day**, costs 1 from the exemption bank. Midnight reset flips exemption off → punishment enforcer fires → blocks return based on actual points.

**Failure modes the script handles natively:** already exempt today, zero days left, called after 23:20 (auto-restores pre-eval points). All produce their own Telegram messages — Jarvis routes the call and stays silent.

---

### `/exempt_status` — check without triggering

**Action:** POST `/api/template`
**Body template:**
```jinja
{% if is_state('input_boolean.exemption_today', 'on') %}🛋️ Today is an exemption day. All AdGuard blocks lifted; no eval tonight.
{% else %}📋 Normal day. No exemption active.
{% endif %}{% if is_state('binary_sensor.jarvis_relaxed_day', 'on') %}🌴 Relaxed day — screen limit {{ states('sensor.jarvis_screen_limit_today') | int }} min.
{% endif %}Exemption days available: {{ states('sensor.jarvis_exemption_days_view') | int }}.
Overflow progress: {{ states('sensor.jarvis_overflow_points_view') | int }}/{{ states('input_number.jarvis_points_per_exemption') | int }}.
```

---

### `/holiday` — declare today a soft day (relaxed screen limit)

**Action:** POST `/api/services/script/jarvis_mark_holiday_today`
**Body:** `{}`
**Response handling:** Ignore — the script sends its own Telegram confirmation.

**vs `/exempt`:** holiday still scores you (eval runs as normal); it only raises the screen-time limit (210 min vs 120 default). No exemption-bank cost. Auto-clears at midnight. See Cheatsheet "Today modes" for the full mode comparison.

---

### `/tasks_done` — confirm house tasks done

**Enhanced flow** (not a simple curl — requires file I/O):
1. Read `/home/danny/.openclaw/shared-house/house_tasks.json`
2. Filter pending tasks due today or earlier
3. If pending: list them, ask Danny to confirm. On confirm, mark `status: "done"` with `completed_at` in the file, set `last_updated_by: "jarvis"`
4. If no pending (or after marking): POST `/api/services/script/mark_tasks_done` with `{}` to flip the HA boolean

**Fallback:** If the file is missing or unreadable, skip to step 4 (simple HA script call).

This is the natural reply to the 22:30 IST house-tasks prompt automation, but can also be sent unprompted any time during the day.

---

### `/health` — system health snapshot (recommended new command)

**Action:** POST `/api/template`
**Body template:**
```jinja
🩺 *System health*

Tasker last poll: {{ states('sensor.jarvis_minutes_since_tasker_poll') | int }} min ago
AdGuard last sync: {{ states('sensor.jarvis_minutes_since_adguard_sync') | int }} min ago

AdGuard protection: {{ states('switch.adguard_home_protection_2') }}
AdGuard filtering: {{ states('switch.adguard_home_filtering_2') }} ← required for blocks
Phone WiFi: {{ states('sensor.danny_s23_wi_fi_connection') }}
Phone tracker: {{ states('device_tracker.danny_s23') }}

{% if states('sensor.jarvis_minutes_since_tasker_poll') | int > 15 %}⚠️ Tasker stale (>15 min)
{% endif %}{% if states('sensor.jarvis_minutes_since_adguard_sync') | int > 30 %}⚠️ AdGuard sync stale (>30 min)
{% endif %}
```

(The Health Watchdog automation will Telegram-alert proactively, but `/health` lets you check on demand.)

---

## Implementation pattern for OpenClaw (pseudocode)

```python
COMMAND_ROUTES = {
  "/status": {
    "method": "POST",
    "path": "/api/template",
    "body": {"template": "<paste /status template from above>"},
    "response": "forward_markdown"
  },
  "/points":         {"method": "POST", "path": "/api/template", "body": {...}, "response": "forward_markdown"},
  "/screen":         {"method": "POST", "path": "/api/template", "body": {...}, "response": "forward_markdown"},
  "/habits":         {"method": "POST", "path": "/api/template", "body": {...}, "response": "forward_markdown"},
  "/exempt_status":  {"method": "POST", "path": "/api/template", "body": {...}, "response": "forward_markdown"},
  "/health":         {"method": "POST", "path": "/api/template", "body": {...}, "response": "forward_markdown"},
  "/exempt":         {"method": "POST", "path": "/api/services/script/mark_exemption_today",      "body": {}, "response": "ignore"},
  "/holiday":        {"method": "POST", "path": "/api/services/script/jarvis_mark_holiday_today", "body": {}, "response": "ignore"},
  "/tasks_done":     {"method": "POST", "path": "/api/services/script/mark_tasks_done",           "body": {}, "response": "ignore"},
}

def handle_message(msg):
  cmd = msg.text.split()[0] if msg.text.startswith("/") else None

  if cmd and cmd in COMMAND_ROUTES:
    route = COMMAND_ROUTES[cmd]
    r = requests.request(
      route["method"],
      f"http://192.168.0.124:8123{route['path']}",
      headers={"Authorization": f"Bearer {JARVIS_LLAT}"},
      json=route["body"]
    )
    if route["response"] == "forward_markdown":
      telegram.send(msg.chat_id, r.text, parse_mode="Markdown")
    return  # DONE — no Claude invoked

  # Fall through to Claude for conversational messages
  invoke_claude_agent(msg)
```

---

## Future-proofing: adding a new module

1. **HA side:** Add new entities (helpers, automations, scripts). Optionally add a `*_view` wrapper sensor for stability.
2. **OpenClaw side:** Add a new route entry with its Jinja template. Reference view sensors, not raw entities.
3. **Done.** No Claude tokens, no HA routing changes.

---

## One thing to tell Jarvis explicitly

Update the Jarvis system prompt in OpenClaw to add:

> For the habits module: slash commands matching the routing table are handled
> natively via HA API. Do NOT attempt to answer `/status`, `/points`, `/screen`,
> `/habits`, `/exempt`, `/exempt_status`, `/holiday`, `/tasks_done`, `/health` —
> the router handles these before you see them. For anything conversational
> about habits, you may still query HA via the REST API using the Jarvis
> long-lived token. When templating, prefer `sensor.jarvis_*_view` and
> `binary_sensor.jarvis_*_view` over raw `input_number.*` for stability across
> refactors.
