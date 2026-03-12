#!/usr/bin/env bash
set -e

# Focus the workspace by its compact visible number so keyboard navigation
# matches the Sketchybar workspace labels when empty workspaces are hidden.
# Keep the non-empty workspace detection aligned with
# sketchybar/plugins/spaces/aerospace/script-space.sh.

AEROSPACE="${AEROSPACE_BIN:-/opt/homebrew/bin/aerospace}"
if [[ ! -x "$AEROSPACE" ]]; then
  AEROSPACE="aerospace"
fi

target_workspace="${1:-}"
if [[ ! "$target_workspace" =~ ^[0-9]+$ ]]; then
  echo "Usage: $(basename "$0") <workspace-number>" >&2
  exit 2
fi

COMPACT_WORKSPACES="${SKETCHYBAR_AEROSPACE_COMPACT_WORKSPACES:-1}"

resolve_workspace_id() {
  local display_workspace_id="$1"

  if [[ "${COMPACT_WORKSPACES}" != "1" ]] && [[ "${COMPACT_WORKSPACES}" != "true" ]]; then
    printf '%s\n' "$display_workspace_id"
    return 0
  fi

  local focused_workspace non_empty_workspaces workspaces all_numeric
  focused_workspace="$("$AEROSPACE" list-workspaces --focused 2>/dev/null || true)"
  non_empty_workspaces=$(
    "$AEROSPACE" list-windows --monitor all --format '%{workspace}%{tab}%{app-bundle-id}%{tab}%{window-layout}' 2>/dev/null |
      awk -F '\t' '
        NF < 3 { next }
        {
          ws = $1
          id = $2
          layout = $3
        }
        ws == "" { next }
        layout == "floating" {
          if (id ~ /^com\\.1password\\./ ||
              id == "com.apple.SecurityAgent" ||
              id == "com.apple.authorizationhost" ||
              id == "com.apple.LocalAuthentication.UIAgent" ||
              id == "com.apple.coreservices.uiagent" ||
              id == "com.apple.IOUIAgent" ||
              id == "com.apple.NetAuthAgent") {
            print ws
          }
          next
        }
        { print ws }
      ' | sort -u
  )

  workspaces=$(
    {
      printf '%s\n' "$non_empty_workspaces"
      printf '%s\n' "$focused_workspace"
    } | awk 'NF' | sort -u
  )

  if [[ -z "$workspaces" ]]; then
    printf '%s\n' "$display_workspace_id"
    return 0
  fi

  all_numeric=$(
    printf '%s\n' "$workspaces" | awk '!/^[0-9]+$/ { bad=1 } END { if (bad) print 0; else print 1 }'
  )
  if [[ "$all_numeric" != "1" ]]; then
    printf '%s\n' "$display_workspace_id"
    return 0
  fi

  local idx=0
  local ws
  while IFS= read -r ws; do
    [[ -n "$ws" ]] || continue
    idx=$((idx + 1))
    if [[ "$idx" -eq "$display_workspace_id" ]]; then
      printf '%s\n' "$ws"
      return 0
    fi
  done <<<"$(printf '%s\n' "$workspaces" | sort -n)"

  printf '%s\n' "$display_workspace_id"
}

resolved_workspace="$(resolve_workspace_id "$target_workspace")"
"$AEROSPACE" workspace "$resolved_workspace" >/dev/null 2>&1 || exit 0
