#!/usr/bin/env bash
# test/cleanup.sh — Remove moltbot-test worker and local clone
#
# Usage:
#   bash test/cleanup.sh

WORKER_NAME="moltbot-test"
INSTALL_DIR="$HOME/moltworker-test"

echo ""
echo "Cleaning up moltbot-test..."
echo ""

# Delete worker from Cloudflare
echo "  Deleting $WORKER_NAME worker..."
if [[ -d "$INSTALL_DIR" ]]; then
  cd "$INSTALL_DIR"
  echo "yes" | npx wrangler delete --name "$WORKER_NAME" &>/dev/null \
    && echo "  ✓ Worker deleted" \
    || echo "  Worker not found (already deleted?)"
else
  echo "  Skipping (no local clone found)"
fi

# Remove local clone
echo "  Removing $INSTALL_DIR..."
rm -rf "$INSTALL_DIR" && echo "  ✓ Local files removed"

echo ""
echo "Done. moltbot-test fully removed."
echo ""
