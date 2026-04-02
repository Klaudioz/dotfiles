#!/usr/bin/env python3
"""
Niimbot B1 Starken Shipping Label Printer Daemon
Polls pepchile.com admin API for Starken shipping label jobs in the R2 starken-queue,
renders label PNGs with customer info, prints via BLE using the B1 protocol,
and removes from queue.

B1 Protocol requirements (different from D11):
- printStart7b (7-byte), setPageSize6b (6-byte)
- All BLE writes use writeWithoutResponse
- Dummy GetPrintStatus after PrintStart (B1 drops first BLE packet)
- All rows as PrintBitmapRow (0x85), never PrintEmptyRow (0x84)
- Poll GetPrintStatus until finished BEFORE EndPrint
"""

from __future__ import annotations

import asyncio
import json
import math
import os
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request

from PIL import Image, ImageOps

# Add niimprint to path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
NIIMPRINT_DIR = os.path.join(os.path.expanduser("~"), "dotfiles", "niimbot-vial-printer", "niimprint")
sys.path.insert(0, NIIMPRINT_DIR)

from niimprint.printer import NiimbotPacket  # noqa: E402

# Config from env
NIIMBOT_ADDR = os.environ.get("NIIMBOT_B1_ADDR", "10193FDD-6171-CC1B-27B4-F49D20566DC5")
PRINT_DENSITY = int(os.environ.get("B1_PRINT_DENSITY", "5"))
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "10"))
API_BASE = os.environ.get("API_BASE", "https://pepchile.com")
ADMIN_SECRET = os.environ.get("ADMIN_SECRET", "")
RENDER_SCRIPT = os.path.join(
    os.path.expanduser("~"), "projects", "sites", "pepchile.com", "niimbot", "render_starken_label.py"
)

BLE_CHAR = "bef8d6c9-9c21-4c9e-b632-bd58c1009f9f"


def log(msg: str) -> None:
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def admin_request(method: str, path: str) -> urllib.request.Request:
    url = f"{API_BASE}{path}"
    req = urllib.request.Request(url, method=method)
    req.add_header("X-Admin-Secret", ADMIN_SECRET)
    req.add_header("User-Agent", "PepChile-StarkenPrinter/1.0")
    return req


def admin_api(method: str, path: str) -> dict:
    req = admin_request(method, path)
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def list_starken_queue() -> list[dict]:
    data = admin_api("GET", "/api/admin/print-queue?type=starken")
    return data.get("files", [])


def download_job(key: str) -> dict:
    encoded_key = urllib.request.quote(key, safe="")
    req = admin_request("GET", f"/api/admin/print-queue?type=starken&key={encoded_key}")
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def delete_from_queue(key: str) -> None:
    encoded_key = urllib.request.quote(key, safe="")
    admin_api("DELETE", f"/api/admin/print-queue?key={encoded_key}")


