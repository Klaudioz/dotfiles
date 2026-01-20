#!/usr/bin/env bash
set -e

# Master layout: focus the window you want bigger, press alt-m
# Balances sizes first, then enlarges focused window by MASTER_RESIZE_AMOUNT pixels

AEROSPACE="/opt/homebrew/bin/aerospace"
if [[ ! -x "$AEROSPACE" ]]; then
  AEROSPACE="aerospace"
fi

MASTER_RESIZE_AMOUNT="${MASTER_RESIZE_AMOUNT:-400}"

focused_window_id="$("$AEROSPACE" list-windows --focused --format '%{window-id}' 2>/dev/null || true)"
[[ -n "$focused_window_id" ]] || exit 0

"$AEROSPACE" balance-sizes >/dev/null 2>&1 || true
sleep 0.05
"$AEROSPACE" resize smart +"$MASTER_RESIZE_AMOUNT" >/dev/null 2>&1 || true
