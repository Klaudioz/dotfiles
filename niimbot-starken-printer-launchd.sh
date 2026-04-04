#!/usr/bin/env bash
set -e

# Niimbot B1 Starken Shipping Label Printer - launchd wrapper script
# launchd runs this in single-run mode every 30s to avoid a resident BLE process

HOME_DIR="${HOME:-/Users/klaudioz}"
SCRIPT_DIR="$HOME_DIR/dotfiles/niimbot-starken-printer"
LOG_FILE="/tmp/niimbot-starken-printer.log"
SECRETS_FILE="$HOME_DIR/.config/niimbot-starken-printer/secrets.env"

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
  log "Create it with: ADMIN_SECRET=<secret>"
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

# Use the niimbot-vial-printer venv (has bleak, Pillow, niimprint)
VENV_PYTHON="$HOME_DIR/dotfiles/niimbot-vial-printer/.venv/bin/python"

if [[ "${RUN_ONCE:-0}" != "1" ]]; then
  log "Starting Niimbot B1 Starken Label Printer daemon..."
fi
exec "$VENV_PYTHON" starken_label_printer.py 2>&1 | tee -a "$LOG_FILE"
