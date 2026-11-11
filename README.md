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

Explorer is treated as file manager:

- Root
- Mods: `Client/mods/<version>/<loader>/`
- Resource Packs: `Client/<version>/resourcepacks/`
- Minecraft Data: `~/.glide/minecraft/`
- Logs: `~/.glide/logs/`

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

## Tips

- Codespaces have no GPU, low profile is strongly recommended. 
- Using a 4 core codespace will double the performance.
- Keep port 6080 private and keep sessions short to lower the risk of your account getting suspended.
- If you are out of free codespace usage, simply delete your github account and make a new one.

## How the entire thing works

```
YOUR BROWSER
  └─ https://Codespace-6080.app.github.dev          
       └─ nginx :6080                               
            ├─ /       → Selkies :8080  →  Xvfb :99  →  Minecraft window
            └─ /healthz → 200 for boot checks
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

-  A passphrase-keyed Cloudflare KV entry (`glide link`). The key
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

So after switching a GitHub account: Create the codespace, run **Glide: Link profile**
with the same passphrase, and both the profile and the game settings come back. Restart
the game once if it was already running when you linked.


### 8. Worlds, mods and packs in the portable store

The larger data now follows the same sync key:

- Archive contents: `saves/` (worlds), `mods/`, `resourcepacks/`, `shaderpacks/`.
  Together with the game-settings archive (options, servers, config) this covers the whole
  gameplay state except versions/libraries/assets/logs.
- Pulled on a full session start (`glide up` / boot all) and when linking a key.
- Pushed on **Stop**, before a restart is not needed (it uses the live files), and by
  `glide sync` / `glide save`.
- Requires `glide link`; unlinked data stays in the codespace.
- Stop the game before linking, otherwise link refuses so worlds/mods cannot be
  overwritten.
- Limits: the Worker chunks archives at 24 MB with a **40 MB per-archive cap**. Cloudflare
  KV gives 1 GB total and about 1,000 writes/day on the free plan, so ~100 users fit when
  worlds are small; large worlds/modpacks need R2 (enable it in the Cloudflare dashboard)
  or a paid limit.
- Nothing is committed to the fork and no GitHub token is used.


### 9. Correction: the fork and passphrase text above is obsolete

Current behaviour: no settings or data are written to the fork, and there is no
passphrase. `glide link` generates (or accepts) a random 64-character sync key and the
Cloudflare KV entry stores the profile, game settings and the chunked worlds/mods/packs
archive. Use `glide key` to print the key and `glide link <key>` on another account.

