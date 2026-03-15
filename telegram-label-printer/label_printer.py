#!/usr/bin/env python3
"""
Telegram Label Printer Daemon
Polls pepchile.com admin API for label PDFs in the R2 print queue,
downloads them, scales to 85%, prints, and removes from queue.
"""

from __future__ import annotations

import os
import sys
import subprocess
import tempfile
import time
import urllib.request
import urllib.error
import json

PRINTER = os.environ.get("LABEL_PRINTER", "EPSON_L1250_Series")
SCALE = os.environ.get("LABEL_SCALE", "0.85")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "10"))
API_BASE = os.environ.get("API_BASE", "https://pepchile.com")
ADMIN_SECRET = os.environ.get("ADMIN_SECRET", "")
R2_DOMAIN = os.environ.get("R2_DOMAIN", "https://images.pepchile.com")
SCALER_BIN = os.path.expanduser("~/dotfiles/automator-services/scale-pdf")


def log(msg: str) -> None:
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def admin_api(method: str, path: str) -> dict:
    url = f"{API_BASE}{path}"
    req = urllib.request.Request(url, method=method)
    req.add_header("X-Admin-Secret", ADMIN_SECRET)
    req.add_header("User-Agent", "PepChile-LabelPrinter/1.0")
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def list_print_queue() -> list[dict]:
    data = admin_api("GET", "/api/admin/print-queue")
    return data.get("files", [])


def delete_from_queue(key: str) -> None:
    encoded_key = urllib.request.quote(key, safe="")
    admin_api("DELETE", f"/api/admin/print-queue?key={encoded_key}")


def download_from_r2(key: str, dest: str) -> None:
    url = f"{R2_DOMAIN}/{key}"
    urllib.request.urlretrieve(url, dest)


def print_pdf(pdf_path: str) -> bool:
    if not os.path.isfile(SCALER_BIN):
        log(f"ERROR: scale-pdf binary not found at {SCALER_BIN}")
        return False

    result = subprocess.run(
        [SCALER_BIN, pdf_path, SCALE],
        capture_output=True, text=True
    )
    scaled_path = result.stdout.strip()

    if result.returncode != 0 or not scaled_path or not os.path.isfile(scaled_path):
        log(f"ERROR: scale-pdf failed: {result.stderr}")
        return False

    try:
        lp_result = subprocess.run(
            ["/usr/bin/lp", "-d", PRINTER, "-o", "print-quality=3", scaled_path],
            capture_output=True, text=True
        )
        if lp_result.returncode != 0:
            log(f"ERROR: lp failed: {lp_result.stderr}")
            return False
        return True
    finally:
        try:
            os.unlink(scaled_path)
        except OSError:
            pass


def process_label(label: dict) -> None:
    key = label["key"]
    filename = key.replace("print-queue/", "")
    log(f"Label found: {filename}")

    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        download_from_r2(key, tmp_path)
        if print_pdf(tmp_path):
            log(f"PRINTED: {filename}")
            delete_from_queue(key)
            log(f"Removed from queue: {filename}")
        else:
            log(f"FAILED to print: {filename} (will retry next cycle)")
    except Exception as e:
        log(f"ERROR processing {filename}: {e}")
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def main() -> None:
    if not ADMIN_SECRET:
        log("ERROR: ADMIN_SECRET not set")
        sys.exit(1)

    log(f"Starting label printer daemon (printer={PRINTER}, scale={SCALE}, poll={POLL_INTERVAL}s)")

    while True:
        try:
            labels = list_print_queue()
            for label in labels:
                process_label(label)
        except urllib.error.URLError as e:
            log(f"Network error: {e}")
        except Exception as e:
            log(f"Unexpected error: {e}")

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
