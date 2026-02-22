#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Deploy moltworker to Cloudflare
# =============================================================================
# Fully automated deployment of OpenClaw personal AI assistant on Cloudflare.
#
# Usage:
#   ./deploy.sh
#
# What this does:
#   1. Checks and installs all required tools
#   2. Collects ALL credentials upfront (one time)
#   3. Stores secrets securely in 1Password
#   4. Clones the moltworker repo
#   5. Authenticates with Cloudflare
#   6. Creates R2 bucket + sets all secrets
#   7. Deploys the worker
#   8. Guides through Cloudflare Access setup (one browser step)
#   9. Final deploy + verifies everything is running
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Config
REPO_URL="https://github.com/denug/moltbot-sandbox"
WORKER_NAME="moltbot-sandbox"
R2_BUCKET="moltbot-data"
OP_ITEM="moltworker"
OP_VAULT="Private"
INSTALL_DIR="$HOME/moltworker"

# =============================================================================
# HELPERS
# =============================================================================

log()     { echo -e "${GREEN}✓${NC} $*"; }
info()    { echo -e "${BLUE}→${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
error()   { echo -e "${RED}✗ ERROR:${NC} $*"; exit 1; }
heading() { echo -e "\n${BOLD}${CYAN}$*${NC}"; echo -e "${CYAN}$(printf '=%.0s' {1..60})${NC}"; }
ask()     { echo -e "${YELLOW}?${NC} $*"; }

prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local is_secret="${3:-false}"
  local value=""

  echo ""
  ask "$prompt_text"
  if [[ "$is_secret" == "true" ]]; then
    read -r -s value
    echo ""
  else
    read -r value
  fi

  if [[ -z "$value" ]]; then
    error "$var_name cannot be empty."
  fi

  echo "$value"
}

open_url() {
  open "$1" 2>/dev/null || xdg-open "$1" 2>/dev/null || echo "Open this URL: $1"
}

# =============================================================================
# BANNER
# =============================================================================

clear
echo -e "${BOLD}"
cat << 'EOF'
  __  __       _ ____    __        __        _
 |  \/  | ___ | |_   _|  \ \      / /__  _ __| | _____ _ __
 | |\/| |/ _ \| | | |_____\ \ /\ / / _ \| '__| |/ / _ \ '__|
 | |  | | (_) | | | |______\ V  V / (_) | |  |   <  __/ |
 |_|  |_|\___/|_| |_|       \_/\_/ \___/|_|  |_|\_\___|_|

EOF
echo -e "${NC}"
echo -e "${CYAN}OpenClaw Personal AI Assistant — Automated Cloudflare Deployment${NC}"
echo -e "This script will deploy your own AI assistant in about 10 minutes.\n"

# =============================================================================
# PHASE 1 — COLLECT ALL VARIABLES UPFRONT
# =============================================================================

heading "PHASE 1 — What we need from you"

echo ""
echo -e "Before anything runs, we'll collect everything needed."
echo -e "Have these ready (links in REQUIREMENTS.md if you need them):\n"
echo -e "  ${BOLD}Required:${NC}"
echo -e "  • Anthropic API key     → https://console.anthropic.com/settings/keys"
echo -e "  • Cloudflare login      → https://dash.cloudflare.com (you'll log in below)"
echo -e "  • CF Zero Trust domain  → https://one.dash.cloudflare.com → Settings → Custom Pages"
echo -e "  • R2 API keys           → https://dash.cloudflare.com → R2 → Manage R2 API Tokens"
echo -e ""
echo -e "  ${BOLD}Optional (for Telegram chat):${NC}"
echo -e "  • Telegram bot token    → Message @BotFather on Telegram → /newbot"
echo ""
echo -e "  ${YELLOW}Note:${NC} All values are stored in 1Password — never written to disk as plaintext.\n"

read -r -p "Press ENTER when ready to begin..."

# --- Anthropic API key ---
echo ""
heading "Anthropic API Key"
info "Your key starts with 'sk-ant-api03-...'"
info "Get it at: https://console.anthropic.com/settings/keys"
ANTHROPIC_API_KEY=$(prompt "ANTHROPIC_API_KEY" "Paste your Anthropic API key:" true)

# --- CF Zero Trust domain ---
echo ""
heading "Cloudflare Zero Trust Team Domain"
info "Find it at: https://one.dash.cloudflare.com → Settings → Custom Pages"
info "It looks like: yourteam.cloudflareaccess.com"
CF_ACCESS_TEAM_DOMAIN=$(prompt "CF_ACCESS_TEAM_DOMAIN" "Enter your Zero Trust team domain (e.g. myteam.cloudflareaccess.com):" false)
# Strip protocol if user included it
CF_ACCESS_TEAM_DOMAIN="${CF_ACCESS_TEAM_DOMAIN#https://}"
CF_ACCESS_TEAM_DOMAIN="${CF_ACCESS_TEAM_DOMAIN%/}"

