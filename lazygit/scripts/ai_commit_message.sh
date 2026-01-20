#!/usr/bin/env bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

fail() {
  echo -e "${RED}✗${NC} $1"
  exit 1
}

warn() {
  echo -e "${YELLOW}!${NC} $1"
}

if ! command -v git &> /dev/null; then
  fail "git not found"
fi

if ! command -v aichat &> /dev/null; then
  fail "aichat not found (run: ./setup.sh --update)"
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  fail "OPENAI_API_KEY is not set (required for aichat OpenAI client)"
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  fail "not inside a git repository"
fi

cd "$repo_root"

if git diff --cached --quiet; then
  fail "no staged changes (stage files first, then retry)"
fi

system_prompt=$'You write excellent git commit messages.\n\nRules:\n- Output ONLY the subject line.\n- Use Conventional Commits: feat|fix|docs|chore|refactor|test|perf|ci|build.\n- <= 72 characters.\n- Imperative mood.\n- No trailing period.\n- Add scope only if obvious.\n'

message="$(
  git diff --cached --no-color \
    | aichat -S -m openai:gpt-4o-mini --prompt "$system_prompt" \
    | tr -d '\r' \
    | head -n 1 \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
)"

if [[ -z "$message" ]]; then
  fail "model returned an empty commit message"
fi

if command -v pbcopy &> /dev/null; then
  printf '%s' "$message" | pbcopy
else
  warn "pbcopy not found; skipping clipboard copy"
fi

echo "$message"
