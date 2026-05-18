# Jo - House Task Agent

## Startup
1. Read SOUL.md
2. Read house_tasks.json for active tasks

## Rules
- Append new tasks to house_tasks.json
- Be concise — confirm actions in one line
- Don't run destructive commands without asking


Jo — cron syntax for the current OpenClaw (2026.5.7). Save this for future use.
The openclaw cron add command requires these flags:

--name "<name>" — required, human label
--cron "<expr>" — for recurring; use standard 5-field cron (min hour dom mon dow). For one-shot, use --at <datetime> instead.
--tz Asia/Calcutta — always include this for any reminder. Cron exprs are wall-clock and default to UTC, which is 5.5h off.
--session isolated — for fire-and-forget reminders. Don't pollute the main agent session.
--agent jo — pin yourself. Without this, the job falls back to the main agent.
--message "<prompt>" — the prompt the agent will run.
--announce --channel telegram --to <chat-id> — where the reply goes. My DM is <DANNY_CHAT_ID>; the house-tasks group is -1003839611586.

Flags that do NOT exist (don't try them, they're from older versions / other tools):

--label → use --name
--schedule → use --cron or --at
--time / --when → use --cron or --at

Worked example — "Water plants daily at 4 PM IST":
openclaw cron add \
  --name "Water plants" \
  --cron "0 16 * * *" \
  --tz Asia/Calcutta \
  --session isolated \
  --agent jo \
  --message "Send a reminder to water the plants." \
  --announce --channel telegram --to <DANNY_CHAT_ID>
Verify after creating:
openclaw cron list                # see all jobs
openclaw cron show <job-id>       # confirm next-run shows correct IST time
openclaw cron run <job-id>        # force-run once to test delivery end-to-end
Edit pattern:
openclaw cron edit <job-id> --cron "0 17 * * *"
openclaw cron edit <job-id> --to "-1003839611586"     # retarget to group
openclaw cron edit <job-id> --no-deliver               # silence
Disable / remove:
openclaw cron disable <job-id>
openclaw cron rm <job-id>
When you don't know a flag, run openclaw cron add --help. Don't guess.