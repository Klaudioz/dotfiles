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
SETTLE_COOLDOWN_SECONDS="${SETTLE_COOLDOWN_SECONDS:-60}"

RUNTIME_STATE_DIR="/tmp"
if [[ -n "${HOME:-}" ]]; then
  candidate_dir="${HOME}/Library/Caches/aerospace"
  mkdir -p "$candidate_dir" >/dev/null 2>&1 || true
  if [[ -d "$candidate_dir" ]]; then
    RUNTIME_STATE_DIR="$candidate_dir"
  fi
fi

WATCH_LOCK_DIR="${RUNTIME_STATE_DIR}/aerospace-zoom-popup-sweeper.watch.lock"
SETTLE_STATE_FILE="${RUNTIME_STATE_DIR}/aerospace-zoom-popup-sweeper.last-settle-at"

list_controls_bubble_ids() {
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
  let owner = s(info[kCGWindowOwnerName as String]).lowercased()
  if !owner.contains("zoom") { continue }

  let name = s(info[kCGWindowName as String]).lowercased()
  if !name.isEmpty { continue }

  let windowNumber = info[kCGWindowNumber as String] as? Int ?? -1
  if windowNumber <= 0 { continue }

  let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
  let w = Int(num(bounds["Width"]))
  let h = Int(num(bounds["Height"]))
  if w <= 0 || h <= 0 { continue }

  let isRoundBubble = w <= 140 && h <= 140
  let isThinStrip = w <= 180 && h <= 40
  if isRoundBubble || isThinStrip {
    print(windowNumber)
  }
}
SWIFT
  )" 2>/dev/null || true
}

list_overlay_window_ids() {
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
  let owner = s(info[kCGWindowOwnerName as String]).lowercased()
  if !owner.contains("zoom") { continue }

  let name = s(info[kCGWindowName as String]).lowercased()
  let windowNumber = info[kCGWindowNumber as String] as? Int ?? -1
  if windowNumber <= 0 { continue }

  let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
  let w = Int(num(bounds["Width"]))
  let h = Int(num(bounds["Height"]))
  if w <= 0 || h <= 0 { continue }

  // Zoom's sticky "meeting controls" bubble is unnamed and tiny (often 56x56).
  // Other problematic overlays are also unnamed/small.
  let isTinyBubble = name.isEmpty && w <= 120 && h <= 120
  let isSmallNamelessPanel = name.isEmpty && w <= 500 && h <= 220
  let isKnownOverlay = name.contains("annotation entrypoint")
    || name.contains("floating video")
    || name.contains("hud")
  if isTinyBubble || isSmallNamelessPanel || isKnownOverlay {
    print(windowNumber)
  }
}
SWIFT
  )" 2>/dev/null || true
}

disable_zoom_always_show_meeting_controls() {
  [[ -n "${OSASCRIPT_BIN:-}" ]] || return 0
  "$OSASCRIPT_BIN" >/dev/null 2>&1 <<'APPLESCRIPT' || true
tell application "System Events"
  if not (exists application process "zoom.us") then return
  tell process "zoom.us"
    if not (exists menu bar item "Window" of menu bar 1) then return
    tell menu 1 of menu bar item "Window" of menu bar 1
      if exists menu item "Always Show Meeting Controls" then
        click menu item "Always Show Meeting Controls"
      end if
    end tell
  end tell
end tell
APPLESCRIPT
}

settle_zoom_controls() {
  local focused_workspace zoom_line zoom_window_id
  focused_workspace="$("$AEROSPACE" list-workspaces --focused 2>/dev/null || true)"
  zoom_line="$("$AEROSPACE" list-windows --all --format '%{window-id} %{app-name}' 2>/dev/null | awk 'tolower($2) ~ /zoom/ { print; exit }')"
  zoom_window_id="$(awk '{print $1}' <<<"$zoom_line")"
  [[ -n "${zoom_window_id:-}" ]] || return 0

  "$AEROSPACE" focus --window-id "$zoom_window_id" >/dev/null 2>&1 || true
  disable_zoom_always_show_meeting_controls
  hide_zoom_overlay_panels

  if [[ -n "${focused_workspace:-}" ]]; then
    "$AEROSPACE" workspace "$focused_workspace" >/dev/null 2>&1 || true
  fi
}

maybe_settle_zoom_controls() {
  local now last=0
  now="$(date +%s)"

  if [[ -f "$SETTLE_STATE_FILE" ]]; then
    last="$(cat "$SETTLE_STATE_FILE" 2>/dev/null || echo 0)"
  fi
  if [[ ! "$last" =~ ^[0-9]+$ ]]; then
    last=0
  fi
  if (( now - last < SETTLE_COOLDOWN_SECONDS )); then
    return 0
  fi

  settle_zoom_controls
  printf '%s' "$now" >"$SETTLE_STATE_FILE"
}

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

      if (n is missing value) then
        set ww to item 1 of s
        set hh to item 2 of s
        if (ww >= 20) and (ww <= 500) and (hh >= 20) and (hh <= 220) then
          set position of w to {-10000, -10000}
        end if
      end if
    end repeat
  end tell
end tell
APPLESCRIPT
}

list_popup_window_ids() {
  list_overlay_window_ids
}

sweep_once() {
  local bubble_ids
  bubble_ids="$(list_controls_bubble_ids)"
  if [[ -n "${bubble_ids:-}" ]]; then
    maybe_settle_zoom_controls
  fi

  local ids
  ids="$(list_popup_window_ids)"
  if [[ -n "${ids:-}" ]]; then
    disable_zoom_always_show_meeting_controls
    hide_zoom_overlay_panels
  fi
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
      if ps -p "$old_pid" -o command= 2>/dev/null | rg -q "zoom-popup-sweeper.sh watch"; then
        exit 0
      fi
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
