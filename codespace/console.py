#!/usr/bin/env python3
"""Glide Codespace console API.

A tiny, dependency-free HTTP daemon that the Glide web UI talks to. It lives
behind the same nginx port as the stream (under /glide/) so a single codespace
URL is all the UI needs.

    GET  /status                     session state as JSON
    GET  /config                     session config + versions + mods
    POST /config                     {"values": {...}, "restart": "stream|game|session|none"}
    GET  /mods?version=&loader=      installed mods
    POST /mods/upload?version=&loader=&name=     raw file body
    POST /mods/delete                {"version","loader","name"}
    GET  /files?root=&path=          directory listing
    GET  /files/read?root=&path=     text or base64 preview
    GET  /files/download?root=&path= raw download
    POST /files/save                 {"root","path","text"}
    POST /files/upload?root=&path=&name=         raw file body
    POST /files/mkdir                {"root","path"}
    POST /files/delete               {"root","path"}
    GET  /log?name=minecraft&tail=200
    GET  /health                     "ok"
    POST /action {"action": "...", "args": {...}}

Bind address is loopback only: nginx is the only intended client.
"""

from __future__ import annotations

import base64
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, urlparse

APP_NAME = "glide-console"
APP_VERSION = "3.1"

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
GLIDE_CLI = HERE / "glide"

HOME = Path(os.environ.get("GLIDE_HOME", Path.home() / ".glide"))
LOGS = HOME / "logs"
RUN = HOME / "run"
STATE_FILE = HOME / "state.env"
SESSION_ENV = HOME / "session.env"
MC_LOG = LOGS / "minecraft.log"
NGINX_ERROR_LOG = HOME / "nginx" / "logs" / "error.log"
MINECRAFT_DIR = HOME / "minecraft"
REPO_MODS = ROOT / "Client" / "mods"
VERSIONS_FILE = ROOT / "Client" / "versions" / "versions.json"

PORT = int(os.environ.get("GLIDE_CONSOLE_PORT", "6081"))
PROXY_PORT = int(os.environ.get("GLIDE_PROXY_PORT", "6080"))
SELKIES_PORT = int(os.environ.get("GLIDE_SELKIES_PORT", "8080"))
WEB_KEY = os.environ.get("GLIDE_WEB_KEY", "").strip()

MAX_JSON = 256 * 1024
MAX_UPLOAD = 256 * 1024 * 1024
MAX_PREVIEW = 1024 * 1024
CHUNK = 256 * 1024

LOG_FILES = {
    "boot": LOGS / "boot.log",
    "minecraft": MC_LOG,
    "game": Path("/tmp/glide-minecraft.log"),
    "selkies": LOGS / "selkies.log",
    "console": LOGS / "console.log",
    "xvfb": LOGS / "xvfb.log",
    "nginx": NGINX_ERROR_LOG,
}

STAGE_LABELS = {
    "idle": "Idle",
    "setup": "Provisioning",
    "display": "Starting display",
    "audio": "Starting audio",
    "stream": "Starting stream",
    "proxy": "Opening the gateway",
    "console": "Starting console",
    "stream-ready": "Stream ready",
    "game-booting": "Starting Minecraft",
    "restarting-game": "Restarting Minecraft",
    "restarting-stream": "Restarting stream",
    "running": "Running",
    "stopped": "Stopped",
    "error": "Error",
}

# Mirrors the GLIDE_STAGE markers printed by Client/scripts/glide_launch.py.
LOG_STAGES = {
    "minecraft-download": (0.30, "Downloading Minecraft"),
    "fabric-install": (0.40, "Installing Fabric"),
    "forge-install": (0.40, "Installing Forge"),
    "forge-installer-download": (0.38, "Downloading Forge installer"),
    "neoforge-install": (0.40, "Installing NeoForge"),
    "quilt-install": (0.40, "Installing Quilt"),
    "microsoft-login": (0.35, "Waiting for Microsoft sign-in"),
    "minecraft-options": (0.55, "Preparing options"),
    "minecraft-natives": (0.62, "Extracting natives"),
    "minecraft-command": (0.72, "Building launch command"),
    "minecraft-running": (0.95, "Starting the game window"),
}

