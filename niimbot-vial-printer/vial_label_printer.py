#!/usr/bin/env python3
"""
Niimbot D11 Vial Label Printer (on-demand)
Checks pepchile.com admin API for vial label jobs in the R2 vial-queue,
matches to pre-rendered label PNGs, prints via niimprint, and removes from queue.
Run manually: source secrets.env && python vial_label_printer.py
"""

from __future__ import annotations

import os
import sys
import subprocess
import time
import urllib.request
import urllib.error
import json

NIIMBOT_CONN = os.environ.get("NIIMBOT_CONN", "ble")
NIIMBOT_ADDR = os.environ.get("NIIMBOT_ADDR", "")
PRINT_DENSITY = os.environ.get("PRINT_DENSITY", "3")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "10"))
API_BASE = os.environ.get("API_BASE", "https://pepchile.com")
ADMIN_SECRET = os.environ.get("ADMIN_SECRET", "")
LABELS_DIR = os.environ.get("LABELS_DIR", os.path.expanduser(
    "~/projects/sites/pepchile.com/niimbot/labels"
))
PRINT_DELAY = float(os.environ.get("PRINT_DELAY", "2"))

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VENV_PYTHON = os.path.join(SCRIPT_DIR, ".venv", "bin", "python")


def log(msg: str) -> None:
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def admin_request(method: str, path: str) -> urllib.request.Request:
    url = f"{API_BASE}{path}"
    req = urllib.request.Request(url, method=method)
    req.add_header("X-Admin-Secret", ADMIN_SECRET)
    req.add_header("User-Agent", "PepChile-VialPrinter/1.0")
    return req


def admin_api(method: str, path: str) -> dict:
    req = admin_request(method, path)
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def list_vial_queue() -> list[dict]:
    data = admin_api("GET", "/api/admin/print-queue?type=vial")
    return data.get("files", [])


def download_job(key: str) -> dict:
    encoded_key = urllib.request.quote(key, safe="")
    req = admin_request("GET", f"/api/admin/print-queue?type=vial&key={encoded_key}")
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def delete_from_queue(key: str) -> None:
    encoded_key = urllib.request.quote(key, safe="")
    admin_api("DELETE", f"/api/admin/print-queue?key={encoded_key}")



def print_label(image_path: str) -> bool:
    cmd = [
        VENV_PYTHON, "-m", "niimprint",
        "-m", "d11",
        "-c", NIIMBOT_CONN,
        "-d", PRINT_DENSITY,
        "-i", image_path,
    ]
    if NIIMBOT_ADDR:
        cmd.extend(["-a", NIIMBOT_ADDR])

    for attempt in range(3):
        if attempt > 0:
            delay = 2 ** attempt
            log(f"  Retry {attempt}/3 in {delay}s...")
            time.sleep(delay)

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return True
        log(f"  niimprint failed (attempt {attempt + 1}): {result.stderr.strip()}")

    return False


def process_job(entry: dict) -> None:
    key = entry["key"]
    filename = key.replace("vial-queue/", "")
    log(f"Job found: {filename}")

    try:
        job = download_job(key)
    except Exception as e:
        log(f"ERROR downloading job {filename}: {e}")
        return

    product_id = job.get("productId", "")
    quantity = job.get("quantity", 1)
    label_path = os.path.join(LABELS_DIR, f"{product_id}.png")

    if not os.path.isfile(label_path):
        log(f"WARNING: No label PNG for {product_id}, skipping")
        delete_from_queue(key)
        return

    log(f"Printing {quantity}x {product_id}")
    success = True
    for i in range(quantity):
        if i > 0:
            time.sleep(PRINT_DELAY)
        if not print_label(label_path):
            log(f"FAILED to print {product_id} (copy {i + 1}/{quantity})")
            success = False
            break
        log(f"  PRINTED {product_id} ({i + 1}/{quantity})")

    if success:
        delete_from_queue(key)
        log(f"Removed from queue: {filename}")
    else:
        log(f"Job {filename} will retry next cycle")



def main() -> None:
    if not ADMIN_SECRET:
        log("ERROR: ADMIN_SECRET not set")
        sys.exit(1)

    if not NIIMBOT_ADDR:
        log("WARNING: NIIMBOT_ADDR not set, niimprint will try auto-discovery")

    log(f"Checking vial print queue (conn={NIIMBOT_CONN}, addr={NIIMBOT_ADDR})")
    log(f"Labels dir: {LABELS_DIR}")

    try:
        jobs = list_vial_queue()
        if not jobs:
            log("No jobs in queue")
            return
        for job in jobs:
            process_job(job)
    except urllib.error.URLError as e:
        log(f"Network error: {e}")
        sys.exit(1)
    except Exception as e:
        log(f"Unexpected error: {e}")
        sys.exit(1)

    log("Done")


if __name__ == "__main__":
    main()
