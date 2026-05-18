# House Tasks & Reminders — Shared Schema & Integration Guide

**Audience:** Jo (house-tasks agent), Jarvis (habits agent), Claude (HA admin)
**Location:** `/home/danny/.openclaw/shared-house/`
**Ownership:** Jo writes both files. Jarvis reads `house_tasks.json` + marks complete.

---

## File 1: `house_tasks.json` — Today's active task list

This is what Jarvis reads for the habits system. It answers: "what does Danny need to do today, and has he done it?"

```json
{
  "tasks": [
    {
      "id": 1,
      "task": "Do the dishes",
      "assigned_by": "maria",
      "source": "direct",
      "created": "2026-05-13",
      "due": "2026-05-13",
      "status": "pending",
      "completed_at": null
    },
    {
      "id": 2,
      "task": "Water plants",
      "assigned_by": "danny",
      "source": "recurring:water_plants",
      "created": "2026-05-13",
      "due": "2026-05-13",
      "status": "done",
      "completed_at": "2026-05-13T11:45:00+05:30"
    }
  ],
  "last_updated": "2026-05-13T11:45:00+05:30",
  "last_updated_by": "jo"
}
```

### Field definitions

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | int | yes | Auto-increment. Highest existing id + 1. |
| `task` | string | yes | Short description. Plain text, no markdown. |
| `assigned_by` | string | yes | `"danny"` or `"maria"`. |
| `source` | string | yes | `"direct"` (assigned in chat), `"reminder:<id>"` (from one-off reminder), or `"recurring:<cron_label>"` (from recurring cron). Tells you where the task came from. |
| `created` | date | yes | `YYYY-MM-DD` IST. |
| `due` | date | yes | `YYYY-MM-DD` IST. Default: today. |
| `status` | string | yes | `"pending"` or `"done"`. |
| `completed_at` | datetime/null | yes | ISO 8601 IST when done. `null` while pending. |

### Rules

1. **IDs never reused.** Next id = `max(existing ids) + 1`. Start at 1 if empty.
2. **All timestamps IST** with `+05:30` offset.
3. **Atomic writes.** Read, modify in memory, write back. No partial updates.
4. **No templates or schedules here.** This file is the live task list. Recurring tasks create fresh entries each time they fire — the schedule lives in the cron job or reminders.json.

---

## File 2: `reminders.json` — One-off scheduled reminders

For reminders with a future due date. A single daily cron reads this file and fires due reminders.

```json
{
  "reminders": [
    {
      "id": "r1",
      "task": "Pay electricity bill",
      "assigned_by": "danny",
      "created": "2026-05-13",
      "due": "2026-05-16",
      "remind_at": "09:00",
      "status": "pending",
      "fired_at": null
    },
    {
      "id": "r2",
      "task": "Clean laundry",
      "assigned_by": "maria",
      "created": "2026-05-13",
      "due": "2026-05-14",
      "remind_at": "09:00",
      "status": "fired",
      "fired_at": "2026-05-14T09:00:00+05:30"
    }
  ],
  "last_updated": "2026-05-14T09:00:00+05:30",
  "last_updated_by": "jo"
}
```

### Field definitions

| Field | Type | Notes |
|---|---|---|
| `id` | string | Prefix `r` + increment. e.g. `"r1"`, `"r2"`. |
| `task` | string | What to remind about. |
| `assigned_by` | string | `"danny"` or `"maria"`. |
| `created` | date | When the reminder was created. |
| `due` | date | When to fire the reminder. |
| `remind_at` | time | `HH:MM` in IST. Default `"09:00"` if not specified. |
| `status` | string | `"pending"` or `"fired"`. |
| `fired_at` | datetime/null | When the reminder was actually sent. |

### Lifecycle

```
User says "remind me to X on Friday"
  → Jo adds entry: status "pending", due Friday, remind_at "09:00"

Friday 9AM: Jo's daily reminder cron fires
  → Reads reminders.json
  → Finds all entries where due <= today AND status == "pending"
  → For each:
      1. Send Telegram: "Reminder: Pay electricity bill"
      2. Add to house_tasks.json as pending task (source: "reminder:r1")
      3. Set status: "fired", fired_at: now()
  → Write back

Daily cleanup: remove entries where status == "fired" and fired_at < today
```

