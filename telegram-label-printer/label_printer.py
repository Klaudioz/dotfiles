#!/usr/bin/env python3
"""
Telegram Label Printer Daemon
Polls the R2 print-queue/ for PDF labels and prints them
automatically using the scale-pdf + lp pipeline (85% scale).

The Cloudflare worker uploads label PDFs to R2 print-queue/ when
sending them to Telegram. This daemon picks them up, prints, and
deletes them from R2.
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
from typing import Optional

PRINTER = os.environ.get("LABEL_PRINTER", "EPSON_L1250_Series")
SCALE = os.environ.get("LABEL_SCALE", "0.85")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "10"))
CF_ACCOUNT_ID = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "")
CF_API_TOKEN = os.environ.get("CLOUDFLARE_API_TOKEN", "")
R2_BUCKET = os.environ.get("R2_BUCKET", "pepchile-images")
R2_PREFIX = "print-queue/"
R2_CUSTOM_DOMAIN = os.environ.get("R2_CUSTOM_DOMAIN", "images.pepchile.com")
SCALER_BIN = os.path.expanduser("~/dotfiles/automator-services/scale-pdf")


def log(msg: str) -> None:
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def cf_api(method: str, path: str, body: bytes | None = None) -> dict:
    url = f"https://api.cloudflare.com/client/v4/accounts/{CF_ACCOUNT_ID}/{path}"
    req = urllib.request.Request(url, method=method, data=body)
    req.add_header("Authorization", f"Bearer {CF_API_TOKEN}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def list_print_queue() -> list[dict]:
    """List objects in R2 print-queue/ prefix."""
    path = f"r2/buckets/{R2_BUCKET}/objects?prefix={R2_PREFIX}&delimiter=/"
    data = cf_api("GET", path)
    objects = data.get("result", {}).get("objects", [])
    return [obj for obj in objects if obj.get("key", "").endswith(".pdf")]


def download_from_r2(key: str, dest: str) -> None:
    """Download a file from R2 via custom domain."""
    url = f"https://{R2_CUSTOM_DOMAIN}/{key}"
    urllib.request.urlretrieve(url, dest)


def delete_from_r2(key: str) -> None:
    """Delete a file from R2."""
    path = f"r2/buckets/{R2_BUCKET}/objects/{key}"
    cf_api("DELETE", path)


def print_pdf(pdf_path: str) -> bool:
    """Scale to 85% and send to printer."""
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


def process_label(obj: dict) -> None:
    key = obj["key"]
    filename = key.replace(R2_PREFIX, "")
    log(f"Label found: {filename}")

    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        download_from_r2(key, tmp_path)
        if print_pdf(tmp_path):
            log(f"PRINTED: {filename}")
            delete_from_r2(key)
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
    if not CF_ACCOUNT_ID or not CF_API_TOKEN:
        log("ERROR: CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN must be set")
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
