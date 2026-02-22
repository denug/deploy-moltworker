#!/usr/bin/env bash
# test/run.sh — Smoke-test deploy of a second moltworker instance (moltbot-test)
#
# Non-interactive: reads all credentials from the existing 1Password 'moltworker' item.
# Uses DEV_MODE=true to bypass CF Access auth — no browser step needed.
# No Telegram.
#
# Usage:
#   bash test/run.sh
#
# Prerequisites: 1Password CLI authenticated, wrangler authenticated, node installed.

set -euo pipefail

WORKER_NAME="moltbot-test"
OP_ITEM="moltworker"
OP_VAULT="Private"
INSTALL_DIR="$HOME/moltworker-test"
REPO_URL="https://github.com/denug/moltbot-sandbox"

log()   { echo "  ✓ $*"; }
info()  { echo "  → $*"; }
error() { echo "  ✗ ERROR: $*" >&2; exit 1; }

echo ""
echo "=========================================="
echo "  moltbot-test smoke deploy"
echo "=========================================="
echo ""

# --- Prereqs ---
command -v op      &>/dev/null || error "1Password CLI not installed. Run: brew install 1password-cli"
command -v node    &>/dev/null || error "Node.js not installed."
command -v git     &>/dev/null || error "Git not installed."
op account list    &>/dev/null || error "Not signed in to 1Password. Run: op signin"
npx wrangler whoami &>/dev/null 2>&1 || error "Not authenticated with Cloudflare. Run: npx wrangler login"

# --- Read credentials from 1Password ---
info "Reading credentials from 1Password '$OP_ITEM'..."

ANTHROPIC_API_KEY=$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields label="ANTHROPIC_API_KEY" --reveal 2>/dev/null)
CF_ACCESS_TEAM_DOMAIN=$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields label="CF_ACCESS_TEAM_DOMAIN" 2>/dev/null)
R2_ACCESS_KEY_ID=$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields label="R2_ACCESS_KEY_ID" 2>/dev/null)
R2_SECRET_ACCESS_KEY=$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields label="R2_SECRET_ACCESS_KEY" --reveal 2>/dev/null)
CF_ACCOUNT_ID=$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields label="CF_ACCOUNT_ID" 2>/dev/null)
EXISTING_WORKER_URL=$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields label="WORKER_URL" 2>/dev/null)

[[ -z "$ANTHROPIC_API_KEY" ]]    && error "ANTHROPIC_API_KEY missing from 1Password"
[[ -z "$CF_ACCOUNT_ID" ]]        && error "CF_ACCOUNT_ID missing from 1Password"
[[ -z "$EXISTING_WORKER_URL" ]]  && error "WORKER_URL missing from 1Password"

# Derive workers subdomain from existing URL
# e.g. https://moltbot-sandbox.yourname.workers.dev → yourname
WORKERS_SUBDOMAIN=$(echo "$EXISTING_WORKER_URL" | sed 's|https://[^.]*\.\([^.]*\)\.workers\.dev.*|\1|')
WORKER_URL="https://${WORKER_NAME}.${WORKERS_SUBDOMAIN}.workers.dev"
MOLTBOT_GATEWAY_TOKEN=$(openssl rand -hex 32)

log "Credentials loaded"
echo ""
echo "  Worker:  $WORKER_URL"
echo "  R2:      moltbot-data (shared with production — fine for testing)"
echo "  Auth:    DEV_MODE=true (no CF Access browser step)"
echo ""

# --- Clone or update repo ---
if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "Updating existing repo at $INSTALL_DIR..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  info "Cloning repo to $INSTALL_DIR..."
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
info "Installing dependencies..."
npm install --silent
log "Repo ready"
echo ""

# Patch wrangler.jsonc: change worker name to moltbot-test
sed -i '' 's/"name": "moltbot-sandbox"/"name": "moltbot-test"/' wrangler.jsonc
log "Patched wrangler.jsonc: name → $WORKER_NAME"

# --- Set wrangler secrets ---
info "Setting secrets for $WORKER_NAME..."

set_secret() {
  local name="$1" value="$2"
  if [[ -n "$value" ]]; then
    if echo "$value" | npx wrangler secret put "$name" --name "$WORKER_NAME" &>/dev/null; then
      echo "    ✓ $name"
    else
      echo "    ✗ $name (FAILED)"
    fi
  fi
}

set_secret "ANTHROPIC_API_KEY"     "$ANTHROPIC_API_KEY"
set_secret "MOLTBOT_GATEWAY_TOKEN" "$MOLTBOT_GATEWAY_TOKEN"
set_secret "CF_ACCESS_TEAM_DOMAIN" "$CF_ACCESS_TEAM_DOMAIN"
set_secret "R2_ACCESS_KEY_ID"      "$R2_ACCESS_KEY_ID"
set_secret "R2_SECRET_ACCESS_KEY"  "$R2_SECRET_ACCESS_KEY"
set_secret "CF_ACCOUNT_ID"         "$CF_ACCOUNT_ID"
set_secret "WORKER_URL"            "$WORKER_URL"

# DEV_MODE=true: skips CF Access auth + device pairing (test only — never use in production)
if echo "true" | npx wrangler secret put "DEV_MODE" --name "$WORKER_NAME" &>/dev/null; then
  echo "    ✓ DEV_MODE=true"
fi
echo ""

# --- Deploy ---
info "Deploying $WORKER_NAME (3-5 min)..."
echo ""
npm run deploy
echo ""

# --- Done ---
echo "=========================================="
echo "  moltbot-test deployed!"
echo ""
echo "  Open this URL (wait ~60s for container):"
echo "  $WORKER_URL/?token=$MOLTBOT_GATEWAY_TOKEN"
echo ""
echo "  Send a chat message to verify AI responds."
echo ""
echo "  Gateway token: $MOLTBOT_GATEWAY_TOKEN"
echo "  (Not saved to 1Password — test instance only)"
echo ""
echo "  To clean up when done:"
echo "  bash $(cd "$(dirname "$0")"; pwd)/cleanup.sh"
echo "=========================================="
echo ""
