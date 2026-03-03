#!/usr/bin/env bash
set -e

# Close annoying Zoom popup windows (e.g. "zoom annotation entrypoint") that can steal focus / change workspaces.

AEROSPACE="/opt/homebrew/bin/aerospace"
if [[ ! -x "$AEROSPACE" ]]; then
  AEROSPACE="aerospace"
fi

SWIFT_BIN="/usr/bin/swift"
if [[ ! -x "$SWIFT_BIN" ]]; then
  SWIFT_BIN="$(command -v swift 2>/dev/null || true)"
fi
if [[ -z "${SWIFT_BIN:-}" ]]; then
  exit 0
fi

mode="${1:-sweep}"
WATCH_INTERVAL_SECONDS="${WATCH_INTERVAL_SECONDS:-0.5}"

RUNTIME_STATE_DIR="/tmp"
if [[ -n "${HOME:-}" ]]; then
  candidate_dir="${HOME}/Library/Caches/aerospace"
  mkdir -p "$candidate_dir" >/dev/null 2>&1 || true
  if [[ -d "$candidate_dir" ]]; then
    RUNTIME_STATE_DIR="$candidate_dir"
  fi
fi

WATCH_LOCK_DIR="${RUNTIME_STATE_DIR}/aerospace-zoom-popup-sweeper.watch.lock"

list_popup_window_ids() {
  "$SWIFT_BIN" -e "$(
    cat <<'SWIFT'
import Foundation
import CoreGraphics

func s(_ any: Any?) -> String { return any as? String ?? "" }
func num(_ any: Any?) -> Double {
  if let d = any as? Double { return d }
  if let i = any as? Int { return Double(i) }
  if let n = any as? NSNumber { return n.doubleValue }
  return 0
}

let options: CGWindowListOption = [.optionOnScreenOnly]

guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
  exit(0)
}

for info in infoList {
  let owner = s(info[kCGWindowOwnerName as String])
  let ownerLC = owner.lowercased()
  if !ownerLC.contains("zoom") { continue }

  let name = s(info[kCGWindowName as String])
  let nameLC = name.lowercased()
  let windowNumber = info[kCGWindowNumber as String] as? Int ?? -1
  if windowNumber <= 0 { continue }

  if nameLC.contains("annotation entrypoint") {
    print(windowNumber)
    continue
  }

  // Some builds present these popups without a stable window name.
  let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
  let w = Int(num(bounds["Width"]))
  let h = Int(num(bounds["Height"]))
  if name.isEmpty && w > 0 && h > 0 && w <= 800 && h <= 240 {
    // Avoid the main meeting window (usually titled), but be extra safe anyway.
    if !nameLC.contains("zoom meeting") {
      print(windowNumber)
    }
  }
}
SWIFT
  )" 2>/dev/null || true
}

sweep_once() {
  local ids
  ids="$(list_popup_window_ids)"
  [[ -n "${ids:-}" ]] || return 0

  while IFS= read -r win_id; do
    [[ -n "${win_id:-}" ]] || continue
    if [[ "$win_id" =~ ^[0-9]+$ ]]; then
      "$AEROSPACE" close --window-id "$win_id" >/dev/null 2>&1 || true
    fi
  done <<<"$ids"
}

watch() {
  if ! mkdir "$WATCH_LOCK_DIR" 2>/dev/null; then
    local old_pid=""

    # Handle race: another instance may have created the lock dir but not written pid yet.
    for _ in 1 2 3 4 5; do
      if [[ -f "$WATCH_LOCK_DIR/pid" ]]; then
        break
      fi
      sleep 0.05
    done

    old_pid="$(cat "$WATCH_LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
      exit 0
    fi

    rm -rf "$WATCH_LOCK_DIR" 2>/dev/null || true
    if ! mkdir "$WATCH_LOCK_DIR" 2>/dev/null; then
      exit 0
    fi
  fi

  printf '%s' "$$" >"$WATCH_LOCK_DIR/pid"
  trap 'rm -rf "$WATCH_LOCK_DIR" 2>/dev/null || true' EXIT

  while true; do
    sweep_once
    sleep "$WATCH_INTERVAL_SECONDS"
  done
}

case "$mode" in
  sweep)
    sweep_once
    ;;
  watch)
    watch
    ;;
  *)
    echo "Usage: $0 [sweep|watch]" >&2
    exit 2
    ;;
esac
