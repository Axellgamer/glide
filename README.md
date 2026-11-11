# Glide — Minecraft streamed out of a GitHub Codespace

Glide runs a real Minecraft Java client on a virtual desktop **inside your own GitHub
Codespace** and streams the window to a browser over WebSocket (Selkies + H.264).

This build replaces the old GitHub Actions backend:

| Before | Now |
| --- | --- |
| You pasted a **GitHub token** into the page | The page never asks for a token |
| The page dispatched **Actions workflows** | No workflows, no `workflow_dispatch`, no runners |
| The client ran on an Actions runner for 6 hours | The client runs in the **codespace you already own** |
| Stream URL was scraped out of workflow logs | You paste the **codespace forwarded URL** |
| Cloudflare quick tunnel | GitHub port forwarding, one port |

The result is a smaller system: one VM, one port, one URL. The browser page is a
console — it stores nothing except that URL (and an optional action key).

---

## Quick start

### 1. Start a codespace

Open this repository in a codespace. `.devcontainer/devcontainer.json` provisions the
container on first create (Xvfb, PulseAudio, nginx, Selkies, Java 21/8, the Python
launcher) and boots the session on every start.

If you prefer doing it by hand:

```bash
bash codespace/setup.sh        # once, takes a few minutes
bash codespace/boot.sh --detach
```

### 2. Keep port 6080 private

Codespaces forwarded ports are private by default. Keep them that way. The console opens
the stream in its own tab while you are signed in to GitHub, so nothing has to be made
public. If it was made public before, flip it back in the **Ports** tab (or run the old
`gh codespace ports visibility` command with `private`).

```bash
```

`glide up` tries this automatically when `gh` is authenticated.

### 3. Get the URL

```bash
glide url
# https://<codespace-name>-6080.app.github.dev
```

### 4. Open the console

The console is already deployed at
**https://stream.amphibianclientlauncher.pages.dev** (a `stream` preview branch of the
`amphibianclientlauncher` Pages project). Paste the codespace URL and press **Connect**.

Nothing is installed locally: the codespace provisions and boots itself, and the page is
a static file. Use the **Open stream** button on Session (or the topbar icon); it opens the
private 6080 URL in a tab, authenticated by your GitHub session.

You can deep-link a session:
`https://stream.amphibianclientlauncher.pages.dev/?connect=https://<codespace>-6080.app.github.dev`

<details>
<summary>Running or redeploying the console yourself</summary>

```bash
python3 serve.py        # http://localhost:5173
export CLOUDFLARE_ACCOUNT_ID=<your account id>
npx wrangler pages deploy Html --project-name amphibianclientlauncher --branch stream
```

</details>

---

## The console

Six tabs, each with one job:

| Tab | What it does |
| --- | --- |
| **Connect** | Paste the codespace URL; probes the port, console API, stream gateway and game |
| **Session** | Session telemetry, quick actions, and the full-height log console (all sources). The stream opens in its own tab |
| **Installations** | Version + loader + heap, and drag-and-drop mod upload for that installation |
| **File manager** | Browse/upload/download/edit/delete in the repository or `~/.glide/minecraft` |
| **Settings** | Stream quality, resolution/encoder/audio/dashboard, Microsoft or offline account, browser preferences |
| **Help** | Four GUI steps, then troubleshooting |

No tab asks for a terminal command, a token, or a local download. Everything that changes
the codespace goes through the console API (`/glide/…`) on port 6080. The console checks the port, the console API, the stream
gateway and the game, then embeds the stream.

Typical boot: display ~2 s, Selkies ~5 s, Minecraft download on first launch 1–3 min.
`glide status` and the **Session** view show each step.

---

## What lives where

```
.
├─ Html/                  static console UI (no build step, no token)
│  ├─ index.html
│  ├─ app.css
│  ├─ app.js
│  └─ favicon.svg
├─ codespace/
│  ├─ setup.sh            one-time provisioner (apt, Selkies, Java, venv)
│  ├─ boot.sh             display → audio → Selkies → nginx → console → game
│  ├─ stop.sh             stops everything cleanly
│  ├─ console.py          tiny status/log/action API on 127.0.0.1:6081
│  ├─ nginx.conf.tpl      renders the 6080 gateway (stream + /glide/ API)
│  ├─ lib.sh              shared paths, defaults, state file
│  └─ glide               the CLI you actually use
├─ Client/
│  ├─ scripts/glide_launch.py      Minecraft launcher (minecraft-launcher-lib)
│  ├─ glide-gl-bridge/             optional Rust GL/Vulkan bridge
│  ├─ glide-runtime-agent/         optional JVM probe agent
│  ├─ mods/<version>/<loader>/     mods, per Minecraft version and loader
│  ├─ <version>/resourcepacks/     resource packs
│  ├─ <version>/datapacks/<loader>/
│  ├─ <version>/worlds/            worlds copied in at boot
│  ├─ <version>/settings/<loader>/ options.txt, servers.dat, config/, …
│  ├─ Shaders/                     shader packs (zips)
│  └─ skins/                       one 64×64 skin PNG (Microsoft auth only)
├─ .devcontainer/         codespace definition, port 6080 private
├─ serve.py               local static server for Html/
└─ README.md
```