STAGE_PROGRESS = {
    "idle": 0.0,
    "display": 0.12,
    "audio": 0.2,
    "stream": 0.45,
    "proxy": 0.6,
    "console": 0.68,
    "stream-ready": 0.75,
    "game-booting": 0.8,
    "restarting-game": 0.75,
    "restarting-stream": 0.5,
    "running": 1.0,
    "stopped": 0.0,
    "error": 0.0,
}

ALLOWED_ACTIONS = {
    "restart-game": ["restart-game"],
    "restart-stream": ["restart-stream"],
    "restart-session": ["restart"],
    "stop": ["stop"],
    "profile": ["profile"],
    "resolution": ["resize"],
    "dashboard": ["dashboard"],
    "save": ["save"],
}

LOADERS = [
    "vanilla",
    "fabric",
    "legacy-fabric",
    "forge",
    "legacy-forge",
    "quilt",
    "neoforge",
]
ENCODERS = ["h264enc", "h265enc", "vp8enc", "vp9enc", "av1enc", "h264enc-striped", "jpeg"]
DEFAULT_VERSIONS = [
    "1.21.5",
    "1.21.4",
    "1.21.1",
    "1.20.6",
    "1.20.4",
    "1.20.1",
    "1.19.4",
    "1.18.2",
    "1.16.5",
    "1.12.2",
    "1.8.9",
]

VERSION_RE = re.compile(r"^\d{1,2}\.\d{1,2}(?:\.\d{1,2})?$")
RESOLUTION_RE = re.compile(r"^\d{3,4}x\d{3,4}$")
XMX_RE = re.compile(r"^[1-9]\d{0,1}G$")
USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{3,16}$")
FILE_NAME_RE = re.compile(r"^[^/\\\x00]{1,160}$")

ROOTS = {
    "repo": ROOT,
    "minecraft": MINECRAFT_DIR,
}


class ApiError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


# --------------------------------------------------------------------- utils ---
def read_state() -> dict[str, str]:
    state: dict[str, str] = {}
    try:
        text = STATE_FILE.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return state
    for line in text.splitlines():
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        state[key.strip()] = value.strip()
    return state


def read_session_env() -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        text = SESSION_ENV.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return values
    for line in text.splitlines():
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def write_session_env(updates: dict[str, str]) -> None:
    lines: list[str] = []
    try:
        lines = SESSION_ENV.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        lines = []
    remaining = dict(updates)
    output: list[str] = []
    for line in lines:
        if "=" in line and not line.lstrip().startswith("#"):
            key = line.split("=", 1)[0].strip()
            if key in remaining:
                output.append(f"{key}={remaining.pop(key)}")
                continue
        output.append(line)
    for key, value in remaining.items():
        output.append(f"{key}={value}")
    SESSION_ENV.parent.mkdir(parents=True, exist_ok=True)
    temp = SESSION_ENV.with_suffix(".tmp")
    temp.write_text("\n".join(output).rstrip() + "\n", encoding="utf-8")
    os.replace(temp, SESSION_ENV)


