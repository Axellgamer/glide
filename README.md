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

## How the entire thing works

```
YOUR BROWSER (signed in to GitHub)
  └─ https://<codespace>-6080.app.github.dev        private forwarded port
       └─ nginx :6080                               injects the Selkies login
            ├─ /       → Selkies :8080  →  Xvfb :99  →  Minecraft window
            └─ /healthz → 200 for boot checks

GITHUB.DEV (VS Code in the codespace)
  ├─ Explorer        the file manager (Client/, ~/.glide/)
  ├─ terminal menu   codespace/menu.sh
  └─ tasks           .vscode/tasks.json
```

### 1. Provision and boot

- `onCreateCommand` runs `codespace/setup.sh`: apt packages, Temurin Java 8 and 21,
  a Python venv with `minecraft-launcher-lib`, Selkies (deb, AppImage fallback), the
  optional JVM probe agent, and a `glide` symlink in `~/.local/bin`.
- `postStartCommand` runs `codespace/boot.sh --detach`:
  1. starts **Xvfb** on `:99` at the configured resolution;
  2. starts **PulseAudio** with a virtual sink so game audio can be captured;
  3. starts **Selkies** on `127.0.0.1:8080` with H.264 and a generated password;
  4. starts **nginx** on `6080`, the only forwarded port, and injects the Selkies
     basic-auth header so the browser never shows a login prompt;
  5. copies mods/settings for the selected version+loader and launches Minecraft.
- `postAttachCommand` opens the **Glide menu** in the integrated terminal. The tasks in
  `.vscode/tasks.json` expose the same actions from the Command Palette.

### 2. Version, loader and mods

- **Switch installation** in the menu/task prompts for a Minecraft version, a loader
  (`fabric`, `vanilla`, `forge`, `quilt`, `neoforge`, `legacy-fabric`, `legacy-forge`) and
  a heap size. `glide install` writes them to the profile and restarts the game.
- `boot.sh` picks Java 8 for versions older than 1.17 and Java 21 otherwise, clears the
  game's `mods/` directory, copies `Client/mods/<version>/<loader>/`, and runs
  `Client/scripts/glide_launch.py`.
- The launcher uses `minecraft-launcher-lib` to install the requested version and loader,
  extract native libraries, build the JVM command and start the game. It restarts on a
  crash up to the configured limit.
- **Mods** are plain `.jar` files in `Client/mods/<version>/<loader>/`. Drop them there in
  the Explorer; they apply on the next game restart. Vanilla loads none.
- **Files:** the Explorer is the file manager. Worlds and options live in
  `~/.glide/minecraft/`; `glide save` copies worlds/settings back into `Client/`.

### 3. The stream

- The browser opens the private 6080 URL in a normal tab. GitHub authenticates it with
  your session, nginx proxies to Selkies, and Selkies captures the Xvfb screen, encodes
  H.264 and sends it over one WebSocket (`/api/websockets`). Keyboard/mouse/gamepad events
  travel back the same socket.
- Nothing is embedded and no port is public. Do not share the URL: it is your session.
- Browser fullscreen (F11 or the Selkies fullscreen button) needs one keypress; browsers
  do not allow a page to fullscreen itself in a new tab.

### 4. Settings that follow you

Two layers keep version/loader/heap/stream/account settings:

1. **The fork** — `.glide/profile.env` is committed to your fork. A new codespace on the
   same account clones it and boots with your last settings automatically.
2. **The portable store** — a passphrase-keyed Cloudflare KV entry (`glide link`). The key
   is `sha256("glide-profile-v1:" + passphrase)`; the passphrase is never stored anywhere.
   This is what survives **switching GitHub accounts**: on the new account/codespace, run
   the **Glide: Link profile (switch accounts)** task (or menu `l`, or `glide link`) with
   the same passphrase. It pulls the settings, applies them, and commits them into the
   new fork.

On boot the portable store is checked first, then the fork. Every settings change writes
both. `glide sync` forces a save; `glide unlink` removes the local key (the fork copy
remains). Only non-secret settings are stored: version, loader, heap, resolution,
fps/bitrate/encoder, dashboard/audio, auth mode, username and the public Microsoft client
ID. Selkies passwords, Microsoft tokens, logs and world data are never uploaded.

### 5. Nothing else is involved

No web frontend, no GitHub token, no GitHub Actions, no public port, no tunnel, no
container outside the codespace, and no local install on the user's computer. The only
external service is the small settings KV store for cross-account profiles.



### 6. Game settings

The small Minecraft settings also follow you, separately from the profile:

- Included in a `.tar.gz`: `options.txt`, `optionsof.txt`, `optionsshaders.txt`,
  `servers.dat` and `config/`. **Not** included: worlds, resource packs, shader packs,
  screenshots, logs or mods (those are repo/workspace files).
- Stored in the same passphrase-keyed Cloudflare KV entry under `/v1/game/<key>`.
- Pulled and extracted before every game launch; pushed after **Stop**, before a game
  restart, and by `glide sync` / `glide save`.
- Requires `glide link` (the same passphrase). Without linking, game settings stay in the
  codespace only.
- They are **not** committed to the fork, so server addresses and mod configs never land
  in a public repository.

So after switching a GitHub account: create the codespace, run **Glide: Link profile**
with the same passphrase, and both the profile and the game settings come back. Restart
the game once if it was already running when you linked.