Runtime state lives outside the repo, in `~/.glide`:

```
~/.glide/
├─ session.env     version, loader, heap, resolution, fps, bitrate, dashboard…
├─ state.env       stage/detail written by boot.sh, read by console.py
├─ minecraft/      the actual .minecraft directory
├─ logs/           boot, minecraft, selkies, nginx, console, setup, actions
├─ run/            pid files
├─ nginx/          rendered config, temp dirs
├─ jre/8, jre/21   Temurin runtimes
└─ venv/           minecraft-launcher-lib
```

---

## Commands

| Command | What it does |
| --- | --- |
| `glide up` | Start display, audio, stream, gateway, console and Minecraft (background) |
| `glide up --wait` | Same, but keep the boot log in the foreground |
| `glide down [--save]` | Stop the game and every streaming process |
| `glide restart` | Full restart (needed when the resolution changes) |
| `glide restart-game` | Relaunch just Minecraft, keep the stream alive |
| `glide restart-stream` | Restart Selkies, keep the game running |
| `glide status [--json]` | Human summary or raw JSON from the console API |
| `glide url` | Print the port 6080 URL (adds `#key=…` if configured) |
| `glide logs [name]` | Tail `boot`, `minecraft`, `game` (Java), `selkies`, `nginx`, `console`, `xvfb`, `setup`, `actions` |
| `glide profile low\|medium\|high` | 30 fps/2.5 Mbps, 60/6, 60/12 — restarts the stream only |
| `glide resize 1280x720` | Store a new resolution and restart the session |
| `glide dashboard on\|off` | Show/hide the Selkies sidebar inside the video |
| `glide save` | Copy worlds/settings back into `Client/<version>/` for committing |
| `glide env` | Edit `~/.glide/session.env` |
| `glide setup [--force]` | Re-run provisioning |

`glide` is symlinked into `~/.local/bin` by setup; `./codespace/glide` always works.

---

## How it fits together

```
browser (Html/app.js)
   │  https://<name>-6080.app.github.dev
   ▼
nginx :6080 ──► Selkies :8080 (Xvfb :99, H.264 over /api/websockets)
   │                 ▲
   └─ /glide/ ──► console API :6081 ──► glide CLI (restart / stop / profile)
                       │
                       └─ reads ~/.glide/state.env, logs, session.env
Minecraft JVM ── draws on :99, audio through PulseAudio virtual sink
```

* **One private port.** nginx injects the Selkies HTTP basic-auth header, so opening
  `https://<codespace>-6080.app.github.dev` in a signed-in tab needs no prompt. Keep the
  port private; do not turn it into a public service.
  Opening the console with `?connect=<url>` connects immediately, which is handy for
  bookmarks and kiosks.
* **Selkies is framed on purpose.** Boot sets `SELKIES_FRAME_ANCESTORS=*` and
  `SELKIES_ALLOWED_ORIGINS=*`; without those the dashboard refuses to be embedded.
* **Adaptive boot.** Every step is idempotent, so `boot.sh` can be re-run at any time
  and only starts what is missing.
* **Status is real.** `glide_launch.py` prints `GLIDE_STAGE=…` markers; the console API
  reads them from the log and turns them into progress. Nothing is faked in the UI.

### The console API

`console.py` binds `127.0.0.1:6081` (never public) and is reachable at `/glide/`:

| Route | Purpose |
| --- | --- |
| `GET /glide/status` | stage, progress, MC version/loader, stream settings, uptime, log tail |
| `GET /glide/config` | session values, available versions/loaders/encoders, current mods |
| `POST /glide/config` | `{"values":{…},"restart":"stream\|game\|session\|none"}` |
| `GET /glide/mods` / `POST /glide/mods/upload` / `POST /glide/mods/delete` | per-installation mod management |
| `GET /glide/files`, `/files/read`, `/files/download` | file manager reads |
| `POST /glide/files/save`, `/files/upload`, `/files/mkdir`, `/files/delete` | file manager writes |
| `GET /glide/log?name=minecraft&tail=400` | plain text log |
| `POST /glide/action` | `{"action":"restart-game"}` etc., allow-listed |
| `GET /glide/health` | `ok` |

CORS is `*` so the static page can read it from any origin. Actions are open by
default because the codespace URL is the secret; set `GLIDE_WEB_KEY` in
`~/.glide/session.env` to require `X-Glide-Key` on actions (then use
`glide url`, which appends `#key=…`).

---

## Configuration

`~/.glide/session.env` (create or edit with `glide env`):

