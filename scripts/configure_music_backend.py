#!/usr/bin/env python3
"""Configure the dedicated music Worker without building locally or printing secrets."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
KEYS = ("TELEGRAM_BOT_TOKEN", "TELEGRAM_STORAGE_CHAT_ID", "TELEGRAM_WEBHOOK_SECRET", "API_KEYS", "SEND_CHAT_IDS", "ADMIN_KEY")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["deploy", "check"])
    parser.add_argument("--env-file", type=Path, default=ROOT / ".env")
    parser.add_argument("--url", default="")
    args = parser.parse_args()
    settings = load_settings(args.env_file)
    me = bot(settings, "getMe")
    chat = bot(settings, "getChat", {"chat_id": settings["TELEGRAM_STORAGE_CHAT_ID"]})
    member = bot(settings, "getChatMember", {"chat_id": settings["TELEGRAM_STORAGE_CHAT_ID"], "user_id": me["id"]})
    if member.get("status") not in ("administrator", "creator"):
        raise RuntimeError("Add the dedicated Bot as an administrator of the storage channel first.")
    if chat["type"] == "channel" and member.get("status") != "creator" and not member.get("can_post_messages"):
        raise RuntimeError("Storage Bot needs permission to post messages.")
    print("Verified Bot @" + me["username"] + " and private storage administrator.")
    url = args.url.rstrip("/")
    if args.operation == "deploy":
        run("d1", "migrations", "apply", "c0snow-music", "--remote")
        output = run("deploy", "--no-bundle")
        if not url:
            match = re.search(r"https://[a-zA-Z0-9.-]+\.workers\.dev", output)
            if not match:
                raise RuntimeError("Worker URL not found; rerun with --url.")
            url = match.group()
        run("secret", "bulk", input_text=json.dumps(settings))
        bot(settings, "setWebhook", {"url": url + "/api/telegram/webhook", "secret_token": settings["TELEGRAM_WEBHOOK_SECRET"], "allowed_updates": ["channel_post", "message"]})
        print("Registered dedicated webhook.")
    if not url.startswith("https://"):
        raise RuntimeError("Supply the HTTPS Worker URL with --url.")
    webhook = bot(settings, "getWebhookInfo")
    if webhook.get("url") != url + "/api/telegram/webhook":
        raise RuntimeError("Webhook does not match this Worker.")
    key = next(iter(json.loads(settings["API_KEYS"])))
    request = urllib.request.Request(url + "/api/tracks?limit=1", headers={"Authorization": "Bearer " + key})
    with urllib.request.urlopen(request, timeout=30) as response:
        result = json.load(response)
    if "items" not in result:
        raise RuntimeError("Catalog returned an unexpected response.")
    print("Verified protected catalog and webhook at " + url)
    print("Device credentials remain in " + str(args.env_file) + "; they were not printed.")


def load_settings(path):
    values = {}
    if path.exists():
        if path.stat().st_mode & 0o077:
            raise RuntimeError("The credential file must have permissions 0600.")
        for line in path.read_text().splitlines():
            if line.strip() and not line.lstrip().startswith("#"):
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip()
    values.update({key: os.environ[key] for key in KEYS if key in os.environ})
    missing = [key for key in KEYS if not values.get(key)]
    if missing:
        raise RuntimeError("Missing configuration keys: " + ", ".join(missing))
    return {key: values[key] for key in KEYS}


def bot(settings, method, payload=None):
    request = urllib.request.Request("https://api.telegram.org/bot" + settings["TELEGRAM_BOT_TOKEN"] + "/" + method, data=json.dumps(payload or {}).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            data = json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError("Telegram " + method + " failed: HTTP " + str(error.code)) from None
    except urllib.error.URLError:
        raise RuntimeError("Telegram " + method + " network request failed") from None
    if not data.get("ok"):
        raise RuntimeError("Telegram " + method + " rejected the request")
    return data["result"]


def run(*args, input_text=None):
    result = subprocess.run(["wrangler", *args, "--config", str(ROOT / "worker/wrangler.toml")], cwd=ROOT, input=input_text, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    # Wrangler output contains secret names, not secret values.
    print(result.stdout, end="")
    if result.returncode:
        raise RuntimeError("Wrangler operation failed")
    return result.stdout


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Do not print urllib request objects or tracebacks containing credential URLs.
        print(str(error) if isinstance(error, RuntimeError) else "Configuration failed: " + type(error).__name__, file=sys.stderr)
        sys.exit(1)
