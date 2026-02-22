# Troubleshooting

## Browser automation not working

Browser rendering requires two setup steps: a CF Access bypass and configuring the browser profile via the OpenClaw CLI.

### Step 1 — Create a CF Access bypass for `/cdp`

CF Access intercepts all requests to your worker before they reach your code. You need a bypass rule so the browser skill's WebSocket connection to `/cdp` can reach the worker directly (the `CDP_SECRET` query param handles auth instead).

**Easiest: use the Cloudflare API (requires a one-time token)**

1. Go to `dash.cloudflare.com` → **My Profile** → **API Tokens** → **Create Token**
2. Use **Create Custom Token** with permission: `Account` → `Access: Apps and Policies` → `Edit`
3. Run:
```bash
ACCOUNT_ID="your-cf-account-id"
WORKER_NAME="moltbot-sandbox"
WORKERS_SUBDOMAIN="yourname"  # e.g. yourname from yourname.workers.dev
CF_TOKEN="your-token-here"

curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/access/apps" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"self_hosted\",
    \"name\": \"moltbot CDP bypass\",
    \"destinations\": [{\"type\": \"public\", \"uri\": \"$WORKER_NAME.$WORKERS_SUBDOMAIN.workers.dev/cdp\"}],
    \"session_duration\": \"24h\",
    \"policies\": [{
      \"name\": \"bypass-everyone\",
      \"decision\": \"bypass\",
      \"include\": [{\"everyone\": {}}],
      \"exclude\": [], \"require\": [], \"precedence\": 1
    }]
  }"
```
4. Delete the API token immediately after.

**Or manually** via Zero Trust dashboard → Access → Applications → Add Self-Hosted → path `/cdp` → policy Bypass/Everyone.

### Step 2 — Verify `/cdp` is accessible

```bash
CDP_SECRET=$(op item get "moltworker" --vault Private --fields label="CDP_SECRET" --reveal)
WORKER_URL=$(op item get "moltworker" --vault Private --fields label="WORKER_URL")
curl "$WORKER_URL/cdp"
```
Should return JSON listing supported CDP methods (not a 302 redirect).

### Step 3 — Configure the browser profile via OpenClaw CLI

**Do not** edit `openclaw.json` by hand or via startup script — OpenClaw validates the schema strictly. Use the CLI instead.

Open the debug CLI at `https://<your-worker>/_admin/debug/cli` and run:
```
openclaw browser --help
```
to find the exact `profile add` command, then add the Cloudflare profile pointing to your `/cdp` endpoint:
```
openclaw browser profile add cloudflare \
  --cdp-url "https://<your-worker>/cdp?secret=<CDP_SECRET>"
```

This writes a valid, schema-compliant browser profile to `openclaw.json` and saves to R2.

**If CDP_SECRET is missing** (installs before this was added):
```bash
CDP_SECRET=$(openssl rand -hex 32)
echo "$CDP_SECRET" | npx wrangler secret put CDP_SECRET --name moltbot-sandbox
op item edit "moltworker" --vault Private "CDP_SECRET[concealed]=$CDP_SECRET"
cd ~/moltworker && npm run deploy
```

---

## deploy.sh fails immediately

**"Permission denied"**
```bash
chmod +x deploy.sh && ./deploy.sh
```

**"brew: command not found" on Linux**
Homebrew is macOS-only. On Linux, install tools manually:
```bash
# Ubuntu/Debian
sudo apt-get install -y nodejs npm git curl
npm install -g wrangler
brew install 1password-cli  # use snap or apt alternative
```

---

## Cloudflare login fails

Run wrangler login manually:
```bash
npx wrangler login
```
Then re-run `deploy.sh`.

---

## "Worker not found" error when setting secrets

The worker must be deployed before secrets can be set. If deploy failed, check:
```bash
npx wrangler tail --name moltbot-sandbox
```

---

## Deploy fails with "Unauthorized"

You need to enable Cloudflare Containers on your account:
1. Go to https://dash.cloudflare.com → Workers → Containers
2. Click **Enable Containers**

---

## Worker deploys but shows config error (503)

A required secret is missing. Check which ones are set:
```bash
cd ~/moltworker
npx wrangler secret list --name moltbot-sandbox
```

Compare against the required list in REQUIREMENTS.md. Set any missing ones:
```bash
echo "your-value" | npx wrangler secret put SECRET_NAME
```

---

## AI not responding to chats / HTTP 401 invalid x-api-key