```ini
GLIDE_MINECRAFT_VERSION=1.21.5
GLIDE_MINECRAFT_LOADER=fabric        # vanilla|fabric|legacy-fabric|forge|legacy-forge|quilt|neoforge
GLIDE_MINECRAFT_XMX=4G
GLIDE_AUTH_MODE=offline              # offline | microsoft
GLIDE_OFFLINE_USERNAME=GlidePlayer
GLIDE_RESOLUTION=1280x720            # applies after glide restart
GLIDE_FPS=60
GLIDE_BITRATE=6000                   # kbps
GLIDE_ENCODER=h264enc                # h264enc|h265enc|vp8enc|vp9enc|av1enc|h264enc-striped|jpeg
GLIDE_DASHBOARD=true                 # Selkies sidebar inside the stream
GLIDE_AUDIO=true
GLIDE_MAX_RESTARTS=3
GLIDE_WEB_KEY=                       # optional action key
```

### Microsoft accounts

`GLIDE_AUTH_MODE=microsoft` uses a device-code login. Put your own Azure public client
ID in `GLIDE_MICROSOFT_CLIENT_ID` (in `session.env`), run `glide up`, then follow the
`MICROSOFT_LOGIN_URL` / `MICROSOFT_LOGIN_CODE` lines in `glide logs minecraft`.

### Mods, packs, worlds, shaders

Everything is copied into the codespace at boot, from the repo layout:

* mods → `Client/mods/<version>/<loader>/*.jar` (upload from **Installations** or the File manager)
* resource packs → `Client/<version>/resourcepacks/`
* datapacks → `Client/<version>/datapacks/<loader>/`
* worlds → `Client/<version>/worlds/` (copied to `~/.glide/minecraft/saves/`)
* shader packs → `Client/Shaders/*.zip`
* settings → `Client/<version>/settings/<loader>/`

Saves made inside a codespace persist with the codespace. `glide save` copies them
back into `Client/` so you can commit them.

---

## Performance (read this before complaining)

A default codespace is **2 vCPU / 8 GB with no GPU**, and Mesa falls back to
`llvmpipe`. Minecraft will run, at 20–40 fps at 854×480 with optimisation mods.
Things that actually help, in order:

1. **Sodium + Lithium + Ferrite Core + ImmediatelyFast** (or the equivalent for your
   version) in `Client/mods/<version>/fabric/`.
2. `glide profile low` and `glide resize 854x480`.
3. A 4-core codespace (`hostRequirements.cpus` in `.devcontainer/devcontainer.json`).
4. `GLIDE_MINECRAFT_XMX=2G`–`3G`; more heap does not help a software renderer.

The Rust GL bridge (`glide-gl-bridge`) is optional here. Set `GLIDE_USE_BRIDGE=1` and
build it with `GLIDE_BUILD_BRIDGE=1 bash codespace/setup.sh` before enabling it.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Probe says *"port asks for GitHub sign-in"* | Correct: the port is private. Click **Open in a new tab** while signed in to GitHub; do not make it public. |
| Probe says *"no answer"* | Codespace stopped, or port 6080 not forwarded. `glide up`. |
| Video loads, stays black | Minecraft still downloading. `glide logs minecraft`, wait for `GLIDE_READY=true`. |
| `502` from the gateway | Selkies died: `glide logs selkies`, then `glide restart-stream`. |
| Keys do nothing | Click once inside the video (pointer lock), or open the Selkies sidebar and use *capture keyboard*. |
| `setup.stamp` missing on boot | `bash codespace/setup.sh` (first create may have failed; see `~/.glide/logs/setup.log`). |
| Audio silent | Browser autoplay policy: click the stream once. `glide logs boot` shows the PulseAudio sink. |
| Everything is slow | See performance above. |
| The video panel stays blank but the tab version works | A framing policy blocked the iframe. Use the ↗ button in the stage bar to open the stream in its own tab; the rest of the console keeps working. |

Logs are also in the UI: **Logs → minecraft launcher | minecraft java | selkies | nginx | boot**.

---

## A reality check (read this before running it)

Moving off Actions removes the token and the billing abuse, but it does **not** make this
policy-safe. GitHub's terms for Codespaces prohibit activity unrelated to developing or
testing the project, and using Codespaces to host an application or service. "I am
technically developing" is not a defence against either clause.

The pattern that gets noticed is not the word "Minecraft"; it is a **shared or public port serving
an interactive desktop for hours**. Keep these habits:

- every user runs their own codespace under their own account (this repo never runs
  anything under a shared token, so there is no central thing to ban)
- prefer `glide down` + `gh codespace stop -c "$CODESPACE_NAME"` as soon as you stop
  playing; long unattended sessions are both a policy and a core-hours problem
- never publish one codespace URL for other people to use; that is hosting a service
- always leave port 6080 private and use **Open stream** / **Open in a new tab**; making
  the port public turns a personal session into a hosted service

Nothing here is legal advice, and no amount of UI polish changes the terms. Use it on
your own account, at your own risk.

## Credits

* Original Glide project: [PierrotTheFreak/Glide-u2-beta](https://github.com/PierrotTheFreak/Glide-u2-beta)
* Streaming: [Selkies](https://github.com/selkies-project/selkies) (`pixelflux` + `pcmflux`)
* Launcher logic: [minecraft-launcher-lib](https://github.com/JakobDev/minecraft-launcher-lib)
* Everything else: shell, Python stdlib and one static page.

Not affiliated with Mojang, Microsoft or GitHub.
