# TOOLS.md — Jarvis

## Home Assistant
- **URL:** http://192.168.0.124:8123
- **Token:** stored at `/home/danny/.openclaw/workspace-jarvis/ha-token.txt` (read inline via `cat` in curl commands — see `habits-commands.md`)
- **Usage:** `curl -s -H "Authorization: Bearer $(cat /home/danny/.openclaw/workspace-jarvis/ha-token.txt)" -H "Content-Type: application/json" http://192.168.0.124:8123/api/states`

## Google (via gog CLI)
- **Account:** <YOUR_EMAIL>
- **Gmail:** `gog gmail list`, `gog gmail read <id>`, etc.
- **Calendar:** `gog calendar list`, `gog calendar events`, etc.
- **Tasks:** `gog tasks list`, `gog tasks items <listId>`, etc.

## Delivery
- **Target:** Danny on Telegram DM
- **Command:** `openclaw message send --channel telegram --account jarvis --target "<DANNY_CHAT_ID>" --message "MESSAGE"`

## Telegram Group (Jo's domain)
- **House Tasks group:** -1003839611586
- **Jo's account:** jo
- Route Maria-relevant info through Jo, not directly
