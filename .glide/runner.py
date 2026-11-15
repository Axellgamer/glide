#!/usr/bin/env python3
import base64, codecs, fcntl, json, os, pathlib, pty, signal, struct, subprocess, tempfile, threading, time, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
import pyte

ROOT = pathlib.Path(__file__).resolve().parent.parent
NAME = os.environ.get("CODESPACE_NAME", "")
PUBLIC_KEY = ROOT / ".glide/runner-public.pem"
SCREEN = pyte.HistoryScreen(100, 28, history=200)
STREAM = pyte.Stream(SCREEN)
CONDITION = threading.Condition()
REVISION = 0
EXITED = False
PUBLIC_STREAM = False
PORT_ERROR = ""
VERIFIED = {}
AUTH_LOCK = threading.Lock()

pid, master = pty.fork()
if pid == 0:
    os.chdir(ROOT)
    env = dict(os.environ, TERM="xterm-256color", COLUMNS="100", LINES="28")
    env["PATH"] = str(pathlib.Path.home() / ".local/bin") + ":" + env.get("PATH", "")
    os.execve("/bin/bash", ["bash", "-lc", "bash codespace/menu.sh; exec bash -i"], env)
fcntl.ioctl(master, 0x5414, struct.pack("HHHH", 28, 100, 0, 0))


def read_terminal():
    global REVISION, EXITED
    decoder = codecs.getincrementaldecoder("utf-8")("replace")
    while True:
        try:
            data = os.read(master, 8192)
            if not data:
                break
            with CONDITION:
                STREAM.feed(decoder.decode(data))
                REVISION += 1
                CONDITION.notify_all()
        except OSError:
            break
    with CONDITION:
        EXITED = True
        REVISION += 1
        CONDITION.notify_all()


def keep_ports_public():
    global PUBLIC_STREAM, PORT_ERROR, REVISION
    while True:
        messages = []
        for number in (6081, 6080):
            try:
                result = subprocess.run(["gh", "codespace", "ports", "visibility", str(number) + ":public", "-c", NAME], capture_output=True, text=True, timeout=45)
                if result.returncode:
                    messages.append(result.stderr.strip()[-600:])
            except (OSError, subprocess.TimeoutExpired) as error:
                messages.append(str(error))
        ready = False
        try:
            with urllib.request.urlopen("https://" + NAME + "-6080.app.github.dev/healthz", timeout=5) as response:
                ready = response.status == 200 and response.read(16).strip() == b"ok"
        except Exception:
            pass
        with CONDITION:
            PUBLIC_STREAM = ready
            PORT_ERROR = "\n".join(messages)
            REVISION += 1
            CONDITION.notify_all()
        if messages:
            print("Public forwarding:", PORT_ERROR, flush=True)
        time.sleep(60 if ready else 10)


def decode64(value):
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def authorized(token):
    if not token or len(token) > 4096:
        return False
    with AUTH_LOCK:
        if VERIFIED.get(token, 0) > time.time():
            return True
        try:
            header, payload, signature = token.split(".")
            claims = json.loads(decode64(payload))
            if json.loads(decode64(header)).get("alg") != "RS256" or claims.get("aud") != "glide-terminal" or claims.get("name") != NAME:
                return False
            expires = claims.get("exp", 0)
            if not isinstance(expires, (int, float)) or expires <= time.time() or expires > time.time() + 660:
                return False
            with tempfile.NamedTemporaryFile() as sigfile:
                sigfile.write(decode64(signature))
                sigfile.flush()
                check = subprocess.run(["openssl", "dgst", "-sha256", "-verify", str(PUBLIC_KEY), "-signature", sigfile.name], input=(header + "." + payload).encode(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
            if check.returncode:
                return False
            for cached, expiry in list(VERIFIED.items()):
                if expiry < time.time():
                    del VERIFIED[cached]
            if len(VERIFIED) >= 128:
                VERIFIED.clear()
            VERIFIED[token] = expires
            return True
        except Exception:
            return False


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Never log bearer tickets or terminal input.

    def cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Max-Age", "600")
        self.send_header("Cache-Control", "no-store")

    def reply(self, data, status=200):
        content = json.dumps(data).encode()
        self.send_response(status)
        self.cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_OPTIONS(self):
        self.send_response(204)
        self.cors()
        self.end_headers()

    def check_auth(self):
        value = self.headers.get("Authorization", "")
        if not value.startswith("Bearer ") or not authorized(value[7:]):
            self.reply({"error": "Terminal authorization expired. Reconnect in Glide Runner."}, 401)
            return False
        return True

    def do_GET(self):
        path = urlparse(self.path)
        if path.path == "/healthz":
            self.reply({"bridge": 1, "name": NAME})
            return
        if not self.check_auth():
            return
        if path.path != "/output":
            self.reply({"error": "Not found"}, 404)
            return
        try:
            cursor = int(parse_qs(path.query).get("cursor", ["-1"])[0])
        except ValueError:
            self.reply({"error": "Invalid cursor"}, 400)
            return
        with CONDITION:
            if cursor == REVISION and not EXITED:
                CONDITION.wait(timeout=20)
            history = ["".join(line.get(x, SCREEN.default_char).data for x in range(SCREEN.columns)).rstrip() for line in SCREEN.history.top]
            result = {"lines": history + SCREEN.display, "revision": REVISION, "exited": EXITED, "public_stream": PUBLIC_STREAM, "port_error": PORT_ERROR}
        self.reply(result)

    def do_POST(self):
        if not self.check_auth():
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 16384:
                self.reply({"error": "Input too large"}, 400)
                return
            body = json.loads(self.rfile.read(length))
            path = urlparse(self.path).path
            if path == "/input":
                data = body.get("data")
                if not isinstance(data, str) or len(data) > 4096 or EXITED:
                    self.reply({"error": "Terminal is closed or input is invalid"}, 400)
                    return
                encoded = data.encode()
                while encoded:
                    encoded = encoded[os.write(master, encoded):]
            elif path == "/resize":
                cols, rows = int(body.get("cols", 100)), int(body.get("rows", 28))
                if not 40 <= cols <= 180 or not 10 <= rows <= 60:
                    self.reply({"error": "Invalid terminal size"}, 400)
                    return
                with CONDITION:
                    SCREEN.resize(lines=rows, columns=cols)
                    fcntl.ioctl(master, 0x5414, struct.pack("HHHH", rows, cols, 0, 0))
                os.kill(pid, signal.SIGWINCH)
            else:
                self.reply({"error": "Not found"}, 404)
                return
            self.reply({"ok": True})
        except (ValueError, TypeError, OSError):
            self.reply({"error": "Unable to send terminal input"}, 400)


threading.Thread(target=read_terminal, daemon=True).start()
threading.Thread(target=keep_ports_public, daemon=True).start()
print("Glide Runner terminal listening on http://localhost:6081", flush=True)
ThreadingHTTPServer(("0.0.0.0", 6081), Handler).serve_forever()