def render_label(job: dict) -> str:
    """Render a shipping label PNG and return the file path."""
    import tempfile

    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    tmp.close()

    cmd = [
        sys.executable, RENDER_SCRIPT,
        "--name", job.get("customerName", ""),
        "--address", job.get("shippingAddress", ""),
        "--city", job.get("shippingCity", ""),
        "--region", job.get("shippingRegion", ""),
        "--phone", job.get("customerPhone", ""),
        "--email", job.get("customerEmail", ""),
        "-o", tmp.name,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        os.unlink(tmp.name)
        raise RuntimeError(f"render failed: {result.stderr}")
    return tmp.name


def count_black_pixels(data_bytes: bytes) -> int:
    return sum(bin(b).count("1") for b in data_bytes)


async def print_label_b1(image_path: str) -> bool:
    """Print a label on the Niimbot B1 using the B1-specific BLE protocol."""
    from bleak import BleakClient

    image = Image.open(image_path)
    img = ImageOps.invert(image.convert("L")).convert("1")
    width, height = img.size

    recv_buffer = bytearray()

    def on_notify(char, data):
        recv_buffer.extend(data)

    try:
        client = BleakClient(NIIMBOT_ADDR)
        await client.connect()
        await client.start_notify(BLE_CHAR, on_notify)
        await asyncio.sleep(0.5)

        async def send_cmd(reqcode, data):
            recv_buffer.clear()
            pkt = NiimbotPacket(reqcode, data)
            await client.write_gatt_char(BLE_CHAR, pkt.to_bytes(), response=False)
            await asyncio.sleep(0.1)

        # B1 protocol sequence
        await send_cmd(0x21, bytes((PRINT_DENSITY,)))  # density
        await send_cmd(0x23, bytes((1,)))  # label type
        await send_cmd(0x01, struct.pack(">H", 1) + b"\x00\x00\x00\x00\x00")  # printStart7b
        await send_cmd(0xA3, b"\x01")  # dummy GetPrintStatus (B1 drops first packet)
        await asyncio.sleep(0.1)
        await send_cmd(0x03, b"\x01")  # pageStart
        await send_cmd(0x13, struct.pack(">HHH", height, width, 1))  # setPageSize6b

        # Send all rows as PrintBitmapRow (0x85)
        for y in range(height):
            line_data = [img.getpixel((x, y)) for x in range(width)]
            line_str = "".join("0" if pix == 0 else "1" for pix in line_data)
            line_bytes = int(line_str, 2).to_bytes(math.ceil(width / 8), "big")
            black_count = count_black_pixels(line_bytes)
            count_parts = bytes([0, black_count & 0xFF, (black_count >> 8) & 0xFF])
            header = struct.pack(">H", y) + count_parts + bytes([1])
            pkt = NiimbotPacket(0x85, header + line_bytes)
            await client.write_gatt_char(BLE_CHAR, pkt.to_bytes(), response=False)
            await asyncio.sleep(0.05)

        # End page
        await send_cmd(0xE3, b"\x01")

        # Poll GetPrintStatus until finished BEFORE EndPrint
        for attempt in range(100):
            recv_buffer.clear()
            pkt = NiimbotPacket(0xA3, b"\x01")
            await client.write_gatt_char(BLE_CHAR, pkt.to_bytes(), response=False)
            await asyncio.sleep(0.5)

            resp = bytes(recv_buffer)
            idx = resp.find(b"\x55\x55")
            if idx >= 0 and len(resp) > idx + 4:
                data_len = resp[idx + 3]
                data = resp[idx + 4 : idx + 4 + data_len]
                if len(data) >= 2 and data[0] == 1:
                    break
            await asyncio.sleep(0.5)

        # Send EndPrint
        for _ in range(20):
            recv_buffer.clear()
            pkt = NiimbotPacket(0xF3, b"\x01")
            await client.write_gatt_char(BLE_CHAR, pkt.to_bytes(), response=False)
            await asyncio.sleep(0.5)
            if recv_buffer and len(recv_buffer) >= 5 and recv_buffer[4] == 1:
                break

        await client.disconnect()
        return True

    except Exception as e:
        log(f"  BLE error: {e}")
        return False


def print_label_sync(image_path: str) -> bool:
    """Synchronous wrapper for the async BLE print function."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(print_label_b1(image_path))
    finally:
        loop.close()


def process_job(entry: dict) -> None:
    key = entry["key"]
    filename = key.replace("starken-queue/", "")
    log(f"Job found: {filename}")

    try:
        job = download_job(key)
    except Exception as e:
        log(f"ERROR downloading job {filename}: {e}")
        return

    order_id = job.get("orderId", "unknown")
    log(f"Rendering label for {order_id}: {job.get('customerName', '?')}")

    try:
        image_path = render_label(job)
    except Exception as e:
        log(f"ERROR rendering label for {order_id}: {e}")
        delete_from_queue(key)
        return

    try:
        if print_label_sync(image_path):
            log(f"PRINTED: {order_id}")
            delete_from_queue(key)
            log(f"Removed from queue: {filename}")
        else:
            log(f"FAILED to print {order_id} (will retry next cycle)")
    finally:
        try:
            os.unlink(image_path)
        except OSError:
            pass


def main() -> None:
    if not ADMIN_SECRET:
        log("ERROR: ADMIN_SECRET not set")
        sys.exit(1)

    log(f"Starting Starken label printer daemon (addr={NIIMBOT_ADDR}, poll={POLL_INTERVAL}s)")

    while True:
        try:
            jobs = list_starken_queue()
            if jobs:
                for job in jobs:
                    process_job(job)
        except urllib.error.URLError as e:
            log(f"Network error: {e}")
        except Exception as e:
            log(f"Unexpected error: {e}")

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