# --- R2 keys ---
echo ""
heading "Cloudflare R2 API Keys"
info "Create them at: https://dash.cloudflare.com → R2 → Manage R2 API Tokens"
info "Create a token with 'Object Read & Write' on bucket '$R2_BUCKET'"
warn "The Secret Access Key is shown ONCE — copy it before closing the page."
echo ""
R2_ACCESS_KEY_ID=$(prompt "R2_ACCESS_KEY_ID" "Paste your R2 Access Key ID:" false)
R2_SECRET_ACCESS_KEY=$(prompt "R2_SECRET_ACCESS_KEY" "Paste your R2 Secret Access Key:" true)

# --- Telegram (optional) ---
echo ""
heading "Telegram Bot Token (optional)"
info "Skip this if you don't want Telegram chat integration."
info "To get a token: open Telegram → message @BotFather → /newbot"
echo ""
ask "Do you want Telegram integration? (y/n)"
read -r WANT_TELEGRAM
TELEGRAM_BOT_TOKEN=""
if [[ "$WANT_TELEGRAM" == "y" || "$WANT_TELEGRAM" == "Y" ]]; then
  TELEGRAM_BOT_TOKEN=$(prompt "TELEGRAM_BOT_TOKEN" "Paste your Telegram bot token:" true)
fi

# --- Generate gateway token and CDP secret ---
MOLTBOT_GATEWAY_TOKEN=$(openssl rand -hex 32)
CDP_SECRET=$(openssl rand -hex 32)

# --- Summary ---
echo ""
heading "Summary — here's what we'll set up"
echo ""
echo -e "  ${BOLD}Worker:${NC}       $WORKER_NAME"
echo -e "  ${BOLD}R2 Bucket:${NC}    $R2_BUCKET"
echo -e "  ${BOLD}CF Zero Trust:${NC} $CF_ACCESS_TEAM_DOMAIN"
echo -e "  ${BOLD}Telegram:${NC}     $([ -n "$TELEGRAM_BOT_TOKEN" ] && echo "enabled" || echo "skipped")"
echo -e "  ${BOLD}Gateway token:${NC} [generated — will be saved to 1Password]"
echo -e "  ${BOLD}1Password item:${NC} '$OP_ITEM' in '$OP_VAULT' vault"
echo ""
ask "Everything look right? Type 'yes' to continue or Ctrl+C to abort:"
read -r CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# =============================================================================
# PHASE 2 — INSTALL TOOLS
# =============================================================================

heading "PHASE 2 — Installing required tools"

# Homebrew
if ! command -v brew &>/dev/null; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  log "Homebrew already installed"
fi

# Node.js
if ! command -v node &>/dev/null; then
  info "Installing Node.js..."
  brew install node
else
  log "Node.js already installed ($(node --version))"
fi

# 1Password CLI
if ! command -v op &>/dev/null; then
  info "Installing 1Password CLI..."
  brew install 1password-cli
else
  log "1Password CLI already installed ($(op --version))"
fi

# Git
if ! command -v git &>/dev/null; then
  info "Installing Git..."
  brew install git
else
  log "Git already installed"
fi

# Docker Desktop
if ! command -v docker &>/dev/null; then
  info "Installing Docker Desktop..."
  warn "This requires your Mac password. Enter it when prompted."
  brew install --cask docker
  echo ""
  warn "Docker Desktop installed. Please:"
  warn "  1. Open Docker Desktop from your Applications folder"
  warn "  2. Wait for it to finish starting (whale icon stops animating)"
  read -r -p "Press ENTER once Docker Desktop is running..."
else
  # Docker is installed — make sure daemon is running
  if ! docker info &>/dev/null 2>&1; then
    warn "Docker is installed but not running."
    warn "Please open Docker Desktop from Applications and wait for it to start."
    read -r -p "Press ENTER once Docker Desktop is running..."
  else
    log "Docker already installed and running"
  fi
fi

# =============================================================================
# PHASE 3 — AUTHENTICATE
# =============================================================================

heading "PHASE 3 — Authentication"

# 1Password
info "Checking 1Password authentication..."
if ! op account list &>/dev/null; then
  info "Please sign in to 1Password:"
  op signin
fi
log "1Password authenticated"

# Cloudflare / wrangler
info "Checking Cloudflare authentication..."
if ! npx wrangler whoami &>/dev/null 2>&1; then
  info "Opening Cloudflare login in your browser..."
  npx wrangler login
fi
log "Cloudflare authenticated"

