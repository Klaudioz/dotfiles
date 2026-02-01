#!/usr/bin/env bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_warn() {
  echo -e "${YELLOW}!${NC} $1" >&2
}

log_error() {
  echo -e "${RED}✗${NC} $1" >&2
}

HOME_DIR="${HOME:-/Users/klaudioz}"
TAKOPI_CONFIG="${HOME_DIR}/.takopi/takopi.toml"
TAKOPI_BIN="${HOME_DIR}/.local/bin/takopi"
OPENCODE_SECRETS="${HOME_DIR}/.config/opencode/secrets.zsh"

if [[ ! -f "$TAKOPI_CONFIG" ]]; then
  log_warn "takopi config not found: $TAKOPI_CONFIG"
  log_warn "Run: takopi --onboard"
  exit 0
fi

export TAKOPI_NO_INTERACTIVE=1

# launchd can start before your interactive environment is ready. Keep limits sane to
# reduce transient `fork()`/EAGAIN failures (seen as: "cannot fork() ... Resource temporarily unavailable").
ulimit -u 4000 2>/dev/null || true
ulimit -n 8192 2>/dev/null || true

# Prefer 1Password SSH agent (GitHub key lives here). If 1Password isn't up yet,
# wait briefly so Takopi can push/fetch via SSH.
ONEPASSWORD_SSH_AUTH_SOCK="${HOME_DIR}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
if [[ ! -S "$ONEPASSWORD_SSH_AUTH_SOCK" ]]; then
  tries=0
  while [[ $tries -lt 30 ]]; do
    sleep 1
    [[ -S "$ONEPASSWORD_SSH_AUTH_SOCK" ]] && break
    tries=$((tries + 1))
  done
fi

if [[ -S "$ONEPASSWORD_SSH_AUTH_SOCK" ]]; then
  export SSH_AUTH_SOCK="$ONEPASSWORD_SSH_AUTH_SOCK"
else
  log_warn "1Password SSH agent socket not found; git fetch/push via SSH may fail until 1Password is running/unlocked."
fi

# launchd does not inherit the interactive shell PATH. Ensure Nix + Homebrew + uv tools are visible.
path_additions=(
  /run/current-system/sw/bin
  /opt/homebrew/bin
  /opt/homebrew/sbin
  "$HOME_DIR/.local/bin"
  "$HOME_DIR/.opencode/bin"
  "$HOME_DIR/.npm-global/bin"
  "$HOME_DIR/.bun/bin"
  "$HOME_DIR/go/bin"
  "$HOME_DIR/.cargo/bin"
)

for dir in "${path_additions[@]}"; do
  [[ -d "$dir" ]] && PATH="${dir}:${PATH}"
done

export PATH

if [[ -f "$OPENCODE_SECRETS" ]]; then
  # shellcheck source=/dev/null
  source "$OPENCODE_SECRETS"
fi

[[ -n "${QUOTIO_API_KEY:-}" ]] && export QUOTIO_API_KEY
export CLIPROXYAPI_ENDPOINT="http://localhost:8317/v1"
export OPENCODE_CONFIG_CONTENT='{"model":"quotio/gemini-claude-sonnet-4-5","small_model":"quotio/gemini-3-flash-preview"}'
unset OPENCODE_BIN_PATH

if [[ ! -x "$TAKOPI_BIN" ]]; then
  log_warn "takopi not found at: $TAKOPI_BIN"
  exit 0
fi

if ! command -v opencode >/dev/null 2>&1 && ! command -v codex >/dev/null 2>&1 && ! command -v claude >/dev/null 2>&1 && \
  ! command -v pi >/dev/null 2>&1; then
  log_warn "no engine found on PATH (need one of: opencode, codex, claude, pi)"
  exit 0
fi

# If Takopi has no projects configured, it runs in the startup working directory.
# Keep that contained to ~/.takopi to avoid polluting $HOME.
cd "${HOME_DIR}/.takopi" 2>/dev/null || cd "$HOME_DIR"

exec "$TAKOPI_BIN" opencode