Chat messages are silently ignored (no response). Logs show runs completing in under 300ms, or Telegram shows `HTTP 401: authentication_error: invalid x-api-key`.

**Root cause:** The `ANTHROPIC_API_KEY` stored in R2 (from a previous boot) is stale or invalid. The container restores it from R2 on startup but the startup script is supposed to overwrite it with the current wrangler secret.

**Step 1 — Verify the patch ran:**
Open: `https://<your-worker>/debug/logs`
Look for this line in stdout:
```
Auth profiles patched with ANTHROPIC_API_KEY
```
If missing, the container image is outdated — redeploy.

**Step 2 — Verify the correct key is loaded:**
Open: `https://<your-worker>/debug/cli?cmd=cat%20/root/.openclaw/agents/main/agent/auth-profiles.json`
Check that `profiles["anthropic:default"].key` matches your current key from 1Password.

**Step 3 — If key is wrong, push it fresh and redeploy:**
```bash
cd ~/moltworker
op item get "moltworker" --vault Private --fields label="ANTHROPIC_API_KEY" --reveal \
  | npx wrangler secret put ANTHROPIC_API_KEY --name moltbot-sandbox
npm run deploy
```

**Step 4 — Verify key is valid at console.anthropic.com → API Keys**
The key must show as Active and not revoked.

---

## Telegram DMs silently ignored (no response, no error)

**Root cause:** `dmPolicy` is set to `allowlist` with an empty list. All DMs are blocked.

**Fix — approve the pending pairing request:**
1. Have the user send any message to the bot — they'll get a pairing code
2. Open: `https://<your-worker>/debug/cli?cmd=openclaw%20pairing%20list%20telegram`
3. Copy the code, then open: `https://<your-worker>/debug/cli?cmd=openclaw%20pairing%20approve%20telegram%20<CODE>`

**Alternative — open DMs to everyone:**
```bash
echo "allow" | npx wrangler secret put TELEGRAM_DM_POLICY --name moltbot-sandbox
cd ~/moltworker && npm run deploy
```

---

## Gateway hung / AI not responding to chats

This happens when the OpenClaw process inside the container freezes. Fix:
1. Edit `~/moltworker/Dockerfile` — change the `# Build cache bust:` comment date to today
2. Redeploy:
```bash
cd ~/moltworker && npm run deploy
```

---

## CF Access 403 / "Authentication error"

`CF_ACCESS_TEAM_DOMAIN` or `CF_ACCESS_AUD` is wrong. Verify:
1. Go to https://one.dash.cloudflare.com → Access → Applications
2. Find your moltbot-sandbox app → copy the AUD tag
3. Update the secret:
```bash
cd ~/moltworker
echo "your-aud" | npx wrangler secret put CF_ACCESS_AUD
npm run deploy
```

---

## R2 storage not working / data not persisting

All three R2 secrets must be set:
```bash
npx wrangler secret list --name moltbot-sandbox | grep R2
```

Should show: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `CF_ACCOUNT_ID`

If missing, re-run: `cd ~/moltworker && ./scripts/set-secrets.sh`

---

## First visit is very slow (1-2 minutes)

This is normal — the container is starting up (cold start). Subsequent requests are fast. If it takes longer than 3 minutes, check logs:
```bash
npx wrangler tail --name moltbot-sandbox
```

---

## Lost your gateway token

It's saved in 1Password:
1. Open 1Password → Private vault → `moltworker`
2. Find `MOLTBOT_GATEWAY_TOKEN`

Or retrieve via CLI:
```bash
op item get "moltworker" --vault Private --fields label=MOLTBOT_GATEWAY_TOKEN --reveal
```

---

## Cron job runs but Telegram message never arrives

**Root cause:** Telling the cron agent to "send a message to @username" doesn't work because cron jobs run as isolated agents with no access to your Telegram session.

**Fix:** Use `announce` delivery mode when registering the cron job. This routes the agent's output back to you automatically through the correct channel.

```bash
openclaw cron add \
  --name "my-job" \
  --schedule "0 9 * * *" \
  --command "echo 'your message or script here'" \
  --deliver telegram
```

Under the hood this sets `delivery: { mode: "announce", channel: "telegram" }` — the output of the command is delivered to you via Telegram when the job completes. Do not instruct the agent itself to send a message to a username.

---

## Need to start completely fresh

```bash
# Delete the worker
npx wrangler delete --name moltbot-sandbox

# Delete the 1Password item
op item delete "moltworker" --vault Private

# Re-run the deployment
cd /path/to/deploy-new-moltworker
./deploy.sh
```
