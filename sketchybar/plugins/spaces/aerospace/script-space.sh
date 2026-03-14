#!/usr/bin/env bash
# Source: github.com/Kcraft059/sketchybar-config

WORKSPACE_ID=${1:-${NAME#space.}}

RELPATH="$HOME/.config/sketchybar"
source "$RELPATH/colors.sh"

COMPACT_WORKSPACES="${SKETCHYBAR_AEROSPACE_COMPACT_WORKSPACES:-1}"

compact_workspace_label() {
    local workspace_id="$1"

    if [[ "${COMPACT_WORKSPACES}" != "1" ]] && [[ "${COMPACT_WORKSPACES}" != "true" ]]; then
        printf '%s' "$workspace_id"
        return 0
    fi

    local focused_workspace non_empty_workspaces workspaces all_numeric
    focused_workspace=$(aerospace list-workspaces --focused 2>/dev/null || true)
    non_empty_workspaces=$(
        aerospace list-windows --monitor all --format '%{workspace}%{tab}%{app-bundle-id}%{tab}%{window-layout}' 2>/dev/null |
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
                        id == "com.apple.finder" ||
                        id == "com.apple.FaceTime" ||
                        id == "com.apple.mail" ||
                        id == "com.apple.iCal" ||
                        id == "com.apple.QuickTimePlayerX" ||
                        id == "com.apple.SecurityAgent" ||
                        id == "com.apple.authorizationhost" ||
                        id == "com.apple.LocalAuthentication.UIAgent" ||
                        id == "com.apple.coreservices.uiagent" ||
                        id == "com.apple.IOUIAgent" ||
                        id == "com.apple.NetAuthAgent" ||
                        id == "com.apple.systempreferences" ||
                        id == "com.macpaw.clearvpn.macos-setapp" ||
                        id == "com.macpaw.CleanMyMac-setapp" ||
                        id == "com.electron.wispr-flow" ||
                        id == "com.naotanhaocan.BetterMouse" ||
                        id == "com.witt-software.Rocket-Typist-setapp" ||
                        id == "us.zoom.xos") {
                        next
                    }
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
        printf '%s' "$workspace_id"
        return 0
    fi

    all_numeric=$(
        printf '%s\n' "$workspaces" | awk '!/^[0-9]+$/ { bad=1 } END { if (bad) print 0; else print 1 }'
    )
    if [[ "$all_numeric" != "1" ]]; then
        printf '%s' "$workspace_id"
        return 0
    fi

    local idx=0
    while IFS= read -r ws; do
        [[ -n "$ws" ]] || continue
        idx=$((idx + 1))
        if [[ "$ws" == "$workspace_id" ]]; then
            printf '%s' "$idx"
            return 0
        fi
    done <<<"$(printf '%s\n' "$workspaces" | sort -n)"

    printf '%s' "$workspace_id"
}

FOCUSED_WORKSPACE=$(aerospace list-workspaces --focused 2>/dev/null)

if [ "$FOCUSED_WORKSPACE" = "$WORKSPACE_ID" ]; then
    SELECTED="true"
else
    SELECTED="false"
fi

DISPLAY_WORKSPACE_ID="$(compact_workspace_label "$WORKSPACE_ID")"

update() {
    if [ "$SELECTED" = "true" ]; then
        sketchybar --animate tanh 20 --set $NAME \
            icon="$DISPLAY_WORKSPACE_ID" \
            icon.highlight=true \
            icon.color=0xff1e1e2e \
            background.color=0xffcba6f7 \
            background.drawing=on
    else
        sketchybar --animate tanh 20 --set $NAME \
            icon="$DISPLAY_WORKSPACE_ID" \
            icon.highlight=false \
            icon.color=0xff6c7086 \
            background.color=0xff313244
    fi
}

mouse_clicked() {
    if [ "$BUTTON" = "right" ]; then
        echo "Right click on aerospace workspace not supported"
    else
        aerospace workspace "$WORKSPACE_ID" 2>/dev/null
    fi
}

case "$SENDER" in
"mouse.clicked")
    mouse_clicked
    ;;
"mouse.entered")
    ;;
*)
    "$RELPATH/plugins/spaces/aerospace/script-windows.sh" "$WORKSPACE_ID"
    update
    ;;
esac
