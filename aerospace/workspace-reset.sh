#!/usr/bin/env bash
set -e

# Reset the focused workspace to a sane tiling layout:
# - Keep known helper/dialog windows floating
# - Force other windows to tiling (undo accidental floating)
# - Flatten the workspace tree
# - Set layout to horizontal tiles

AEROSPACE="/opt/homebrew/bin/aerospace"
if [[ ! -x "$AEROSPACE" ]]; then
  AEROSPACE="aerospace"
fi

should_float_window() {
  local app_id="$1"
  local window_title="${2:-}"

  case "$app_id" in
    com.apple.finder | \
      com.apple.FaceTime | \
      com.apple.mail | \
      com.apple.QuickTimePlayerX | \
      com.apple.SecurityAgent | \
      com.apple.authorizationhost | \
      com.apple.coreservices.uiagent | \
      com.apple.IOUIAgent | \
      com.apple.LocalAuthentication.UIAgent | \
      com.apple.NetAuthAgent | \
      com.apple.systempreferences | \
      com.electron.wispr-flow | \
      com.naotanhaocan.BetterMouse | \
      com.witt-software.Rocket-Typist-setapp)
      return 0
      ;;
  esac

  local title_lc=""
  title_lc="$(printf '%s' "$window_title" | tr '[:upper:]' '[:lower:]')"

  if [[ "$app_id" == "com.1password.1password" && "$title_lc" == *"quick access"* ]]; then
    return 0
  fi

  if [[ "$title_lc" == *"1password access requested"* ]]; then
    return 0
  fi

  if [[ "$title_lc" == *"settings"* || "$title_lc" == *"preferences"* ]]; then
    return 0
  fi

  if [[ "$title_lc" == *"password"* || "$title_lc" == *"authenticate"* || "$title_lc" == *"authorization"* ]]; then
    return 0
  fi

  return 1
}

focused_window_id="$("$AEROSPACE" list-windows --focused --format '%{window-id}' 2>/dev/null || true)"
if [[ -z "$focused_window_id" ]]; then
  first_window_id="$("$AEROSPACE" list-windows --workspace focused --format '%{window-id}' 2>/dev/null | head -n 1 || true)"
  if [[ -z "$first_window_id" ]]; then
    exit 0
  fi
  "$AEROSPACE" focus --window-id "$first_window_id" >/dev/null 2>&1 || exit 0
fi

while IFS=$'\t' read -r window_id app_id window_title; do
  [[ -n "$window_id" ]] || continue
  if should_float_window "$app_id" "$window_title"; then
    "$AEROSPACE" layout --window-id "$window_id" floating >/dev/null 2>&1 || true
  else
    "$AEROSPACE" layout --window-id "$window_id" tiling >/dev/null 2>&1 || true
  fi
done < <(
  "$AEROSPACE" list-windows --workspace focused --format '%{window-id}%{tab}%{app-bundle-id}%{tab}%{window-title}' 2>/dev/null || true
)

"$AEROSPACE" flatten-workspace-tree >/dev/null 2>&1 || true
"$AEROSPACE" layout tiles horizontal >/dev/null 2>&1 || true
"$AEROSPACE" balance-sizes >/dev/null 2>&1 || true