# Detect account ID and subdomain
CF_ACCOUNT_ID=$(npx wrangler whoami --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
if [[ -z "$CF_ACCOUNT_ID" ]]; then
  warn "Could not auto-detect account ID. Checking config..."
  CF_ACCOUNT_ID=$(cat ~/Library/Preferences/.wrangler/config/default.toml 2>/dev/null | grep account_id | cut -d'"' -f2 || echo "")
fi

if [[ -z "$CF_ACCOUNT_ID" ]]; then
  CF_ACCOUNT_ID=$(prompt "CF_ACCOUNT_ID" "Could not auto-detect account ID. Find it at https://dash.cloudflare.com → right sidebar. Paste it here:" false)
fi

log "Cloudflare Account ID: $CF_ACCOUNT_ID"
WORKER_URL="https://${WORKER_NAME}.$(npx wrangler whoami 2>/dev/null | grep 'workers.dev' | awk '{print $NF}' || echo 'workers.dev')"
info "Worker will be deployed to: $WORKER_URL"

# =============================================================================
# PHASE 4 — STORE IN 1PASSWORD
# =============================================================================

heading "PHASE 4 — Storing secrets in 1Password"

# Check if item already exists
if op item get "$OP_ITEM" --vault "$OP_VAULT" &>/dev/null 2>&1; then
  warn "1Password item '$OP_ITEM' already exists — updating it..."
  op item edit "$OP_ITEM" --vault "$OP_VAULT" \
    "ANTHROPIC_API_KEY[concealed]=$ANTHROPIC_API_KEY" \
    "MOLTBOT_GATEWAY_TOKEN[concealed]=$MOLTBOT_GATEWAY_TOKEN" \
    "CF_ACCOUNT_ID[text]=$CF_ACCOUNT_ID" \
    "CF_ACCESS_TEAM_DOMAIN[text]=$CF_ACCESS_TEAM_DOMAIN" \
    "R2_ACCESS_KEY_ID[text]=$R2_ACCESS_KEY_ID" \
    "R2_SECRET_ACCESS_KEY[concealed]=$R2_SECRET_ACCESS_KEY" \
    "WORKER_URL[text]=$WORKER_URL" \
    ${TELEGRAM_BOT_TOKEN:+"TELEGRAM_BOT_TOKEN[concealed]=$TELEGRAM_BOT_TOKEN"} \
    "CDP_SECRET[concealed]=$CDP_SECRET" \
    &>/dev/null
else
  op item create \
    --category "API Credential" \
    --title "$OP_ITEM" \
    --vault "$OP_VAULT" \
    --url "$WORKER_URL" \
    --tags "cloudflare,moltworker" \
    "ANTHROPIC_API_KEY[concealed]=$ANTHROPIC_API_KEY" \
    "MOLTBOT_GATEWAY_TOKEN[concealed]=$MOLTBOT_GATEWAY_TOKEN" \
    "CF_ACCOUNT_ID[text]=$CF_ACCOUNT_ID" \
    "CF_ACCESS_TEAM_DOMAIN[text]=$CF_ACCESS_TEAM_DOMAIN" \
    "CF_ACCESS_AUD[concealed]=PENDING" \
    "R2_ACCESS_KEY_ID[text]=$R2_ACCESS_KEY_ID" \
    "R2_SECRET_ACCESS_KEY[concealed]=$R2_SECRET_ACCESS_KEY" \
    "WORKER_URL[text]=$WORKER_URL" \
    ${TELEGRAM_BOT_TOKEN:+"TELEGRAM_BOT_TOKEN[concealed]=$TELEGRAM_BOT_TOKEN"} \
    "CDP_SECRET[concealed]=$CDP_SECRET" \
    &>/dev/null
fi

log "Secrets stored in 1Password"

# =============================================================================
# PHASE 5 — CLONE REPO
# =============================================================================

heading "PHASE 5 — Setting up moltworker code"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "Repo already exists at $INSTALL_DIR — pulling latest..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  info "Cloning moltworker repo to $INSTALL_DIR..."
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
info "Installing dependencies..."
npm install --silent
log "Repo ready at $INSTALL_DIR"

# =============================================================================
# PHASE 6 — SET WRANGLER SECRETS
# =============================================================================

heading "PHASE 6 — Setting Cloudflare secrets"

set_secret() {
  local name="$1"
  local value="$2"
  if [[ -n "$value" && "$value" != "PENDING" ]]; then
    echo "$value" | npx wrangler secret put "$name" --name "$WORKER_NAME" &>/dev/null
    log "Set $name"
  fi
}

set_secret "ANTHROPIC_API_KEY"    "$ANTHROPIC_API_KEY"
set_secret "MOLTBOT_GATEWAY_TOKEN" "$MOLTBOT_GATEWAY_TOKEN"
set_secret "CF_ACCESS_TEAM_DOMAIN" "$CF_ACCESS_TEAM_DOMAIN"
set_secret "R2_ACCESS_KEY_ID"     "$R2_ACCESS_KEY_ID"
set_secret "R2_SECRET_ACCESS_KEY" "$R2_SECRET_ACCESS_KEY"
set_secret "CF_ACCOUNT_ID"        "$CF_ACCOUNT_ID"
set_secret "WORKER_URL"           "$WORKER_URL"
set_secret "CDP_SECRET"           "$CDP_SECRET"
[[ -n "$TELEGRAM_BOT_TOKEN" ]] && set_secret "TELEGRAM_BOT_TOKEN" "$TELEGRAM_BOT_TOKEN"

# =============================================================================
# PHASE 7 — INITIAL DEPLOY
# =============================================================================

heading "PHASE 7 — Deploying to Cloudflare (this takes 3-5 minutes)"

npm run deploy

log "Worker deployed!"
echo ""
echo -e "  Worker URL: ${CYAN}$WORKER_URL${NC}"

# =============================================================================
# PHASE 8 — CLOUDFLARE ACCESS SETUP (one browser step)
# =============================================================================

heading "PHASE 8 — Setting up Cloudflare Access (one manual step)"

echo ""
echo -e "  ${BOLD}We need to protect your worker with Cloudflare Access.${NC}"
echo -e "  This requires one step in the Cloudflare dashboard.\n"
echo -e "  ${BOLD}Instructions:${NC}"
echo -e "  1. We'll open the Workers dashboard in your browser"
echo -e "  2. Click on '${WORKER_NAME}'"
echo -e "  3. Go to Settings → Domains & Routes"
echo -e "  4. Find the 'workers.dev' row → click '...' → 'Enable Cloudflare Access'"
echo -e "  5. Copy the ${BOLD}Application Audience (AUD)${NC} tag shown in the dialog"
echo -e "  6. Paste it here\n"

read -r -p "Press ENTER to open the Cloudflare Workers dashboard..."
open_url "https://dash.cloudflare.com/${CF_ACCOUNT_ID}/workers-and-pages"

echo ""
CF_ACCESS_AUD=$(prompt "CF_ACCESS_AUD" "Paste the Application Audience (AUD) tag:" true)

# Save AUD to 1Password
op item edit "$OP_ITEM" --vault "$OP_VAULT" \
  "CF_ACCESS_AUD[concealed]=$CF_ACCESS_AUD" &>/dev/null
log "AUD saved to 1Password"

# Set the secret
set_secret "CF_ACCESS_AUD" "$CF_ACCESS_AUD"

# =============================================================================
# PHASE 9 — FINAL DEPLOY + VERIFY
# =============================================================================

heading "PHASE 9 — Final deploy"

npm run deploy
log "Final deploy complete"

# =============================================================================
# DONE
# =============================================================================

heading "All done!"

GATEWAY_TOKEN=$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields label=MOLTBOT_GATEWAY_TOKEN --reveal 2>/dev/null)

