# Setup Guide

A step-by-step guide to replicate this system. Each section covers broad setup steps with links to official documentation for the details. Even if you're new to these tools, you should be able to get this running — especially with an AI coding assistant to help fill in the gaps.

> **Stuck on a step?** Load this entire repo into [Claude Code](https://claude.ai/claude-code), [Codex](https://openai.com/index/introducing-codex/), or any AI coding assistant. It can ingest the full codebase — configs, automations, scripts, docs — and answer questions, debug issues, or help you adapt configs to your setup as you build.

> **GitHub:** [github.com/dannyjkk/Watchtower](https://github.com/dannyjkk/Watchtower)

---

## What You'll Need

### Hardware

| Item | Purpose | Notes |
|------|---------|-------|
| **Mini PC** (or equivalent) | Runs Home Assistant, AdGuard, and OpenClaw | **Must be always-on.** The entire system depends on it — if it goes down, habit tracking, DNS filtering, and all automations stop. A mini PC with UPS is ideal. **16 GB RAM recommended** (8 GB bare minimum). Reference specs: Intel N150, 16 GB RAM, 256 GB SSD — handles everything comfortably. |
| **Android phone** | Screen time tracking via Tasker, gym detection via GPS | iPhone users would need to find alternatives to Tasker |
| **Smart lights** (optional) | WiZ bulbs or similar HA-compatible lights | Alternatives: Philips Hue, IKEA Tradfri, any Zigbee/Z-Wave bulbs. For the automated lighting and power cut management features. |
| **Robot vacuum** (optional) | HA-integrated vacuum with room/area support | Alternatives: Roborock, Ecovacs, iRobot — any with HA integration. For NFC tag control. |
| **NFC tags** (optional) | Physical tags for vacuum control | One per room you want to control |
| **Fitness tracker** (optional) | Garmin or any HA-integrated tracker | Alternatives: Fitbit, Withings, Samsung Health, Google Fit — any with an HA integration. For step counting. |
| **Secondary router** (optional) | On a different circuit, no UPS | For power cut detection — only useful if you have frequent outages |

### Accounts & API Keys

| Account | Purpose | Cost |
|---------|---------|------|
| **Telegram** | Interface for all agents | Free |
| **LLM API** (Anthropic, OpenAI, Google, Mistral, etc.) | Powers Kal-El + Jarvis — any provider that OpenClaw supports | Pay per token |
| **Lightweight LLM** (Ollama cloud, LM Studio, or equivalent) | Powers Jo (house tasks) | Ollama free tier is sufficient |
| **Garmin Connect** (optional) | Step tracking via HA integration | Free (with Garmin device) |
| **Tailscale** (optional) | Secure remote access to HA and OpenClaw | Free for personal use |

**On model selection:** Kal-El should be your most capable model (handles complex reasoning, coding, research). Jarvis should be the sweet spot between capability and token cost (runs frequently, needs to be reliable but doesn't need frontier-level reasoning). Jo is lightweight — any decent model handles house task parsing.

**On local vs. cloud models:** Typical mini PCs (Intel N100, etc.) don't have the GPU or RAM to run local LLMs at usable speeds. Cloud LLM APIs are the practical choice — Ollama's cloud offering has a free tier that's more than sufficient for a lightweight agent like Jo. If you have a machine with a dedicated GPU (or a Mac with Apple Silicon), local models via Ollama or LM Studio become viable.

---

## Step 1: Server Setup (Mini PC)

The recommended approach is **Proxmox** on the mini PC, running two VMs:

1. **Ubuntu Server VM** — runs OpenClaw, AdGuard Home, and general-purpose tasks
2. **HAOS (Home Assistant OS) VM** — dedicated Home Assistant instance

### Why Proxmox?

Running HA and your other services on separate VMs means:
- HA restarts don't take down AdGuard (important — if AdGuard goes down during an HA restart, DNS filtering stops and blocks are temporarily bypassed)
- You can snapshot and roll back VMs independently
- Clean separation of concerns

### Alternatives

- **Bare metal Ubuntu** with HA in Docker — simpler but less isolation
- **Mac Mini** — excellent always-on machine; install HA as a Docker container or VM via UTM
- **Docker / Docker Compose** — run HA Container + AdGuard + OpenClaw without a hypervisor. Simpler but no VM snapshots.
- **Unraid / TrueNAS** — NAS-oriented hypervisors with VM and container support; good if you already run one
- **Raspberry Pi** — works but limited CPU/RAM for running multiple agents
- **Any always-on Linux machine** — the key requirement is that it stays on 24/7

> **HA install types:** This guide assumes HAOS (Home Assistant OS) in a VM. HA also supports [Container](https://www.home-assistant.io/installation/linux#install-home-assistant-container) and [Supervised](https://www.home-assistant.io/installation/linux#install-home-assistant-supervised) installs. Container is lighter but lacks add-on support; Supervised gives you add-ons on any Debian-based host.

### Proxmox Setup

1. Install Proxmox VE on the mini PC — [proxmox.com/downloads](https://www.proxmox.com/en/downloads)
2. Create an Ubuntu Server VM (for OpenClaw + AdGuard)
3. Create an HAOS VM — follow the [HA Proxmox guide](https://www.home-assistant.io/installation/alternative#install-home-assistant-operating-system)
4. **Give both VMs static IPs on your LAN** — this is critical. SSH connections, webhook URLs, DNS settings, Samba mounts, and agent configs all reference devices by IP. If IPs drift via DHCP, things silently break. Assign static IPs (either via your router's DHCP reservation or in each VM's network config) for:
   - The Ubuntu VM (AdGuard + OpenClaw)
   - The HAOS VM (Home Assistant)
   - Your Android/iOS phone (Tasker webhooks, AdGuard client matching)
   - The secondary router, if using power cut detection

### Remote Access to the Mini PC

Set up easy access from your main PC:

- **Samba file share** — mount the Ubuntu VM's filesystem as a network drive. Makes editing OpenClaw config files trivial (just open them in your editor).
  ```bash
  # On Ubuntu VM
  sudo apt install samba
  # Configure /etc/samba/smb.conf to share your home directory
  ```
- **SSH** — for terminal access to both VMs
  ```bash
  ssh danny@<ubuntu-vm-ip>     # Ubuntu VM
  ssh danny@<ha-ip> -p 22222   # HA SSH add-on (if installed)
  ```
- **HA SSH add-on** — install from the add-on store for `scp` access to HA config files. Note: use `scp -O` (legacy SCP protocol) because the HA SSH add-on doesn't support the SFTP subsystem.

**Alternatives to Samba:** NFS (faster, Linux-native), SSHFS (mount over SSH — no extra server needed), or just use `scp` for file transfers.

---

## Step 2: Home Assistant

### Initial Setup

1. Access HAOS at `http://<ha-ip>:8123`
2. Create your user account
3. Set your home location and timezone

Official docs: [home-assistant.io/getting-started](https://www.home-assistant.io/getting-started/)

### Essential Add-ons

Install from **Settings > Add-ons**:

| Add-on | Purpose |
|--------|---------|
| **File Editor** (or Studio Code Server) | Edit YAML files directly in the browser. Essential for tweaking automations and scripts. |
| **SSH & Web Terminal** | Terminal access + `scp` for pulling config files to the repo |

### HA Companion App

Install the **Home Assistant Companion App** on your Android phone. This provides:
- **Location tracking** — needed for gym zone detection (person entity)
- **Battery sensors** — phone battery level, charging state
- **Push notifications** — power cut alerts, gym confirmations
- **Wi-Fi connection sensor** — used to rule out GPS drift (gym detection ignores triggers when on home Wi-Fi)
- **Volume sensors** — Maria's phone ringer monitoring
- **NFC tag scanning** — tap physical tags to trigger automations

After installing, verify that `person.<your_name>` appears in HA with location updates.

### Create Helpers

The automations and scripts reference many helpers. Create these in **Settings > Devices & Services > Helpers**:

**Toggles (input_boolean):**
- `gym_visited_today` — flipped by gym exit automation
- `phone_used_late` — flipped by late phone webhook
- `exemption_today` — declared by user
- `jarvis_holiday_today` — declared by user
- `tasks_completed_today` — flipped by tasks_done script
- `power_cut_active` — managed by power automations
- `adguard_blocked` — reflects current blocking state

**Numbers (input_number):**

*Points system:*
- `demerit_points` (min: 0, max: 12, step: 1)
- `exemption_days` (min: 0, max: 99, step: 1)
- `overflow_points` (min: 0, max: 99, step: 1)
- `pre_eval_points` (min: 0, max: 12, step: 1) — snapshot before nightly eval

*Phone usage (all min: 0, max: 1440, step: 1):*
- `phone_youtube_usage`
- `phone_instagram_usage`
- `phone_netflix_usage`
- `phone_prime_video_usage`
- `phone_jiohotstar_usage`
- `phone_brave_usage`
- `phone_guitar_usage`

*Tunable thresholds:*
- `jarvis_guitar_target_minutes` (default: 20)
- `jarvis_screen_limit_normal` (default: 120)
- `jarvis_screen_limit_relaxed` (default: 210)
- `jarvis_gym_min_minutes` (default: 20)
- `jarvis_steps_target` (default: 8000)
- `jarvis_points_max` (default: 12)
- `jarvis_points_per_exemption` (default: 6)

*Daily result trackers (for dashboard/history):*
- `daily_gym_result`, `daily_guitar_result`, `daily_screen_result`, `daily_tasks_result`, `daily_steps_result`, `daily_total_delta`

*Light state backup:*
- `backlight_saved_brightness`, `frontlight_saved_brightness`

**Date/Time (input_datetime):**
- `jarvis_gym_entered_at`
- `jarvis_last_tasker_poll`
- `jarvis_last_adguard_sync`
- `jarvis_last_health_alert`
- `power_cut_start`, `power_cut_end`

**Text (input_text):**
- `light_state_backup` (max: 255) — JSON snapshot of light states
- `power_cut_log` (max: 255) — rolling event log

**Counter:**
- `power_blips_current_event`

**Calendar:**
- Create a local calendar called `Habit Log` — the nightly eval writes daily entries here

### Template Sensors

These are defined in `configuration.yaml` and compute derived values:

- `sensor.phone_screen_time_total` — sums all phone usage input_numbers
- `sensor.demerit_zone` — maps points to zone (green/yellow/orange/red)
- `binary_sensor.jarvis_relaxed_day` — true on weekends + holidays (drives screen limit)
- `sensor.jarvis_screen_limit_today` — returns normal or relaxed limit based on day type
- `sensor.jarvis_minutes_since_tasker_poll` — for health monitoring
- `sensor.jarvis_minutes_since_adguard_sync` — for health monitoring

Copy the `template:` section from `ha/configuration.yaml` to your own config. Adapt entity IDs to match your setup.

### View Template Sensors (Dashboard Dependencies)

The habit tracker dashboard references additional template sensors that are **created in the HA UI** (Settings > Devices & Services > Helpers > Template), not in `configuration.yaml`. These are cosmetic display wrappers — they format raw helper values for cleaner dashboard presentation (e.g., showing "42 min" instead of "42.0", or "Done ✅" instead of "on").

The dashboard won't render correctly without them. You have two options:

**Option A — Create matching view sensors** (recommended for the full experience):

| Entity ID | Wraps | Purpose |
|-----------|-------|---------|
| `binary_sensor.jarvis_gym_status_view` | `input_boolean.gym_visited_today` | Shows gym visit status with friendly label |
| `sensor.jarvis_guitar_view` | `input_number.phone_guitar_usage` | Formats guitar minutes for display |
| `binary_sensor.jarvis_phone_late_view` | `input_boolean.phone_used_late` | Shows late phone status with friendly label |
| `binary_sensor.jarvis_tasks_view` | `input_boolean.tasks_completed_today` | Shows task completion with friendly label |
| `sensor.jarvis_demerit_points_view` | `input_number.demerit_points` | Formats points as integer for gauge |
| `sensor.jarvis_exemption_days_view` | `input_number.exemption_days` | Formats exemption day count |
| `sensor.jarvis_overflow_points_view` | `input_number.overflow_points` | Formats overflow point count |
| `sensor.jarvis_youtube_view` | `input_number.phone_youtube_usage` | Formats YouTube minutes |
| `sensor.jarvis_instagram_view` | `input_number.phone_instagram_usage` | Formats Instagram minutes |
| `sensor.jarvis_netflix_view` | `input_number.phone_netflix_usage` | Formats Netflix minutes |
| `sensor.jarvis_prime_view` | `input_number.phone_prime_video_usage` | Formats Prime Video minutes |
| `sensor.jarvis_hotstar_view` | `input_number.phone_jiohotstar_usage` | Formats JioHotstar minutes |
| `sensor.jarvis_brave_view` | `input_number.phone_brave_usage` | Formats Brave minutes |
| `binary_sensor.jarvis_screen_counting_active` | `input_datetime.jarvis_last_tasker_poll` | True if Tasker polled within last 5 min |

Create each as a template helper in the HA UI. The template is typically one line — e.g., `{{ states('input_number.phone_youtube_usage') | int(0) }} min` for a usage sensor, or `{{ states('input_boolean.gym_visited_today') }}` for a binary wrapper.

**Option B — Use raw entities directly:** Edit `dashboard-habit-tracker.json` and replace each `*_view` entity ID with the underlying raw helper from the table above. The dashboard will work but show less polished values (e.g., "42.0" instead of "42 min").

### Create Gym Zone

**Settings > Areas & Zones > Zones** — create a zone centered on your gym's GPS coordinates with an appropriate radius (50-100m). Name it "Gym" so `person.<you>` transitions to state "Gym" when you arrive.

The gym entry automation also checks that you're NOT on home Wi-Fi before accepting a zone trigger — this prevents false positives from GPS drift while at home.

### Import Automations & Scripts

Two approaches:

**Option A — Adapt from YAML:**
1. Copy the `rest_command:` section from `ha/configuration.yaml` to yours
2. Create a `secrets.yaml` with your credentials (see configuration.yaml for which `!secret` keys are needed)
3. Import automations and scripts via **Settings > Automations** (create manually using the YAML as reference)

**Option B — Direct YAML edit (faster):**
1. Use the File Editor add-on to edit `automations.yaml` and `scripts.yaml` directly
2. Paste in the contents from the repo's `ha/` directory
3. Replace all placeholder webhook IDs with your own
4. Update entity IDs to match your devices
5. Restart HA to load the changes

### Accepting Tasker Webhooks

Webhook automations in HA are created with `platform: webhook` triggers. When you create the automations (bulk usage + late phone), HA registers the webhook endpoints automatically. No additional configuration needed — just make sure:
- The webhook IDs in your automations match what Tasker sends to
- `local_only: false` if Tasker will hit HA from outside your LAN

### Long-Lived Access Tokens

Home Assistant requires **long-lived access tokens** for any external service to authenticate with its API. You'll need at least one for:
- **AI agents (Jarvis, Kal-El)** — to call HA services, read states, and manage automations via MCP tools
- **Claude Code / Claude Desktop** — for the MCP server connection (see below)

Create tokens in **HA > Profile (bottom-left) > Long-Lived Access Tokens > Create Token**. Store them securely — they grant full API access to your HA instance. The token goes in your agent's workspace (e.g., `workspace-jarvis/ha-token.txt`, which is gitignored) and/or in your MCP server config.

### Claude + Home Assistant via MCP

**This is a game-changer.** Connecting Claude (via Claude Code or Claude Desktop) to Home Assistant's MCP server lets you:
- Create and edit automations conversationally
- Debug template sensors by evaluating them live
- Search entities, check states, read automation traces
- Manage helpers, scripts, and dashboards without touching YAML

Setup: Install the [Home Assistant MCP server](https://github.com/homeassistant-ai/ha-mcp) and configure Claude Code or Claude Desktop to connect to it. This community-maintained server is significantly more capable than the built-in HA MCP integration.

Once connected, you can say things like "create an automation that turns on the porch light when motion is detected after sunset" and Claude will create it directly in HA with proper triggers, conditions, and actions.

---

## Step 3: AdGuard Home

### Installation

**Recommended: Install on the Ubuntu VM** (not as an HA add-on).

Why? If AdGuard runs as an HA add-on:
- HA restarts take AdGuard down with it — DNS filtering stops temporarily
- HA updates can break the add-on
- You lose filtering during HA maintenance

On the Ubuntu VM, AdGuard runs independently. Ubuntu restarts are rare and controllable.

```bash
# On Ubuntu VM
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
```

Official docs: [adguard.com/adguard-home/getting-started](https://github.com/AdguardTeam/AdGuardHome/wiki/Getting-Started)

**Alternatives:** [Pi-hole](https://pi-hole.net/) (similar DNS filtering, different API), [NextDNS](https://nextdns.io/) (cloud-hosted, no self-hosting needed — but less control over per-client rules via API). The scripts in this repo target AdGuard's API; switching DNS providers means rewriting `script.jarvis_sync_adguard_rules`.

A reference AdGuard config is included at `adguard/AdGuardHome.yaml` — it shows the exact DNS settings, client definitions, and filtering options used in this project. Use it as a template when configuring your own instance. Tested with a Samsung Galaxy S23 as the primary tracked device.

### Client Configuration

1. Open AdGuard at `http://<ubuntu-vm-ip>:3000` (port 80 after initial setup)
2. Go to **Settings > Client Settings**
3. Add your phone as a **persistent client** — use both its LAN IP and Tailscale IP (if using Tailscale) so AdGuard matches it regardless of network path
4. The client name **must exactly match** the `client_name` variable in `script.jarvis_sync_adguard_rules` — the HA script builds rules like `||domain^$client='<your_client_name>'`

### Point Your Phone's DNS to AdGuard

**This is critical** — without this, none of the DNS blocking works.

On your Android phone:
1. **Settings > Wi-Fi > your network > Advanced > DNS** — set to the Ubuntu VM's IP
2. Or use **Private DNS** (Settings > Network > Private DNS) if your AdGuard instance supports DNS-over-TLS

All devices you want filtered need their DNS pointed to AdGuard. Only the phone client configured in AdGuard gets the habit-based filtering rules; other devices use AdGuard's default rules.

### AdGuard + HA Integration

The HA scripts push custom filtering rules to AdGuard via its REST API. Ensure the `rest_command` entries in `configuration.yaml` point to your AdGuard instance:

```yaml
# In secrets.yaml
adguard_basic_auth: "Basic <base64_encoded_user:password>"
```

The domain block lists are defined as variables inside `script.jarvis_sync_adguard_rules` in `scripts.yaml`. Edit them there to customize which sites are blocked per zone:

- **Yellow zone:** YouTube, Instagram (+ CDN domains)
- **Orange zone:** + Netflix, Prime Video (+ CDN domains)
- **Red zone:** + Hotstar, Disney+ (+ CDN domains)

The `always_allow_patterns` variable carves out exceptions (e.g., WhatsApp CDN shares a domain with Instagram's CDN).

---

## Step 4: Telegram Bots

### Creating Bots

1. Open Telegram, search for **@BotFather**
2. Send `/newbot`, follow the prompts
3. Create one bot per agent (recommended for clarity), or share bots with routing rules
4. Save each bot token — these go in your `.env` file

### Getting Chat IDs

- **Your personal chat ID:** Message [@userinfobot](https://t.me/userinfobot) — it replies with your numeric ID
- **Group chat ID:** Add your bot to a group, send a message, then check `https://api.telegram.org/bot<TOKEN>/getUpdates` — the group chat ID will be in the response (it's a negative number)

---

## Step 5: Tasker

### Install Tasker

[Tasker](https://play.google.com/store/apps/details?id=net.dinglisch.android.taskm) is a paid Android app (~$3.49). It's the most capable Android automation tool and is essential for this system.

**Alternatives:** [MacroDroid](https://play.google.com/store/apps/details?id=com.arlosoft.macrodroid) (free tier, simpler UI) or [Automate](https://play.google.com/store/apps/details?id=com.llamalab.automate) (flowchart-based). Both can send HTTP requests to HA webhooks.

**iOS:** Not yet supported by this project, but theoretically any app that can track per-app usage and send it to HA via webhooks on a regular interval should work. The HA webhook format is documented in the automations — adapt the payload to match.

### Import Profiles from TaskerNet

Pre-built Tasker profiles are available on TaskerNet:

- **[Apps Usage To HA](https://taskernet.com/shares/?user=AS35m8m2eEjbtUOEvTGebDnO%2BFqCohIxCwGpphAqCnUF7DX7GnW96cp8iXIT05ZOmbPNauUrz2uTq%2FA%3D&id=Project%3AApps+Usage+To+HA)** — polls per-app screen time every ~90 seconds, POSTs JSON to HA webhook
- **[Late Phone Usage Alert To HA](https://taskernet.com/shares/?user=AS35m8m2eEjbtUOEvTGebDnO%2BFqCohIxCwGpphAqCnUF7DX7GnW96cp8iXIT05ZOmbPNauUrz2uTq%2FA%3D&id=Project%3ALate+phone+Usage+alert+To+HA)** — detects screen-on after 23:30, fires HA webhook

### After Importing

1. Update the webhook URLs in each profile to point to your HA instance:
   - Bulk usage: `http://<ha-url>/api/webhook/<your-bulk-webhook-id>`
   - Late phone: `http://<ha-url>/api/webhook/<your-late-phone-webhook-id>`
2. Ensure Tasker has **Usage Access** permission (Settings > Apps > Special Access > Usage Access)
3. Disable battery optimization for Tasker so Android doesn't kill it in the background
4. **Lock Tasker in the recent apps tray** — on Samsung, long-press the app in recents and tap the lock icon so it's never killed. On other manufacturers, the method varies.
5. **Prevent your phone from killing Tasker:** Many Android manufacturers aggressively kill background apps to save battery. This will silently break screen time tracking. Check [dontkillmyapp.com](https://dontkillmyapp.com/) for manufacturer-specific instructions (Samsung, Xiaomi, OnePlus, Huawei, etc.) — it covers exactly which settings to change for your phone brand.

---

## Step 6: OpenClaw

### Installation

Follow the official OpenClaw documentation for installation instructions. Install OpenClaw **on the Ubuntu VM** (the same one running AdGuard), not on your local/personal machine.

> **Warning:** Do not install OpenClaw on your daily-driver PC or laptop. Beyond the always-on requirement (it handles Telegram messages 24/7), running it on your personal machine gives AI agents direct filesystem access to your local files — they can read, create, and modify files in ways you don't expect. Running it on a separate server isolates this risk. A VPS is also an option for OpenClaw itself, but you'll still need a local device for Home Assistant, AdGuard, and the hardware integrations.

### Configuration

1. Copy `.env.example` to `.env` and fill in all values
2. The `openclaw.json` in this repo is a working reference — adapt agent definitions, channel bindings, and plugin configs to your setup
3. `${VAR}` substitution reads from `.env` automatically

### Tips from Experience

- **Exec approvals:** Ensure exec approvals are provided for both Jarvis and Kal-El. Without these, the agents can't execute shell commands (like calling HA APIs via curl, managing cron jobs, or reading/writing files). This is critical for debugging and making fixes through the agents themselves.
- **Workspace files are read literally:** Agents read SOUL.md, AGENTS.md, etc. from disk at runtime. `${VAR}` substitution only works in `openclaw.json` string values — not in workspace markdown files. If an agent needs a chat ID or URL, it must be a literal value in the workspace file.
- **Cron jobs:** Jarvis uses OpenClaw's cron system for scheduled tasks (Morning Brief, Thought Catcher, Subscription Sentinel). Set these up after the agent is running and responding.
- **Memory:** Agent memory is stored in SQLite databases in the `memory/` directory. These are gitignored but persist across restarts. Back them up occasionally.

---

## Step 7: Tailscale (Optional)

[Tailscale](https://tailscale.com/) creates a secure mesh VPN between your devices. Once devices are on the same Tailscale network, you can access them from **anywhere in the world** — home, office, traveling — as if they were on your local LAN. No port forwarding, no dynamic DNS, no firewall rules. It's the easiest remote access solution to set up.

1. Install Tailscale on the Ubuntu VM and HAOS (HA has a Tailscale add-on)
2. Install Tailscale on your phone and any other device you want remote access from
3. Access HA at `https://<ha-tailscale-hostname>:8123` from anywhere
4. Set `TAILSCALE_CONTROL_UI_URL` in `.env` to the Tailscale hostname for CORS

**Alternatives:** [ZeroTier](https://www.zerotier.com/) (similar mesh VPN), [WireGuard](https://www.wireguard.com/) (lightweight, manual config), [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) (no open ports, runs through Cloudflare's network). All achieve the same goal — secure remote access without port forwarding.

---

## Step 8: Fitness Tracker (Optional)

For step tracking, set up the **Garmin Connect** integration in HA:

1. **Settings > Integrations > Add Integration > Garmin Connect**
2. Sign in with your Garmin account
3. The `sensor.garmin_connect_steps` entity will appear with your daily step count
4. The nightly eval reads this sensor for the steps habit

Any HA-integrated fitness tracker works — just update the entity ID in `script.jarvis_compute_daily_eval`.

---

## Step 9: Testing

Once everything is set up, verify each component:

| Test | How |
|------|-----|
| Tasker → HA | Open some apps, wait 90s, check `input_number.phone_youtube_usage` etc. in HA |
| Gym zone | Drive/walk to your gym, verify `person.<you>` enters the Gym zone |
| AdGuard sync | Run `script.jarvis_sync_adguard_rules` manually, verify rules appear in AdGuard UI |
| Nightly eval | Run `script.jarvis_compute_daily_eval` via HA Developer Tools (return_response=True) |
| Telegram | Send a message to your bot — should route to the correct agent |
| Power detection | (If applicable) Unplug the secondary router briefly, verify the automation fires |
| NFC tags | Scan a tag with your phone near an NFC tag, verify vacuum starts |

---

## Checklist

- [ ] Mini PC running with Proxmox (or alternative)
- [ ] Ubuntu VM with AdGuard Home + OpenClaw
- [ ] HAOS VM with Home Assistant
- [ ] Samba / SSH access from main PC to mini PC
- [ ] HA Companion App on phone
- [ ] All HA helpers created
- [ ] Gym zone configured
- [ ] Template sensors in configuration.yaml
- [ ] Automations and scripts imported
- [ ] AdGuard client configured for phone
- [ ] Phone DNS pointed to AdGuard
- [ ] Telegram bots created
- [ ] Tasker profiles imported and webhook URLs updated
- [ ] OpenClaw installed on Ubuntu VM with `.env` configured
- [ ] Exec approvals granted for Jarvis + Kal-El
- [ ] Claude connected to HA via MCP server
- [ ] Garmin Connect integration (if using steps)
- [ ] Tailscale configured (optional)
- [ ] End-to-end test of each component
