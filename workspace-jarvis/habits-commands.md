# Jarvis Habits — Command Reference

When you receive any of these commands, respond by executing the corresponding curl command and formatting the result for Telegram. Do NOT use the LLM to reason about the data — just fetch and present.

## HA Connection
- **URL:** http://192.168.0.124:8123
- **Token:** See TOOLS.md for the Bearer token
- **Template endpoint:** POST to `/api/template` with `{"template": "JINJA_TEMPLATE"}`

## Commands

### "habits" or "commands" or "help habits"
Show this list:
```
📋 Jarvis Habits Commands:

status — Full dashboard (points, zone, habits, steps, exemptions)
points — Demerit points and zone
screen — Screen time breakdown today
habits — Today's habit check (gym, guitar, screen, tasks, steps, phone)
exempt — Use an exemption day (costs 1 day)
exempt status — Check exemption bank
holiday — Soft day (relaxed screen limit, eval still runs)
tasks_done — Confirm house tasks done (checks shared task list)
health — System health snapshot
help habits — This list
```

### "status"
Fetch full dashboard. Run:
```bash
curl -s -X POST http://192.168.0.124:8123/api/template \
  -H "Authorization: Bearer $(cat /home/danny/.openclaw/workspace-jarvis/ha-token.txt)" \
  -H "Content-Type: application/json" \
  -d '{"template": "📊 *Status*\n\nPoints: {{ states(\"sensor.jarvis_demerit_points_view\") | int }}/{{ states(\"input_number.jarvis_points_max\") | int }} ({{ states(\"sensor.demerit_zone\") }})\n{% if is_state(\"input_boolean.exemption_today\", \"on\") %}🛋️ Exempt day — no eval tonight, all AdGuard blocks lifted\n{% elif is_state(\"binary_sensor.jarvis_relaxed_day\", \"on\") %}🌴 Relaxed day — screen limit {{ states(\"sensor.jarvis_screen_limit_today\") | int }} min\n{% endif %}\nScreen: {{ states(\"sensor.phone_screen_time_total\") | int }}/{{ states(\"sensor.jarvis_screen_limit_today\") | int }} min\nGym: {{ \"done ✅\" if is_state(\"binary_sensor.jarvis_gym_status_view\", \"on\") else \"pending ⏳\" }}\nGuitar: {{ states(\"sensor.jarvis_guitar_view\") | int }}/{{ states(\"input_number.jarvis_guitar_target_minutes\") | int }} min\nTasks: {{ \"done ✅\" if is_state(\"binary_sensor.jarvis_tasks_view\", \"on\") else \"pending ⏳\" }}\nSteps: {{ states(\"sensor.garmin_connect_steps\") | int }}/{{ states(\"input_number.jarvis_steps_target\") | int }} {{ \"✅ bonus\" if states(\"sensor.garmin_connect_steps\") | int >= states(\"input_number.jarvis_steps_target\") | int else \"⏳\" }}\n\nExemption days: {{ states(\"sensor.jarvis_exemption_days_view\") | int }}\nOverflow: {{ states(\"sensor.jarvis_overflow_points_view\") | int }}/{{ states(\"input_number.jarvis_points_per_exemption\") | int }}"}'  
```
Forward the response text directly to the user.

### "points"
```bash
curl -s -X POST http://192.168.0.124:8123/api/template \
  -H "Authorization: Bearer $(cat /home/danny/.openclaw/workspace-jarvis/ha-token.txt)" \
  -H "Content-Type: application/json" \
  -d '{"template": "🎯 Points: {{ states(\"sensor.jarvis_demerit_points_view\") | int }}/{{ states(\"input_number.jarvis_points_max\") | int }}\n🚦 Zone: {{ states(\"sensor.demerit_zone\") | upper }}\nExemption days: {{ states(\"sensor.jarvis_exemption_days_view\") | int }}\nOverflow: {{ states(\"sensor.jarvis_overflow_points_view\") | int }}/{{ states(\"input_number.jarvis_points_per_exemption\") | int }}"}'
```

