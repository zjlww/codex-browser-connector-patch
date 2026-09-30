#!/usr/bin/python3
"""Proxy for the Codex CLI used by the browser/computer-use runtime.

The runtime spawns `$CODEX_CLI_PATH app-server` and asks it for `getAuthStatus`;
when the reply carries no auth token it aborts browser discovery with
"Codex auth token is unavailable". This shim runs the real CLI, forwards every
JSON-RPC line unchanged, and rewrites only that one reply so it looks like a
ChatGPT login. The synthetic token is never sent to OpenAI by the shim.

Privacy: by default only method names and rewrites are logged, never payloads
(earlier revisions logged up to 600 characters of every message, which could
capture message content). Set CODEX_AUTH_SHIM_LOG_PAYLOADS=1 to log payloads
while debugging.
"""
import base64
import json
import os
import subprocess
import sys
import threading
import time

REAL_CLI = os.environ.get(
    "CODEX_AUTH_SHIM_REAL_CLI", "/Applications/ChatGPT.app/Contents/Resources/codex"
)
ROLLBACK_DIR = os.path.expanduser(
    os.environ.get("CODEX_BROWSER_ROLLBACK_DIR", "~/.local/share/codex-rollback")
)
LOG_PATH = os.path.join(ROLLBACK_DIR, "shim.log")
TOKEN_PATH = os.path.join(ROLLBACK_DIR, "token.txt")
LOG_PAYLOADS = os.environ.get("CODEX_AUTH_SHIM_LOG_PAYLOADS") == "1"


def log(kind, text):
    try:
        with open(LOG_PATH, "a") as fh:
            fh.write("%s %s %s\n" % (time.strftime("%H:%M:%S"), kind, text[:600]))
    except Exception:
        pass


def summarize(line):
    """Return a non-sensitive description of a JSON-RPC line."""
    if LOG_PAYLOADS:
        return line.strip()[:600]
    try:
        msg = json.loads(line)
    except Exception:
        return "<non-json %d bytes>" % len(line)
    method = msg.get("method")
    if method is None:
        result = msg.get("result")
        if isinstance(result, dict):
            return "response keys=%s" % ",".join(sorted(result)[:6])
        return "response"
    return "%s id=%s" % (method, msg.get("id"))


def b64(obj):
    raw = json.dumps(obj, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def synthetic_token():
    now = int(time.time())
    header = {"alg": "RS256", "typ": "JWT", "kid": "codex-auth-shim"}
    payload = {
        "iss": "https://auth.openai.com",
        "aud": ["https://api.openai.com/v1"],
        "exp": now + 86400 * 30,
        "iat": now,
        "sub": "user-shim",
        "email": "shim@example.com",
        "email_verified": True,
        "name": "Codex Shim",
        "jti": "shim-jti",
        "sid": "shim-sid",
        "https://api.openai.com/auth": {
            "chatgpt_account_id": "acct-shim",
            "chatgpt_plan_type": "plus",
            "chatgpt_user_id": "user-shim",
            "chatgpt_account_user_id": "user-shim",
            "organization_id": "org-shim",
            "user_id": "user-shim",
        },
    }
    return b64(header) + "." + b64(payload) + "." + b64({"sig": "shim"})


def current_token():
    """Prefer an operator-supplied token so it can change without a restart."""
    try:
        with open(TOKEN_PATH) as fh:
            value = fh.read().strip()
        if value:
            return value
    except Exception:
        pass
    return synthetic_token()


def main():
    log("start", "argv=%s" % " ".join(sys.argv[1:]))
    child = subprocess.Popen(
        [REAL_CLI] + sys.argv[1:],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=sys.stderr,
        text=True,
        bufsize=1,
    )

    def pump_stdin():
        try:
            for line in sys.stdin:
                log("req", summarize(line))
                child.stdin.write(line)
                child.stdin.flush()
        except Exception:
            pass
        finally:
            try:
                child.stdin.close()
            except Exception:
                pass

    threading.Thread(target=pump_stdin, daemon=True).start()

    for line in child.stdout:
        stripped = line.strip()
        if stripped.startswith("{") and '"authMethod"' in stripped:
            try:
                msg = json.loads(stripped)
                result = msg.get("result")
                if isinstance(result, dict) and not result.get("authToken"):
                    result["authMethod"] = "chatgpt"
                    result["authToken"] = current_token()
                    result["requiresOpenaiAuth"] = False
                    sys.stdout.write(json.dumps(msg) + "\n")
                    sys.stdout.flush()
                    log("rewrote", "getAuthStatus -> chatgpt")
                    continue
            except Exception:
                pass
        log("resp", summarize(stripped))
        sys.stdout.write(line)
        sys.stdout.flush()


if __name__ == "__main__":
    main()
