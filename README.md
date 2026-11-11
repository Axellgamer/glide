# Glide Codespace

Streamed Minecraft Client out of **your own** GitHub Codespace. The frontend is
**github.dev** itself: the Explorer is the file manager, the task menu selects version and
loader, and the Ports panel opens the stream. There is no web frontend to host, no token,
no GitHub Actions, and no public port.

## Use it

1. **Fork** this repository to your own account.
2. On your fork: **Code → Codespaces → Create codespace on main**.
3. Wait for the devcontainer. It installs Java, Selkies, nginx and the launcher, then boots
   the display, stream and Minecraft (3–8 minutes on the first run).
4. A terminal opens the **Glide menu**. If it is not there, run the task
   **Glide: Menu** (Ctrl/Cmd+Shift+B).
5. From the menu:
   - **Switch installation** — Minecraft version, loader and heap
   - **Start / restart session**, **Restart game**, **Restart stream**, **Stop**
   - **Stream profile** — low / medium / high
   - **Show status**, **Tail a log**, **Edit session.env**
6. Open the stream: **Ports** tab → **6080** → open the forwarded URL. Keep the port
   **Private**; the URL works while you are signed in. Do not make it public and do not
   share it.

The Explorer on the left is the file manager:

- repository files, launcher and runtime: the repo root
- mods: `Client/mods/<version>/<loader>/`
- resource packs: `Client/<version>/resourcepacks/`
- Minecraft data (worlds, options): `~/.glide/minecraft/`
- logs: `~/.glide/logs/`

## Commands

The menu is the normal interface; the CLI underneath is available if you prefer the
terminal.

| Command | What it does |
| --- | --- |
| `glide up` | Start display, stream and Minecraft in the background |
| `glide down` | Stop everything |
| `glide restart` | Restart everything |
| `glide restart-game` | Relaunch Minecraft only |
| `glide restart-stream` | Restart Selkies, keep the game running |
| `glide install 1.21.5 fabric 4G` | Switch version / loader / heap and restart the game |
| `glide status` | State, URL and process summary |
| `glide url` | The private 6080 URL |
| `glide logs minecraft` | Tail a log (`game`, `boot`, `selkies`, `nginx`, `setup`) |
| `glide profile low` | 30 fps / 2.5 Mbps (`medium`, `high`) |
| `glide resize 1280x720` | Restart at a resolution |
| `glide dashboard on` | Show/hide the Selkies sidebar |
| `glide save` | Copy worlds/settings back into `Client/` |
| `glide env` | Edit `~/.glide/session.env` |

## What runs

```
.devcontainer/         provisioning, private port 6080, boot on start, menu on attach
.vscode/tasks.json     Glide tasks (menu, start/stop, installation, logs)
codespace/setup.sh     apt deps, Temurin 8+21, launcher venv, Selkies
codespace/boot.sh      Xvfb → PulseAudio → Selkies → nginx → Minecraft
codespace/menu.sh      interactive launcher for github.dev terminals
codespace/glide        CLI used by the menu and tasks
codespace/nginx.conf.tpl   private 6080 → Selkies 8080 with injected basic auth
Client/scripts/        Minecraft launcher (minecraft-launcher-lib)
Client/mods/<version>/<loader>/   mods
```

State lives in `~/.glide` (`session.env`, `state.env`, logs, Minecraft data, generated
Selkies credentials) and survives codespace stop/start.

## Notes

- The stream opens in its own browser tab from the 6080 URL. Browser fullscreen (F11 or the
  Selkies fullscreen button) is one keypress; the browser will not allow it automatically.
- Codespaces have no GPU: use the low profile, 854×480 and optimisation mods. 4 cores is a
  meaningful step up from 2.
- Keep port 6080 private and keep sessions short. Codespaces are for developing and
  testing the project; a private desktop stream is not a loophole around that, and a public
  or shared one is worse.
