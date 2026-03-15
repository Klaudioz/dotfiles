#!/usr/bin/env bash
set -e

# Telegram Label Printer - launchd wrapper script
# Polls R2 print-queue/ for label PDFs and auto-prints at 85% scale

HOME_DIR="${HOME:-/Users/klaudioz}"
SCRIPT_DIR="$HOME_DIR/dotfiles/telegram-label-printer"
LOG_FILE="/tmp/telegram-label-printer.log"
SECRETS_FILE="$HOME_DIR/.config/telegram-label-printer/secrets.env"

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
  log "Create it with: CLOUDFLARE_ACCOUNT_ID=<id> and CLOUDFLARE_API_TOKEN=<token>"
  exit 1
fi

set -a
source "$SECRETS_FILE"
set +a

# Verify required vars
if [[ -z "$CLOUDFLARE_ACCOUNT_ID" ]] || [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
  log "ERROR: CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN must be set in $SECRETS_FILE"
  exit 1
fi

cd "$SCRIPT_DIR"

log "Starting Telegram Label Printer daemon..."
exec python3 label_printer.py 2>&1 | tee -a "$LOG_FILE"