def pid_alive(pid: int | None) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def read_pid(name: str) -> int | None:
    try:
        return int((RUN / f"{name}.pid").read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None


def tail_lines(path: Path, limit: int) -> list[str]:
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            return [line.rstrip("\n") for line in deque(handle, maxlen=max(1, limit))]
    except OSError:
        return []


def last_marker(lines: list[str], prefix: str) -> str:
    pattern = re.compile(rf"^{re.escape(prefix)}=(.*)$")
    for line in reversed(lines):
        match = pattern.match(line.strip())
        if match:
            return match.group(1)
    return ""


def port_answers(port: int, timeout: float = 0.6) -> bool:
    import socket

    try:
        with socket.create_connection(("127.0.0.1", port), timeout=timeout):
            return True
    except OSError:
        return False


def queue_command(argv: list[str]) -> None:
    log_path = LOGS / "actions.log"
    try:
        with log_path.open("a", encoding="utf-8") as log:
            log.write(f"\n--- {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {' '.join(argv)}\n")
            subprocess.Popen(
                ["bash", str(GLIDE_CLI), *argv],
                cwd=str(ROOT),
                stdout=log,
                stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL,
                start_new_session=True,
            )
    except OSError as error:
        raise ApiError(500, f"could not start action: {error}") from error


def queue_restart(mode: str) -> None:
    mapping = {"stream": "restart-stream", "game": "restart-game", "session": "restart"}
    if mode in mapping:
        queue_command([mapping[mode]])


# --------------------------------------------------------------- validation ---
def require(regex: re.Pattern[str], value: object, label: str) -> str:
    text = str(value if value is not None else "").strip()
    if not regex.fullmatch(text):
        raise ApiError(400, f"{label} is not valid")
    return text


def as_bool(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    text = str(value).strip().lower()
    if text in {"true", "1", "yes", "on"}:
        return "true"
    if text in {"false", "0", "no", "off"}:
        return "false"
    raise ApiError(400, "expected a boolean")


def as_int(value: object, low: int, high: int, label: str) -> str:
    try:
        number = int(str(value).strip())
    except (TypeError, ValueError) as error:
        raise ApiError(400, f"{label} must be a number") from error
    if number < low or number > high:
        raise ApiError(400, f"{label} must be between {low} and {high}")
    return str(number)


def as_client_id(value: object) -> str:
    text = str(value if value is not None else "").strip()
    if not re.fullmatch(r"[A-Za-z0-9._-]{0,128}", text):
        raise ApiError(400, "Microsoft client id contains invalid characters")
    return text


def as_loader(value: object) -> str:
    text = str(value if value is not None else "").strip().lower()
    if text not in LOADERS:
        raise ApiError(400, "unknown loader")
    return text


CONFIG_FIELDS = {
    "version": ("GLIDE_MINECRAFT_VERSION", lambda v: require(VERSION_RE, v, "Minecraft version")),
    "loader": ("GLIDE_MINECRAFT_LOADER", as_loader),
    "xmx": ("GLIDE_MINECRAFT_XMX", lambda v: require(XMX_RE, v, "heap size")),
    "resolution": ("GLIDE_RESOLUTION", lambda v: require(RESOLUTION_RE, v, "resolution")),
    "fps": ("GLIDE_FPS", lambda v: as_int(v, 15, 120, "framerate")),
    "bitrate": ("GLIDE_BITRATE", lambda v: as_int(v, 500, 30000, "bitrate")),
    "encoder": ("GLIDE_ENCODER", lambda v: require_enum(v, ENCODERS, "encoder")),
    "dashboard": ("GLIDE_DASHBOARD", as_bool),
    "audio": ("GLIDE_AUDIO", as_bool),
    "auth_mode": ("GLIDE_AUTH_MODE", lambda v: require_enum(v, ["offline", "microsoft"], "auth mode")),
    "username": ("GLIDE_OFFLINE_USERNAME", lambda v: require(USERNAME_RE, v, "offline username")),
    "client_id": ("GLIDE_MICROSOFT_CLIENT_ID", lambda v: as_client_id(v)),
}


def require_enum(value: object, options: list[str], label: str) -> str:
    text = str(value if value is not None else "").strip()
    if text not in options:
        raise ApiError(400, f"unknown {label}")
    return text


def typed(value: str, key: str) -> object:
    if key in {"dashboard", "audio"}:
        return value.lower() == "true"
    if key in {"fps", "bitrate"}:
        try:
            return int(value)
        except ValueError:
            return 0
    return value


def current_config() -> dict:
    env = read_session_env()
    values: dict[str, object] = {}
    for key, (env_key, _validator) in CONFIG_FIELDS.items():
        default = ""
        values[key] = typed(env.get(env_key, default), key)
    values["version"] = values["version"] or "1.21.5"
    values["loader"] = values["loader"] or "fabric"
    values["xmx"] = values["xmx"] or "4G"
    values["resolution"] = values["resolution"] or "1280x720"
    values["fps"] = values["fps"] or 60
    values["bitrate"] = values["bitrate"] or 6000
    values["encoder"] = values["encoder"] or "h264enc"
    values["auth_mode"] = values["auth_mode"] or "offline"
    values["username"] = values["username"] or "GlidePlayer"
    values["client_id"] = values.get("client_id") or ""
    values["dashboard"] = env.get("GLIDE_DASHBOARD", "true").lower() == "true"
    values["audio"] = env.get("GLIDE_AUDIO", "true").lower() == "true"
    return values


def mods_dir(version: str, loader: str) -> Path:
    require(VERSION_RE, version, "Minecraft version")
    as_loader(loader)
    return REPO_MODS / version / loader


def list_mods(version: str, loader: str) -> list[dict]:
    try:
        directory = mods_dir(version, loader)
    except ApiError:
        return []
    entries: list[dict] = []
    try:
        children = sorted(directory.iterdir(), key=lambda p: p.name.lower())
    except OSError:
        return entries
    for child in children:
        if not child.is_file() or child.name.startswith("."):
            continue
        if child.suffix.lower() not in {".jar", ".zip"}:
            continue
        stat = child.stat()
        entries.append(
            {
                "name": child.name,
                "size": stat.st_size,
                "modified": int(stat.st_mtime),
            }
        )
    return entries


def available_versions() -> list[str]:
    versions: set[str] = set(DEFAULT_VERSIONS)
    try:
        data = json.loads(VERSIONS_FILE.read_text(encoding="utf-8"))
        versions.update(str(key) for key in (data.get("versions") or {}).keys())
    except (OSError, ValueError):
        pass
    try:
        for child in (ROOT / "Client").iterdir():
            if child.is_dir() and VERSION_RE.fullmatch(child.name):
                versions.add(child.name)
    except OSError:
        pass

    def sort_key(name: str) -> tuple:
        return tuple(int(part) for part in name.split("."))

    return sorted(versions, key=sort_key, reverse=True)


def config_payload() -> dict:
    values = current_config()
    return {
        "ok": True,
        "values": values,
        "options": {"loaders": LOADERS, "encoders": ENCODERS, "versions": available_versions()},
        "mods": list_mods(str(values["version"]), str(values["loader"])),
        "mod_dir": f"Client/mods/{values['version']}/{values['loader']}",
    }


def apply_config(values: dict, restart: str) -> dict:
    updates: dict[str, str] = {}
    applied: dict[str, object] = {}
    for key, raw in values.items():
        if key not in CONFIG_FIELDS:
            continue
        env_key, validator = CONFIG_FIELDS[key]
        normalized = validator(raw)
        updates[env_key] = normalized
        applied[key] = typed(normalized, key)
    if updates:
        write_session_env(updates)
    if restart in {"stream", "game", "session"}:
        queue_restart(restart)
    return {"ok": True, "applied": applied, "restart": restart, "config": config_payload()}


# -------------------------------------------------------------------- files ---
def resolve_path(root_key: str, rel: str) -> tuple[Path, Path, str]:
    if root_key not in ROOTS:
        raise ApiError(400, "unknown root")
    root = ROOTS[root_key].resolve()
    if root_key == "minecraft":
        root.mkdir(parents=True, exist_ok=True)
    cleaned = (rel or "").strip().lstrip("/")
    target = (root / cleaned).resolve() if cleaned else root
    if target != root and root not in target.parents:
        raise ApiError(400, "path escapes the root")
    try:
        parts = target.relative_to(root).parts
    except ValueError as error:
        raise ApiError(400, "path escapes the root") from error
    if ".git" in parts:
        raise ApiError(403, "the .git directory is off limits")
    return root, target, "/".join(parts)


def list_dir(root_key: str, rel: str) -> dict:
    root, target, cleaned = resolve_path(root_key, rel)
    if not target.exists():
        raise ApiError(404, "directory not found")
    if not target.is_dir():
        raise ApiError(400, "not a directory")
    entries: list[dict] = []
    try:
        children = sorted(target.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))
    except OSError as error:
        raise ApiError(500, f"could not read directory: {error}") from error
    for child in children[:2000]:
        if child.name == ".git":
            continue
        try:
            stat = child.stat()
        except OSError:
            continue
        entries.append(
            {
                "name": child.name,
                "type": "dir" if child.is_dir() else "file",
                "size": 0 if child.is_dir() else stat.st_size,
                "modified": int(stat.st_mtime),
            }
        )
    parent = "/".join(cleaned.split("/")[:-1]) if cleaned else ""
    return {
        "ok": True,
        "root": root_key,
        "path": cleaned,
        "parent": parent,
        "root_label": "Repository" if root_key == "repo" else "Minecraft data",
        "entries": entries,
    }


def read_file(root_key: str, rel: str) -> dict:
    _root, target, cleaned = resolve_path(root_key, rel)
    if not target.is_file():
        raise ApiError(404, "file not found")
    size = target.stat().st_size
    if size > MAX_PREVIEW:
        return {"ok": True, "path": cleaned, "kind": "binary", "size": size, "too_big": True}
    data = target.read_bytes()
    try:
        text = data.decode("utf-8")
        return {"ok": True, "path": cleaned, "kind": "text", "size": size, "text": text}
    except UnicodeDecodeError:
        return {
            "ok": True,
            "path": cleaned,
            "kind": "binary",
            "size": size,
            "base64": base64.b64encode(data).decode("ascii"),
        }


def save_file(root_key: str, rel: str, text: str) -> dict:
    if len(text.encode("utf-8")) > MAX_PREVIEW:
        raise ApiError(413, "file is too large to edit")
    _root, target, cleaned = resolve_path(root_key, rel)
    if target.is_dir():
        raise ApiError(400, "that path is a directory")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")
    return {"ok": True, "path": cleaned, "size": len(text.encode("utf-8"))}


def make_dir(root_key: str, rel: str) -> dict:
    _root, target, cleaned = resolve_path(root_key, rel)
    target.mkdir(parents=True, exist_ok=True)
    return {"ok": True, "path": cleaned}


def delete_path(root_key: str, rel: str) -> dict:
    root, target, cleaned = resolve_path(root_key, rel)
    if target == root:
        raise ApiError(400, "refusing to delete the root")
    if not target.exists():
        raise ApiError(404, "path not found")
    if target.is_dir():
        shutil.rmtree(target)
    else:
        target.unlink()
    return {"ok": True, "path": cleaned}


# ------------------------------------------------------------------- status ---
def build_status() -> dict:
    state = read_state()
    cfg = read_session_env()
    now = int(time.time())

    mc_tail = tail_lines(MC_LOG, 600) if MC_LOG.exists() else []
    log_stage = last_marker(mc_tail, "GLIDE_STAGE")
    ready = last_marker(mc_tail, "GLIDE_READY") == "true"
    mc_pid = read_pid("minecraft")
    launcher_alive = pid_alive(mc_pid)

    stage_key = state.get("STAGE", "idle")
    detail = state.get("DETAIL", "")

    if stage_key in {"game-booting", "running", "stream-ready", "restarting-game"}:
        if log_stage in LOG_STAGES and not ready:
            detail = LOG_STAGES[log_stage][1]
        if ready and launcher_alive:
            stage_key = "running"
            detail = "Minecraft is running"
        elif stage_key == "running" and not launcher_alive:
            stage_key = "error"
            detail = "Minecraft exited unexpectedly"
        elif stage_key in {"game-booting", "restarting-game"} and not launcher_alive and mc_tail:
            stage_key = "error"
            detail = "The Minecraft launcher exited - check the log"

    if stage_key == "error" and state.get("LAST_ERROR"):
        detail = state["LAST_ERROR"]

    started_at = int(state.get("SESSION_STARTED_AT", "0") or 0)
    updated_at = int(state.get("UPDATED_AT", "0") or 0)
    uptime = max(0, now - started_at) if started_at else 0

    progress = STAGE_PROGRESS.get(stage_key, 0.0)
    if stage_key == "game-booting" and log_stage in LOG_STAGES:
        progress = LOG_STAGES[log_stage][0]
    if stage_key == "running":
        progress = 1.0

    resolution = cfg.get("GLIDE_RESOLUTION", "1280x720")
    width, _, height = resolution.partition("x")
    dashboard = cfg.get("GLIDE_DASHBOARD", "true").lower() == "true"

    public_host = ""
    codespace = os.environ.get("CODESPACE_NAME", "")
    domain = os.environ.get("GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN", "app.github.dev")
    if codespace:
        public_host = f"{codespace}-{PROXY_PORT}.{domain}"

    return {
        "ok": True,
        "app": {"name": APP_NAME, "version": APP_VERSION},
        "now": now,
        "key_required": bool(WEB_KEY),
        "host": {
            "hostname": os.uname().nodename,
            "codespace": codespace,
            "domain": domain,
            "public_url": f"https://{public_host}" if public_host else "",
            "repo": str(ROOT),
        },
        "stage": {
            "key": stage_key,
            "label": STAGE_LABELS.get(stage_key, stage_key.title()),
            "detail": detail,
            "progress": round(progress, 3),
            "updated_at": updated_at,
            "started_at": started_at,
        },
        "minecraft": {
            "version": cfg.get("GLIDE_MINECRAFT_VERSION", ""),
            "loader": cfg.get("GLIDE_MINECRAFT_LOADER", ""),
            "xmx": cfg.get("GLIDE_MINECRAFT_XMX", ""),
            "auth_mode": cfg.get("GLIDE_AUTH_MODE", "offline"),
            "pid": mc_pid if launcher_alive else None,
            "running": launcher_alive,
            "ready": bool(ready and launcher_alive),
            "log_stage": log_stage,
            "resolution": resolution,
        },
        "stream": {
            "ready": port_answers(SELKIES_PORT),
            "gateway_ready": port_answers(PROXY_PORT),
            "port": SELKIES_PORT,
            "gateway_port": PROXY_PORT,
            "encoder": cfg.get("GLIDE_ENCODER", "h264enc"),
            "fps": int(cfg.get("GLIDE_FPS", "60") or 60),
            "bitrate": int(cfg.get("GLIDE_BITRATE", "6000") or 6000),
            "audio": cfg.get("GLIDE_AUDIO", "true").lower() == "true",
            "dashboard": dashboard,
        },
        "audio_ready": state.get("AUDIO_READY", "").lower() == "true",
        "display": {
            "server": "Xvfb",
            "display": os.environ.get("GLIDE_DISPLAY", ":99"),
            "width": int(width) if width.isdigit() else 1280,
            "height": int(height) if height.isdigit() else 720,
        },
        "session": {
            "up": launcher_alive or stage_key in {"running", "game-booting", "stream-ready"},
            "uptime_seconds": uptime,
            "processes": {
                "xvfb": pid_alive(read_pid("xvfb")),
                "selkies": pid_alive(read_pid("selkies")),
                "console": pid_alive(read_pid("console")),
                "minecraft": launcher_alive,
            },
        },
        "actions": sorted(ALLOWED_ACTIONS.keys()),
        "log_tail": [line for line in mc_tail[-10:] if line.strip()],
    }


# --------------------------------------------------------------------- http ---
class Handler(BaseHTTPRequestHandler):
    server_version = f"{APP_NAME}/{APP_VERSION}"
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args) -> None:  # keep the console log quiet
        return

    # -- helpers ----------------------------------------------------------
    def cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Glide-Key")
        self.send_header("Cache-Control", "no-store")

    def send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, text: str, status: int = 200) -> None:
        body = text.encode("utf-8")
        self.send_response(status)
        self.cors()
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_bytes(self, body: bytes, content_type: str, extra: dict | None = None) -> None:
        self.send_response(200)
        self.cors()
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def key_ok(self, query: dict[str, list[str]]) -> bool:
        if not WEB_KEY:
            return True
        supplied = self.headers.get("X-Glide-Key", "") or (query.get("key", [""])[0])
        return supplied == WEB_KEY

    def require_key(self, query: dict[str, list[str]]) -> None:
        if not self.key_ok(query):
            raise ApiError(401, "missing or wrong action key")

    def route(self) -> str:
        path = urlparse(self.path).path
        if path.startswith("/glide/"):
            path = path[len("/glide") :]
        return path.rstrip("/") or "/"

    def query(self) -> dict[str, list[str]]:
        return parse_qs(urlparse(self.path).query)

    def json_body(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise ApiError(400, "invalid content length") from error
        if length <= 0 or length > MAX_JSON:
            raise ApiError(400, "invalid body")
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError) as error:
            raise ApiError(400, "invalid json") from error
        if not isinstance(payload, dict):
            raise ApiError(400, "expected a json object")
        return payload

    def raw_upload(self) -> tuple[Path, int]:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise ApiError(400, "invalid content length") from error
        if length <= 0:
            raise ApiError(411, "content length required")
        if length > MAX_UPLOAD:
            raise ApiError(413, "file is larger than 256 MB")
        root_key = (self.query().get("root", ["repo"])[0] or "repo").strip()
        rel = self.query().get("path", [""])[0]
        name = (self.query().get("name", [""])[0] or "").strip()
        if not FILE_NAME_RE.fullmatch(name) or name in {".", ".."}:
            raise ApiError(400, "invalid file name")
        _root, directory, _cleaned = resolve_path(root_key, rel)
        if directory.is_file():
            raise ApiError(400, "destination is a file")
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / name
        temp = directory / f".glide-upload-{os.getpid()}.part"
        remaining = length
        try:
            with temp.open("wb") as handle:
                while remaining > 0:
                    chunk = self.rfile.read(min(CHUNK, remaining))
                    if not chunk:
                        break
                    handle.write(chunk)
                    remaining -= len(chunk)
            os.replace(temp, target)
        finally:
            temp.unlink(missing_ok=True)
        return target, length

    # -- routes -----------------------------------------------------------
    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        try:
            path = self.route()
            query = self.query()
            if path in {"/health"}:
                self.send_text("ok")
            elif path in {"/", "/status"}:
                self.send_json(build_status())
            elif path == "/config":
                self.send_json(config_payload())
            elif path == "/mods":
                cfg = current_config()
                version = (query.get("version", [cfg["version"]])[0] or cfg["version"]).strip()
                loader = (query.get("loader", [cfg["loader"]])[0] or cfg["loader"]).strip()
                self.send_json({"ok": True, "version": version, "loader": loader, "mods": list_mods(version, loader)})
            elif path == "/log":
                name = (query.get("name", ["boot"])[0] or "boot").strip()
                try:
                    limit = max(1, min(2000, int(query.get("tail", ["200"])[0])))
                except ValueError:
                    limit = 200
                target = LOG_FILES.get(name)
                if target is None:
                    raise ApiError(404, f"unknown log '{name}'")
                self.send_text("\n".join(tail_lines(target, limit)))
            elif path == "/files":
                root_key = (query.get("root", ["repo"])[0] or "repo").strip()
                rel = (query.get("path", [""])[0] or "").strip()
                self.send_json(list_dir(root_key, rel))
            elif path == "/files/read":
                root_key = (query.get("root", ["repo"])[0] or "repo").strip()
                rel = (query.get("path", [""])[0] or "").strip()
                self.send_json(read_file(root_key, rel))
            elif path == "/files/download":
                root_key = (query.get("root", ["repo"])[0] or "repo").strip()
                rel = (query.get("path", [""])[0] or "").strip()
                _root, target, cleaned = resolve_path(root_key, rel)
                if not target.is_file():
                    raise ApiError(404, "file not found")
                content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
                name = os.path.basename(cleaned)
                body = target.read_bytes()
                self.send_bytes(
                    body,
                    content_type,
                    {"Content-Disposition": f"attachment; filename=\"{quote(name)}\""},
                )
            else:
                raise ApiError(404, "not found")
        except ApiError as error:
            self.send_json({"ok": False, "error": error.message}, error.status)
        except Exception as error:  # noqa: BLE001 - a broken request must not kill the daemon
            self.send_json({"ok": False, "error": f"{type(error).__name__}: {error}"}, 500)

    def do_POST(self) -> None:  # noqa: N802
        try:
            path = self.route()
            query = self.query()
            if path in {"/action", "/config", "/mods/upload", "/mods/delete", "/files/save", "/files/upload", "/files/mkdir", "/files/delete"}:
                self.require_key(query)

            if path == "/action":
                payload = self.json_body()
                action = str(payload.get("action", "")).strip()
                args = payload.get("args") or {}
                if action not in ALLOWED_ACTIONS:
                    raise ApiError(400, f"unknown action '{action}'")
                argv = list(ALLOWED_ACTIONS[action])
                if action == "profile":
                    preset = str(args.get("preset", "")).strip()
                    if preset not in {"low", "medium", "high"}:
                        raise ApiError(400, "preset must be low, medium or high")
                    argv.append(preset)
                elif action == "resolution":
                    width = str(args.get("width", "")).strip()
                    height = str(args.get("height", "")).strip()
                    if not width.isdigit() or not height.isdigit():
                        raise ApiError(400, "width and height must be numbers")
                    argv.append(f"{width}x{height}")
                elif action == "dashboard":
                    argv.append("on" if args.get("on", True) else "off")
                queue_command(argv)
                self.send_json({"ok": True, "queued": True, "action": action})

            elif path == "/config":
                payload = self.json_body()
                values = payload.get("values") or {}
                if not isinstance(values, dict):
                    raise ApiError(400, "values must be an object")
                restart = str(payload.get("restart", "none") or "none")
                if restart not in {"none", "stream", "game", "session"}:
                    raise ApiError(400, "unknown restart mode")
                self.send_json(apply_config(values, restart))

            elif path == "/mods/upload":
                cfg = current_config()
                version = (query.get("version", [cfg["version"]])[0] or cfg["version"]).strip()
                loader = (query.get("loader", [cfg["loader"]])[0] or cfg["loader"]).strip()
                name = (query.get("name", [""])[0] or "").strip()
                directory = mods_dir(version, loader)
                if not FILE_NAME_RE.fullmatch(name) or Path(name).suffix.lower() not in {".jar", ".zip"}:
                    raise ApiError(400, "mods must be .jar or .zip files")
                try:
                    length = int(self.headers.get("Content-Length", "0"))
                except ValueError as error:
                    raise ApiError(400, "invalid content length") from error
                if length <= 0:
                    raise ApiError(411, "content length required")
                if length > MAX_UPLOAD:
                    raise ApiError(413, "mod is larger than 256 MB")
                directory.mkdir(parents=True, exist_ok=True)
                target = directory / name
                temp = directory / f".glide-upload-{os.getpid()}.part"
                remaining = length
                try:
                    with temp.open("wb") as handle:
                        while remaining > 0:
                            chunk = self.rfile.read(min(CHUNK, remaining))
                            if not chunk:
                                break
                            handle.write(chunk)
                            remaining -= len(chunk)
                    os.replace(temp, target)
                finally:
                    temp.unlink(missing_ok=True)
                self.send_json({"ok": True, "name": name, "size": target.stat().st_size})

            elif path == "/mods/delete":
                payload = self.json_body()
                version = str(payload.get("version", "")).strip()
                loader = str(payload.get("loader", "")).strip()
                name = str(payload.get("name", "")).strip()
                target = mods_dir(version, loader) / name
                if not FILE_NAME_RE.fullmatch(name) or not target.is_file():
                    raise ApiError(404, "mod not found")
                target.unlink()
                self.send_json({"ok": True, "name": name})

            elif path == "/files/save":
                payload = self.json_body()
                root_key = str(payload.get("root", "repo")).strip()
                rel = str(payload.get("path", "")).strip()
                text = payload.get("text", "")
                if not isinstance(text, str):
                    raise ApiError(400, "text must be a string")
                self.send_json(save_file(root_key, rel, text))

            elif path == "/files/mkdir":
                payload = self.json_body()
                self.send_json(
                    make_dir(str(payload.get("root", "repo")), str(payload.get("path", "")))
                )

            elif path == "/files/delete":
                payload = self.json_body()
                self.send_json(
                    delete_path(str(payload.get("root", "repo")), str(payload.get("path", "")))
                )

            elif path == "/files/upload":
                target, size = self.raw_upload()
                try:
                    shown = target.relative_to(ROOT).as_posix()
                except ValueError:
                    shown = target.name
                self.send_json({"ok": True, "name": target.name, "size": size, "path": shown})
            else:
                raise ApiError(404, "not found")
        except ApiError as error:
            self.send_json({"ok": False, "error": error.message}, error.status)
        except Exception as error:  # noqa: BLE001
            self.send_json({"ok": False, "error": f"{type(error).__name__}: {error}"}, 500)


def main() -> int:
    for directory in (HOME, LOGS, RUN, MINECRAFT_DIR):
        directory.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    server.daemon_threads = True
    print(f"{APP_NAME} {APP_VERSION} listening on 127.0.0.1:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
