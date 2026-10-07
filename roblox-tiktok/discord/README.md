# Diamond Rush Discord server setup

This tool builds the whole Diamond Rush Discord server for you in about a
minute. You make an empty server and a free Discord bot first (about 3
minutes), then run the tool once.

## What you get

| Category | Channels |
| --- | --- |
| START HERE | `#rules` (read-only, pinned rules), `#announcements` (read-only) |
| DOWNLOADS | `#download-connector` (read-only, pinned download link and setup steps) |
| COMMUNITY | `#general` (5 s slowmode), `#clips` (30 s slowmode), `Lounge` voice |
| SUPPORT | `#help` (30 s slowmode), `#bug-reports` (**1 hour slowmode**, pinned report template) |
| STAFF | `#mod-log` (only Moderators can see it; AutoMod alerts go here) |

**Safety**

- **Verification level High:** a verified email and 10 minutes on the server before chatting.
- **Media scanning:** explicit images are scanned from everyone.
- **AutoMod blocks:**
  - Discord's flagged-word lists
  - mention spam (5 or more) and mention raids
  - suspected spam
  - server invites and "free Nitro / free Robux" scams

  Alerts go to `#mod-log`.
- **Community mode:** new members must accept the rules.
- **Members can't** ping @everyone or create invites.
- **Roles:** a **Moderator** role (kick, ban, timeout, delete messages) and a **Streamer** role.
- Notifications default to @mentions only.

## 1. Make an empty server (1 minute)

1. In Discord press **+** (Add a Server) → **Create My Own** → **For a club or community**.
2. Name it, for example "Diamond Rush", and press **Create**.
3. Turn on Developer Mode:
   - Open **User Settings → Advanced → Developer Mode**.
   - Right-click the new server's icon → **Copy Server ID**.
   - Keep the ID for step 3.

## 2. Make the setup bot (2 minutes)

1. Go to <https://discord.com/developers/applications> and press **New Application**.
   - Name it "Diamond Rush Setup", accept the terms and press **Create**.
2. Open **Bot** on the left:
   - Press **Reset Token**, then **Copy**.
   - Keep the token secret: it controls the bot. Don't paste it into chats or share screenshots of it.
3. That's all: you don't need to tick anything else on that site. The tool adds the bot to your server for you in step 3: it opens the bot's invite link for your server, and you click **Authorize**.

## 3. Run the tool

You need Node.js (the same one the TikTok connector uses).

- **Windows:** double-click **Setup Discord.bat**.
- **Anything else:** run `node setup.mjs` in this folder.

It asks for:

1. **The server ID** from step 1.
2. **The bot token** from step 2. It's hidden as you paste it, is used only for this run, and is never saved.
3. **The connector download link.** Press Enter to add it later.

Want to see what it will do first? `node setup.mjs --dry-run` prints every step without touching Discord.

Running it again is safe for channels and roles (it updates them instead of making copies), but it posts the pinned messages again.

## 4. Finish by hand (2 minutes)

1. **Server Settings → Roles → Moderator**: add yourself and anyone you trust.
2. **Server Settings → Safety Setup**: turn on **Require 2FA for moderator actions**.
   - This needs 2FA on your own account first.
3. **Make a permanent invite** for Roblox:
   - Right-click `#rules` → **Invite People** → **Edit invite link**.
   - Set Expire after **Never**, then copy the link.
   - Put it on your Roblox game page under **Social Links → Discord**.
4. **Remove the setup bot**: right-click it in the member list → **Kick**. It isn't needed any more, and it should not keep Administrator.
5. **If you skipped the download link:** post it in `#download-connector`. Discord's free upload limit is 10 MB, so post a link (for example to the GitHub release) rather than the file.

## Changing the layout

Everything the tool creates is described in `plan.mjs`: channel names, slowmodes, rules text, the download post, the bug template and the AutoMod word lists. Edit it and run the tool again. `npm test` checks the plan (the one-hour bug cooldown, read-only channels, hidden staff channel and safety settings).
