#!/usr/bin/env bash
set -e

# If there are exactly 3 tiling windows on the focused workspace:
# - Left and right windows become 25% each
# - Center window becomes 50%

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

# Find leftmost window by walking focus left until it no longer changes.
"$AEROSPACE" focus --window-id "${tiling_window_ids[0]}" >/dev/null 2>&1 || exit 0
while true; do
  prev_id="$(focused_id)"
  "$AEROSPACE" focus left >/dev/null 2>&1 || true
  curr_id="$(focused_id)"
  [[ -n "$curr_id" ]] || break
  if [[ "$curr_id" == "$prev_id" ]]; then
    break
  fi
done

left_id="$(focused_id)"
if [[ -z "$left_id" ]]; then
  exit 0
fi

ordered_ids=("$left_id")
for _ in 1 2; do
  prev_id="$(focused_id)"
  "$AEROSPACE" focus right >/dev/null 2>&1 || true
  curr_id="$(focused_id)"
  [[ -n "$curr_id" ]] || break
  if [[ "$curr_id" == "$prev_id" ]]; then
    break
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

outer_left="${AEROSPACE_GAP_OUTER_LEFT:-20}"
outer_right="${AEROSPACE_GAP_OUTER_RIGHT:-40}"
inner_horizontal="${AEROSPACE_GAP_INNER_HORIZONTAL:-20}"

if ! [[ "$outer_left" =~ ^[0-9]+$ ]]; then
  outer_left=0
fi
if ! [[ "$outer_right" =~ ^[0-9]+$ ]]; then
  outer_right=0
fi
if ! [[ "$inner_horizontal" =~ ^[0-9]+$ ]]; then
  inner_horizontal=0
fi

usable_width=$((screen_visible_width - outer_left - outer_right - 2 * inner_horizontal))
if ((usable_width <= 0)); then
  exit 0
fi

# Starting from 3 equal columns, shrink left and right by 1/12 of total width each:
# 1/3 - 1/12 = 1/4 (side columns), center becomes 1/2.
shrink_amount=$((usable_width / 12))
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
