#!/usr/bin/env bash
# =============================================================================
# setup-browser-skill.sh — Install cloudflare-browser skill into R2
# =============================================================================
# Downloads the cloudflare-browser skill from the public moltworker repo and
# uploads it to R2 so start-openclaw.sh restores it to the container on boot.
#
# Usage (standalone on existing instance):
#   R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... \
#   R2_BUCKET=moltbot-data WORKER_NAME=moltbot-sandbox \
#   ./scripts/setup-browser-skill.sh
#
# Or let deploy.sh call it with variables already in scope.
# =============================================================================

set -euo pipefail

SKILL_REPO="https://raw.githubusercontent.com/cloudflare/moltworker/main/skills/cloudflare-browser"
SKILL_TMP="/tmp/cloudflare-browser-skill"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${BLUE}→${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*"; exit 1; }

# Require wrangler in PATH (deploy.sh already has npm install done)
if ! command -v npx &>/dev/null; then
  err "npx not found. Run this from ~/moltworker after npm install."
fi

: "${WORKER_NAME:?WORKER_NAME must be set}"
: "${R2_BUCKET:?R2_BUCKET must be set}"

# ---------------------------------------------------------------------------
# 1. Download skill files
# ---------------------------------------------------------------------------

info "Downloading cloudflare-browser skill files..."

rm -rf "$SKILL_TMP"
mkdir -p "$SKILL_TMP/scripts"

curl -sSf "$SKILL_REPO/SKILL.md"             -o "$SKILL_TMP/SKILL.md"
curl -sSf "$SKILL_REPO/scripts/cdp-client.js" -o "$SKILL_TMP/scripts/cdp-client.js"
curl -sSf "$SKILL_REPO/scripts/screenshot.js" -o "$SKILL_TMP/scripts/screenshot.js"
curl -sSf "$SKILL_REPO/scripts/video.js"      -o "$SKILL_TMP/scripts/video.js"

log "Downloaded 4 skill files"

# ---------------------------------------------------------------------------
# 2. Upload to R2
#    R2 path: skills/cloudflare-browser/...
#    start-openclaw.sh restores this bucket into /root/.openclaw/ at boot.
# ---------------------------------------------------------------------------

info "Uploading to R2 bucket '$R2_BUCKET'..."

r2_put() {
  local local_path="$1"
  local r2_key="$2"
  npx wrangler r2 object put "${R2_BUCKET}/${r2_key}" \
    --file="$local_path" \
    --name "$WORKER_NAME" \
    2>/dev/null
}

r2_put "$SKILL_TMP/SKILL.md"                 "skills/cloudflare-browser/SKILL.md"
r2_put "$SKILL_TMP/scripts/cdp-client.js"    "skills/cloudflare-browser/scripts/cdp-client.js"
r2_put "$SKILL_TMP/scripts/screenshot.js"    "skills/cloudflare-browser/scripts/screenshot.js"
r2_put "$SKILL_TMP/scripts/video.js"         "skills/cloudflare-browser/scripts/video.js"

log "Uploaded to R2 — files will be restored on next container start"

# ---------------------------------------------------------------------------
# 3. Verify
# ---------------------------------------------------------------------------

echo ""
log "cloudflare-browser skill is staged in R2."
echo ""
echo "  On next container boot start-openclaw.sh will restore:"
echo "    /root/.openclaw/skills/cloudflare-browser/SKILL.md"
echo "    /root/.openclaw/skills/cloudflare-browser/scripts/cdp-client.js"
echo "    /root/.openclaw/skills/cloudflare-browser/scripts/screenshot.js"
echo "    /root/.openclaw/skills/cloudflare-browser/scripts/video.js"
echo ""
echo "  To force an immediate install without restarting, run via debug CLI:"
echo "    /debug/cli?cmd=mkdir%20-p%20/root/.openclaw/skills/cloudflare-browser/scripts"
echo "    /debug/cli?cmd=curl%20-sSo%20/root/.openclaw/skills/cloudflare-browser/SKILL.md%20${SKILL_REPO//\//%2F}/SKILL.md"

rm -rf "$SKILL_TMP"
