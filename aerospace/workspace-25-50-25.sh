#!/usr/bin/env bash
set -e

# If there are exactly 3 tiling windows on the focused workspace:
# - Left and right windows become 27.5% each
# - Center window becomes 45%

AEROSPACE="/opt/homebrew/bin/aerospace"
if [[ ! -x "$AEROSPACE" ]]; then
  AEROSPACE="aerospace"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/workspace-reset.sh"

orig_focused_id="$("$AEROSPACE" list-windows --focused --format '%{window-id}' 2>/dev/null || true)"
orig_focused_layout="$("$AEROSPACE" list-windows --focused --format '%{window-layout}' 2>/dev/null || true)"

mapfile -t tiling_window_ids < <(
  "$AEROSPACE" list-windows --workspace focused --format '%{window-id}%{tab}%{window-layout}' 2>/dev/null |
    awk -F'\t' '$2 != "floating" { print $1 }'
)

if [[ ${#tiling_window_ids[@]} -ne 3 ]]; then
  exit 0
fi

focused_id() {
  "$AEROSPACE" list-windows --focused --format '%{window-id}' 2>/dev/null || true
}

focused_layout() {
  "$AEROSPACE" list-windows --focused --format '%{window-layout}' 2>/dev/null || true
}

focus_next_tiling() {
  local direction="$1"
  local prev_id curr_id curr_layout

  for _ in {1..30}; do
    prev_id="$(focused_id)"
    "$AEROSPACE" focus "$direction" >/dev/null 2>&1 || true
    curr_id="$(focused_id)"
    [[ -n "$curr_id" ]] || return 1
    if [[ "$curr_id" == "$prev_id" ]]; then
      return 1
    fi

    curr_layout="$(focused_layout)"
    if [[ "$curr_layout" != "floating" ]]; then
      return 0
    fi
  done

  return 1
}

# Find leftmost tiling window by walking focus left while skipping floating windows.
"$AEROSPACE" focus --window-id "${tiling_window_ids[0]}" >/dev/null 2>&1 || exit 0
left_id="$(focused_id)"
for _ in {1..30}; do
  prev_tiling_id="$left_id"
  if ! focus_next_tiling left; then
    "$AEROSPACE" focus --window-id "$prev_tiling_id" >/dev/null 2>&1 || true
    break
  fi
  left_id="$(focused_id)"
done

if [[ -z "$left_id" ]]; then
  exit 0
fi

# Collect tiling windows left-to-right, skipping floating windows.
ordered_ids=("$left_id")
for _ in {1..60}; do
  if [[ ${#ordered_ids[@]} -ge 3 ]]; then
    break
  fi
  if ! focus_next_tiling right; then
    break
  fi
  curr_id="$(focused_id)"
  if [[ " ${ordered_ids[*]} " == *" $curr_id "* ]]; then
    continue
  fi
  ordered_ids+=("$curr_id")
done

if [[ ${#ordered_ids[@]} -ne 3 ]]; then
  if [[ -n "$orig_focused_id" && "$orig_focused_layout" != "floating" ]]; then
    "$AEROSPACE" focus --window-id "$orig_focused_id" >/dev/null 2>&1 || true
  fi
  exit 0
fi

left_id="${ordered_ids[0]}"
right_id="${ordered_ids[2]}"

focused_monitor_name="$("$AEROSPACE" list-monitors --focused --format '%{monitor-name}' 2>/dev/null || true)"

screen_visible_width="$(
  AEROSPACE_FOCUSED_MONITOR_NAME="$focused_monitor_name" osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
ObjC.import('Foundation');
ObjC.import('stdlib');

function containsPoint(frame, point) {
  const x = frame.origin.x;
  const y = frame.origin.y;
  const w = frame.size.width;
  const h = frame.size.height;
  return point.x >= x && point.x <= x + w && point.y >= y && point.y <= y + h;
}

const screens = $.NSScreen.screens;
const targetMonitorName = ObjC.unwrap($.getenv('AEROSPACE_FOCUSED_MONITOR_NAME') || '');

let targetScreen = null;
if (targetMonitorName.length > 0) {
  for (let i = 0; i < screens.count; i++) {
    const screen = screens.objectAtIndex(i);
    const name = ObjC.unwrap(screen.localizedName);
    if (name === targetMonitorName) {
      targetScreen = screen;
      break;
    }
  }
}

if (targetScreen === null) {
  const mouseLocation = $.NSEvent.mouseLocation;
  const point = { x: mouseLocation.x, y: mouseLocation.y };

  targetScreen = $.NSScreen.mainScreen;
  for (let i = 0; i < screens.count; i++) {
    const screen = screens.objectAtIndex(i);
    if (containsPoint(screen.frame, point)) {
      targetScreen = screen;
      break;
    }
  }
}

const visibleFrame = targetScreen.visibleFrame;
const width = Math.round(visibleFrame.size.width);
const output = $.NSString.stringWithString(String(width) + '\n');
$.NSFileHandle.fileHandleWithStandardOutput.writeData(output.dataUsingEncoding($.NSUTF8StringEncoding));
JXA
)"

if ! [[ "$screen_visible_width" =~ ^[0-9]+$ ]]; then
  exit 0
fi

toml_config="$script_dir/aerospace.toml"

read_gap_from_toml() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    BEGIN { in_gaps = 0 }
    $0 ~ /^[[]gaps[]]$/ { in_gaps = 1; next }
    in_gaps && $0 ~ /^[[]/ { exit }
    in_gaps {
      line = $0
      sub(/#.*/, "", line)
      gsub(/[ \\t]/, "", line)
      split(line, parts, "=")
      if (parts[1] == key) {
        print parts[2]
        exit
      }
    }
  ' "$file"
}

gap_value() {
  local env_value="$1"
  local key="$2"
  local default="$3"

  local value="$env_value"
  if [[ -z "$value" && -f "$toml_config" ]]; then
    value="$(read_gap_from_toml "$key" "$toml_config")"
  fi

  if [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value"
  else
    echo "$default"
  fi
}

outer_left="$(gap_value "${AEROSPACE_GAP_OUTER_LEFT:-}" "outer.left" 20)"
outer_right="$(gap_value "${AEROSPACE_GAP_OUTER_RIGHT:-}" "outer.right" 40)"
inner_horizontal="$(gap_value "${AEROSPACE_GAP_INNER_HORIZONTAL:-}" "inner.horizontal" 20)"

usable_width=$((screen_visible_width - outer_left - outer_right - 2 * inner_horizontal))
if ((usable_width <= 0)); then
  exit 0
fi

# Starting from 3 equal columns, shrink left and right to get 27.5% / 45% / 27.5%:
# 1/3 - 7/120 = 27.5% (side columns), center becomes 45%.
shrink_amount=$(((usable_width * 7 + 60) / 120))
if ((shrink_amount <= 0)); then
  exit 0
fi

"$AEROSPACE" focus --window-id "$left_id" >/dev/null 2>&1 || exit 0
"$AEROSPACE" resize width -"${shrink_amount}" >/dev/null 2>&1 || true
sleep 0.05

"$AEROSPACE" focus --window-id "$right_id" >/dev/null 2>&1 || exit 0
"$AEROSPACE" resize width -"${shrink_amount}" >/dev/null 2>&1 || true

if [[ -n "$orig_focused_id" && "$orig_focused_layout" != "floating" ]]; then
  "$AEROSPACE" focus --window-id "$orig_focused_id" >/dev/null 2>&1 || true
fi