---

## Recurring reminders — Cron jobs (no file needed)

Recurring reminders are **cron jobs**, not file entries. Each gets its own `openclaw cron add`.

### Examples

| Request | Cron schedule | Label |
|---|---|---|
| "Water plants every day at 11 AM" | `0 11 * * *` | `recurring_water_plants` |
| "Pay rent last day of every month" | `0 9 28-31 * *` (with last-day logic in prompt) | `recurring_rent` |
| "Remind me to clean AC filter every 2 weeks" | `0 9 1,15 * *` | `recurring_ac_filter` |
| "Take out garbage every Tuesday and Friday" | `0 9 * * 2,5` | `recurring_garbage` |

### Cron job prompt template

Each recurring cron job should have a prompt like:

```
You are Jo, the house-tasks agent. This is a recurring reminder.
Task: "Water plants"
Assigned by: danny

Do the following:
1. Send a Telegram message to Danny: "🔔 Reminder: Water plants"
2. Read /home/danny/.openclaw/shared-house/house_tasks.json
3. Add a new task entry:
   - task: "Water plants"
   - assigned_by: "danny"
   - source: "recurring:water_plants"
   - due: today
   - status: "pending"
4. Write the file back.
```

### "Last day of month" pattern

Cron doesn't natively support "last day of month." Use `0 9 28-31 * *` with a condition in the prompt:

```
Only proceed if today is the last day of this month:
  {% set today = now() %}
  {% set tomorrow = today + timedelta(days=1) %}
  If tomorrow.month != today.month: this is the last day, proceed.
  Otherwise: skip silently.
```

Or simpler: schedule for the 28th of every month. Close enough for a rent reminder.

---

## How the two tiers interact

```
                ┌─────────────────────────────────┐
                │     User request in chat         │
                └──────────┬──────────────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
         One-off?                  Recurring?
              │                         │
              ▼                         ▼
     reminders.json              openclaw cron add
     (future due date)           (own schedule)
              │                         │
              │   Daily 9AM cron        │   Fires on schedule
              ▼                         ▼
         ┌─────────────────────────────────┐
         │  When a reminder fires:         │
         │  1. Telegram to Danny           │
         │  2. Add to house_tasks.json     │
         └──────────────┬──────────────────┘
                        │
                        ▼
              house_tasks.json
              (Jarvis reads for habits)
                        │
                        ▼
         input_boolean.tasks_completed_today
              (HA scoring signal)
```

---

## Daily cron job for one-off reminders

Jo needs ONE scheduled cron that runs daily at 09:00 IST:

**Label:** `jo_daily_reminders`
**Schedule:** `0 9 * * *` (Asia/Calcutta)
**Prompt:**

```
You are Jo, the house-tasks agent. This is your daily reminder check.

1. Read /home/danny/.openclaw/shared-house/reminders.json
2. Find all entries where:
   - status == "pending"
   - due <= today (in IST)
3. For each matching entry:
   a. Send Telegram to Danny: "🔔 Reminder: {task}" (add "from Maria" if assigned_by is maria)
   b. Read house_tasks.json, add a pending task with source "reminder:{id}"
   c. Mark the reminder as status: "fired", fired_at: now()
4. Write both files back.
5. Clean up: remove any "fired" reminders where fired_at is before today.

If reminders.json doesn't exist or is empty, do nothing.
If no reminders are due today, do nothing.
```

---

## Default time rules

| Scenario | Default remind_at |
|---|---|
| No time specified | `09:00` IST |
| "in the morning" | `09:00` |
| "in the afternoon" | `14:00` |
| "in the evening" | `18:00` |
| Specific time given ("at 11 AM") | Use that time |
| Recurring with specific time | Bake into cron schedule |
| Recurring, no time | `09:00` in cron schedule |