### "screen"
```bash
curl -s -X POST http://192.168.0.124:8123/api/template \
  -H "Authorization: Bearer $(cat /home/danny/.openclaw/workspace-jarvis/ha-token.txt)" \
  -H "Content-Type: application/json" \
  -d '{"template": "📱 Screen time {{ states(\"sensor.phone_screen_time_total\") | int }}/{{ states(\"sensor.jarvis_screen_limit_today\") | int }} min{% if is_state(\"binary_sensor.jarvis_relaxed_day\", \"on\") %} (relaxed){% endif %}\n\nYouTube: {{ states(\"sensor.jarvis_youtube_view\") | int }}\nInstagram: {{ states(\"sensor.jarvis_instagram_view\") | int }}\nNetflix: {{ states(\"sensor.jarvis_netflix_view\") | int }}\nPrime: {{ states(\"sensor.jarvis_prime_view\") | int }}\nHotstar: {{ states(\"sensor.jarvis_hotstar_view\") | int }}\nBrave: {{ states(\"sensor.jarvis_brave_view\") | int }}"}'  
```

### "habits"
```bash
curl -s -X POST http://192.168.0.124:8123/api/template \
  -H "Authorization: Bearer $(cat /home/danny/.openclaw/workspace-jarvis/ha-token.txt)" \
  -H "Content-Type: application/json" \
  -d '{"template": "🎯 *Today'\''s habits*\n\n{{ \"✅\" if is_state(\"binary_sensor.jarvis_gym_status_view\", \"on\") else \"❌\" }} Gym\n{{ \"✅\" if states(\"sensor.jarvis_guitar_view\") | int >= states(\"input_number.jarvis_guitar_target_minutes\") | int else \"❌\" }} Guitar ({{ states(\"sensor.jarvis_guitar_view\") | int }}/{{ states(\"input_number.jarvis_guitar_target_minutes\") | int }} min)\n{{ \"✅\" if states(\"sensor.phone_screen_time_total\") | int <= states(\"sensor.jarvis_screen_limit_today\") | int else \"❌\" }} Screen time ({{ states(\"sensor.phone_screen_time_total\") | int }}/{{ states(\"sensor.jarvis_screen_limit_today\") | int }} min){% if is_state(\"binary_sensor.jarvis_relaxed_day\", \"on\") %} 🌴{% endif %}\n{{ \"✅\" if is_state(\"binary_sensor.jarvis_tasks_view\", \"on\") else \"❌\" }} House tasks\n{{ \"✅\" if is_state(\"binary_sensor.jarvis_phone_late_view\", \"on\") else \"❌\" }} Phone off by 11:30 PM\n{{ \"✅\" if states(\"sensor.garmin_connect_steps\") | int >= states(\"input_number.jarvis_steps_target\") | int else \"❌\" }} Steps ({{ states(\"sensor.garmin_connect_steps\") | int }}/{{ states(\"input_number.jarvis_steps_target\") | int }}) — bonus only"}'  
```

### "exempt"
This is a WRITE action. Call the HA script:
```bash
curl -s -X POST http://192.168.0.124:8123/api/services/script/mark_exemption_today \
  -H "Authorization: Bearer $(cat /home/danny/.openclaw/workspace-jarvis/ha-token.txt)" \
  -H "Content-Type: application/json" \
  -d '{}'
```
Then confirm to the user: "✅ Exemption requested. HA will confirm via Telegram if successful."

If the response contains an error, tell the user what went wrong.

### "exempt status"
```bash
curl -s -X POST http://192.168.0.124:8123/api/template \
  -H "Authorization: Bearer $(cat /home/danny/.openclaw/workspace-jarvis/ha-token.txt)" \
  -H "Content-Type: application/json" \
  -d '{"template": "{% if is_state(\"input_boolean.exemption_today\", \"on\") %}🛋️ Today is an exemption day. All AdGuard blocks lifted; no eval tonight.\n{% else %}📋 Normal day. No exemption active.\n{% endif %}{% if is_state(\"binary_sensor.jarvis_relaxed_day\", \"on\") %}🌴 Relaxed day — screen limit {{ states(\"sensor.jarvis_screen_limit_today\") | int }} min.\n{% endif %}\nExemption days available: {{ states(\"sensor.jarvis_exemption_days_view\") | int }}.\nOverflow progress: {{ states(\"sensor.jarvis_overflow_points_view\") | int }}/{{ states(\"input_number.jarvis_points_per_exemption\") | int }}."}'  
```

