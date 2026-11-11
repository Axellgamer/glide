# Glide Codespace

STREAMED MINECRAFT CLIENT OUT OF YOUR OWN GITHUB CODESPACES! NO FRONTEND SINCE GITHUB CODESPACE IS THE FRONTEND AHAHAHAHA

## Use it

1. **Fork** this repository to your own account.
2. On your fork: **Code → Codespaces → Create codespace on main**.
3. Wait for the devcontainer. It installs Java, Selkies, nginx and the launcher, then boots
   the display, stream and Minecraft.
4. A terminal opens the **Glide menu**. If it is not there, run the task
   **Glide: Menu**.
5. From the menu:
   - **Switch Installation** — VERSION & LOADER & HEAP
   - **Start / Restart session**, **Restart game**, **Restart stream**, **Stop**
   - **Stream Profile** — LOW / MEDIUM / HIGH
   - **Show Status**, **Tail Log**, **Edit Session**
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

The menu is the interface; the CLI underneath is available if you prefer the terminal.

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

## Tips

- Codespaces have no GPU, low profile is strongly recommended. 
- Using a 4 core codespace will double the performance.
- Keep port 6080 private and keep sessions short to lower the risk of your account getting suspended.
- If you are out of free codespace usage, simply delete your github account and make a new one.