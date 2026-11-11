# Glide Codespace backend

The runtime behind the Glide console at **https://stream.amphibianclientlauncher.pages.dev**.

This repository contains only the codespace side: display, audio, Selkies streaming, the
nginx gateway, the console API, and the Minecraft launcher. The web UI is static and lives
outside this repository, so nothing here needs a token, a workflow or a local install.

## Open a session

1. **Code → Codespaces → Create codespace** on this repository.
2. Wait for the container to finish provisioning and booting (first run downloads Java,
   Selkies and Minecraft; 3–8 minutes).
3. Open the **Ports** tab, right-click **6080**, and set **Port Visibility → Public**.
   The devcontainer asks for this and `boot.sh` tries it too, so usually it is already done.
4. Copy the **6080** forwarded URL into the Glide console.

The console probes the port, reads `/glide/status`, and gives you session telemetry,
installations, the file manager and logs. The stream itself opens in its own tab from the
Session tab.

## What runs

```
.devcontainer/         ports, public visibility, setup + boot on create/start
codespace/setup.sh     apt deps, Temurin 8+21, launcher venv, Selkies, optional tools
codespace/boot.sh      Xvfb → PulseAudio → Selkies → nginx → console API → Minecraft
codespace/console.py   /glide/status, /config, /mods, /files, /log, /action, /health
codespace/nginx.conf.tpl   one public port (6080) in front of Selkies and the API
codespace/glide        CLI: up, down, restart, status, url, logs, profile, resize, save
Client/scripts/        Minecraft launcher (minecraft-launcher-lib)
Client/mods/<version>/<loader>/   mods, managed from the console or committed here
Client/versions/       known version/loader pairs
```

Runtime state lives in `~/.glide`: `session.env`, `state.env`, logs, the Minecraft data
directory and generated Selkies credentials. It survives codespace stop/start.

## Console API

All routes are served on port 6080 under `/glide/`:

| Route | Purpose |
| --- | --- |
| `GET /status` | stage, progress, stream state, log tail |
| `GET /config` / `POST /config` | session settings, versions, loaders, mods |
| `GET /mods`, `POST /mods/upload`, `POST /mods/delete` | per-installation mods |
| `GET /files`, `/files/read`, `/files/download` | file manager reads |
| `POST /files/save`, `/files/upload`, `/files/mkdir`, `/files/delete` | file manager writes |
| `GET /log?name=…` | launcher, java, boot, selkies, nginx, console, xvfb |
| `POST /action` | restart game/stream/session, stop |

Set `GLIDE_WEB_KEY` in `~/.glide/session.env` to require `X-Glide-Key` on writes.

## Notes

- Versions, loaders and heap are chosen in the console (Installations); mods upload there
  or go into `Client/mods/<version>/<loader>/`.
- The first launch of a version downloads its client and loader; later boots are faster.
- Codespaces have no GPU: use the low profile, 854×480, and optimisation mods. A 4-core
  codespace is a meaningful step up from 2 cores.
- Codespaces are for developing and testing the project. A public desktop stream is not a
  loophole around that; keep sessions short and run them on your own account.