### "holiday" (or "soft day", "declare holiday")
Declare today a soft day (relaxed screen limit, eval still runs). Run:
```bash
curl -s -X POST http://192.168.0.124:8123/api/services/script/jarvis_mark_holiday_today \
  -H "Authorization: Bearer $(cat /home/danny/.openclaw/workspace-jarvis/ha-token.txt)" \
  -H "Content-Type: application/json" \
  -d '{}'
```
The script sends its own Telegram confirmation. Route silently unless there's an error.

### "tasks_done" (or "tasks done", "finished tasks", "house tasks done")
Enhanced flow — read shared house tasks, mark done in file, then flip HA boolean:

1. Read `/home/danny/.openclaw/shared-house/house_tasks.json`
2. Filter for tasks where `due <= today` (IST) and `status == "pending"`
3. **If no pending tasks:**
   - Call the HA script (step 5 below)
   - Reply: "No pending house tasks. Marked done for tonight's eval (+1)."
4. **If pending tasks exist:**
   - List them: "You have N pending house tasks:\n • Water plants\n • Garbage collection\nMark all done?"
   - **Danny confirms:** mark each `status: "done"` with `completed_at: now()` (ISO 8601 IST), set `last_updated_by: "jarvis"`, write back, then proceed to step 5
   - **Danny says only some are done:** mark those, list remaining, ask if he still wants the habits credit
5. Call the HA script to flip the boolean:
```bash
curl -s -X POST http://192.168.0.124:8123/api/services/script/mark_tasks_done \
  -H "Authorization: Bearer $(cat /home/danny/.openclaw/workspace-jarvis/ha-token.txt)" \
  -H "Content-Type: application/json" \
  -d '{}'
```
The script sends its own Telegram confirmation.

**Edge cases:**
- File missing or unreadable: fall back to simple flow — just call the HA script and confirm
- Overdue tasks from previous days: mention them but don't block tasks_done
- Danny says tasks_done before Jo added anything: empty list = done, flip the boolean

### "health" (or "system health", "is everything ok")
System health snapshot. Run:
```bash
curl -s -X POST http://192.168.0.124:8123/api/template \
  -H "Authorization: Bearer $(cat /home/danny/.openclaw/workspace-jarvis/ha-token.txt)" \
  -H "Content-Type: application/json" \
  -d '{"template": "🩺 *System health*\n\nTasker last poll: {{ states(\"sensor.jarvis_minutes_since_tasker_poll\") | int }} min ago\nAdGuard last sync: {{ states(\"sensor.jarvis_minutes_since_adguard_sync\") | int }} min ago\n\nAdGuard protection: {{ states(\"switch.adguard_home_protection_2\") }}\nAdGuard filtering: {{ states(\"switch.adguard_home_filtering_2\") }} ← required for blocks\nPhone WiFi: {{ states(\"sensor.danny_s23_wi_fi_connection\") }}\nPhone tracker: {{ states(\"device_tracker.danny_s23\") }}\n\n{% if states(\"sensor.jarvis_minutes_since_tasker_poll\") | int > 15 %}⚠️ Tasker stale (>15 min)\n{% endif %}{% if states(\"sensor.jarvis_minutes_since_adguard_sync\") | int > 30 %}⚠️ AdGuard sync stale (>30 min)\n{% endif %}"}'  
```
Forward verbatim with markdown.

## Important Rules
- When you see messages like "status", "points", "screen", "habits", "exempt", "exempt status", "holiday", "tasks_done", "health", or "help habits" — execute the command immediately. Don't ask clarifying questions.
- These are natural language triggers, NOT slash commands (slash commands clash with OpenClaw built-ins).
- Also match variations: "what's my status", "show points", "screen time", "use exemption", "how many exemptions", "soft day", "finished tasks", "system health", etc.
- Forward the HA template response as-is (it's already formatted for Telegram).
- If curl fails, report the error clearly.
- For "exempt", "holiday", "tasks_done", HA's scripts send their own Telegram confirmations. Route silently unless there's an error.
- These commands work in Jarvis Telegram DM only.
