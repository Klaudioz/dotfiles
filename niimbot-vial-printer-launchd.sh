#!/usr/bin/env bash
set -e

# Niimbot D11 Vial Label Printer - launchd wrapper script
# Polls pepchile.com vial queue and auto-prints labels on the Niimbot D11

HOME_DIR="${HOME:-/Users/klaudioz}"
SCRIPT_DIR="$HOME_DIR/dotfiles/niimbot-vial-printer"
LOG_FILE="/tmp/niimbot-vial-printer.log"
SECRETS_FILE="$HOME_DIR/.config/niimbot-vial-printer/secrets.env"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# launchd does not inherit the interactive shell PATH
path_additions=(
  /run/current-system/sw/bin
  /opt/homebrew/bin
  /opt/homebrew/sbin
  "$HOME_DIR/.local/bin"
)

for dir in "${path_additions[@]}"; do
  [[ -d "$dir" ]] && PATH="${dir}:${PATH}"
done
export PATH

# Load secrets
if [[ ! -f "$SECRETS_FILE" ]]; then
  log "ERROR: Secrets file not found: $SECRETS_FILE"
  log "Create it with: ADMIN_SECRET=<secret> NIIMBOT_ADDR=<uuid> NIIMBOT_CONN=ble"
  exit 1
fi

set -a
source "$SECRETS_FILE"
set +a

if [[ -z "$ADMIN_SECRET" ]]; then
  log "ERROR: ADMIN_SECRET not set in $SECRETS_FILE"
  exit 1
fi

cd "$SCRIPT_DIR"

log "Starting Niimbot D11 Vial Label Printer daemon..."
exec "$SCRIPT_DIR/.venv/bin/python" vial_label_printer.py 2>&1 | tee -a "$LOG_FILE"
