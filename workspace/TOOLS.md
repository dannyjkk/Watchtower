# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## What Goes Here

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Examples

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

## Telegram Media Delivery

**`MEDIA:` lines are NOT reliable for delivering actual file attachments on Telegram.**
They may render in the web UI but the user may receive no file in the Telegram chat.

**For guaranteed file delivery on Telegram, use the native outbound path:**
```bash
openclaw message send --channel telegram --target <chat_id> --message "..." --media /absolute/path/to/file
```
- To prevent Telegram from compressing images/GIFs: add `--force-document`
- Treat `MEDIA:` as a convenience render hint only, not a guaranteed attachment mechanism

---

Add whatever helps you do your job. This is your cheat sheet.