echo ""
echo -e "  ${GREEN}${BOLD}Your moltworker is live!${NC}"
echo ""
echo -e "  ${BOLD}Control UI:${NC}"
echo -e "  ${CYAN}${WORKER_URL}/?token=${GATEWAY_TOKEN}${NC}"
echo ""
echo -e "  ${BOLD}Admin UI (device pairing):${NC}"
echo -e "  ${CYAN}${WORKER_URL}/_admin/${NC}"
echo ""
echo -e "  ${YELLOW}Note:${NC} First visit may take 1-2 minutes for the container to start."
echo -e "  ${YELLOW}Note:${NC} Visit /_admin/ to pair your device before using the Control UI."
echo ""
echo -e "  ${BOLD}Your gateway token is saved in 1Password → '$OP_ITEM'${NC}"
echo ""
echo -e "  To redeploy in the future:"
echo -e "  ${CYAN}cd $INSTALL_DIR && ./scripts/set-secrets.sh && npm run deploy${NC}"
echo ""
echo -e "  ${BOLD}${YELLOW}Optional — enable browser automation (one dashboard step):${NC}"
echo -e "  CF Access intercepts /cdp by default. To allow browser use:"
echo -e "  1. Go to one.dash.cloudflare.com → Access → Applications → Add Application"
echo -e "  2. Self-Hosted | Name: 'moltbot CDP' | Path: /cdp"
echo -e "  3. Policy: name=bypass, Action=Bypass, Include=Everyone"
echo -e "  See TROUBLESHOOTING.md → 'Browser automation not working' for full steps."
echo ""
