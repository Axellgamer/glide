# Glide Codespace

Run the Glide console and a streamed Minecraft client from **your own** GitHub Codespace.
No token, no GitHub Actions, no public port, nothing installed on your computer.

## Fork, then open your own codespace

1. **Fork this repository** to your own GitHub account (top-right **Fork**).
2. On **your fork**: **Code → Codespaces → Create codespace on main**.
3. Wait. The devcontainer provisions Java, Selkies, nginx and the launcher, then boots the
   session. First run takes 3–8 minutes (it downloads Minecraft).
4. Open the **Ports** tab. Find **6080**. Leave its visibility **Private**. Click the
   globe / *Open in browser* icon to open it.
5. Add `/console/` to the URL:

   ```
   https://<your-codespace>-6080.app.github.dev/console/
   ```

   That is the console. It talks to `/glide/` on the same origin, so it works while the
   port stays private. The stream opens in its own tab from the Session view.
6. Bookmark it. When you are done: **Stop session** in the console, then stop the
   codespace from the GitHub Codespaces page.

Do **not** make port 6080 public. Do not share your codespace URL; it is your session.

> The hosted console at `stream.amphibianclientlauncher.pages.dev` is an optional launcher
> for public ports. With a private port it cannot read the API, so use the `/console/`
> URL from step 5 instead.

## What runs

```
.devcontainer/         provisions and boots on create/start
codespace/setup.sh     apt deps, Temurin 8+21, launcher venv, Selkies
codespace/boot.sh      Xvfb → PulseAudio → Selkies → nginx → console → Minecraft
codespace/console.py   /glide/status, /config, /mods, /files, /log, /action
codespace/web/         the console served at /console/
codespace/nginx.conf.tpl   one private port: console, API and stream
codespace/glide        CLI: up, down, restart, status, url, logs, profile, resize, save
Client/scripts/        Minecraft launcher (minecraft-launcher-lib)
Client/mods/<version>/<loader>/   mods uploaded from Installations or committed here
```

State lives in `~/.glide` (session settings, logs, Minecraft data, generated Selkies
credentials) and survives codespace stop/start.

## Settings and features

Everything is in the console:

- **Session** — telemetry, restart game/stream/session, stop, and the log console
- **Installations** — version, loader, heap, drag-and-drop mod upload
- **Files** — browse/upload/download/edit the repository and `~/.glide/minecraft`
- **Settings** — stream quality, resolution, encoder, audio, account, browser prefs
- **Help** — troubleshooting

All API calls stay on port 6080 and are same-origin with the console. Writes can be
protected with `GLIDE_WEB_KEY` in `~/.glide/session.env`.

## Notes

- Codespaces have no GPU: use the low profile, 854×480 and optimisation mods. 4 cores is a
  meaningful step up from 2.
- Keep sessions short. Codespaces are for developing and testing the project; a private
  desktop stream is not a loophole around that, and a public or shared one is worse.
