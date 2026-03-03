#!/usr/bin/env bash
set -e

# Close annoying Zoom popup windows (e.g. "zoom annotation entrypoint") that can steal focus / change workspaces.

AEROSPACE="/opt/homebrew/bin/aerospace"
if [[ ! -x "$AEROSPACE" ]]; then
  AEROSPACE="aerospace"
fi

OSASCRIPT_BIN="/usr/bin/osascript"
if [[ ! -x "$OSASCRIPT_BIN" ]]; then
  OSASCRIPT_BIN="$(command -v osascript 2>/dev/null || true)"
fi

SWIFT_BIN="/usr/bin/swift"
if [[ ! -x "$SWIFT_BIN" ]]; then
  SWIFT_BIN="$(command -v swift 2>/dev/null || true)"
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

hide_zoom_overlay_panels() {
  # Zoom spawns a small, unnamed panel window (e.g. ~247x45) that can appear
  # across workspaces and steal focus (clicking it often jumps to the Zoom
  # workspace). AeroSpace doesn't manage this window, so we hide it by moving it
  # far off-screen via Accessibility.
  [[ -n "${OSASCRIPT_BIN:-}" ]] || return 0
  "$OSASCRIPT_BIN" >/dev/null 2>&1 <<'APPLESCRIPT' || true
tell application "System Events"
  if not (exists application process "zoom.us") then return
  tell process "zoom.us"
    repeat with w in windows
      set n to name of w
      set sr to ""
      try
        set sr to subrole of w
      end try
      set s to size of w

      if (n is missing value) and (sr is "") then
        set ww to item 1 of s
        set hh to item 2 of s
        if (ww >= 150) and (ww <= 450) and (hh >= 20) and (hh <= 90) then
          set position of w to {-10000, -10000}
        end if
      end if
    end repeat
  end tell
end tell
APPLESCRIPT
}

list_popup_window_ids() {
  [[ -n "${SWIFT_BIN:-}" ]] || return 0
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
}
SWIFT
  )" 2>/dev/null || true
}

sweep_once() {
  hide_zoom_overlay_panels

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
