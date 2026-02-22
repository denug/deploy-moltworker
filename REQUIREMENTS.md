# Requirements

Everything you need before running `deploy.sh`.

---

## 1. Computer

- **macOS** (recommended) or Linux
- Windows is not supported (scripts require bash)
- At least 2 GB free disk space

The `deploy.sh` script will automatically install all software tools (Homebrew, Node.js, Git, Docker Desktop, 1Password CLI, wrangler). You don't need to install anything manually, but Docker Desktop installation requires your Mac password when prompted.

---

## 2. Cloudflare Account — Workers Paid Plan

**Cost:** $5/month base + ~$30/month for the container running 24/7

**Sign up:** https://dash.cloudflare.com/sign-up

**Enable paid plan:**
1. Go to https://dash.cloudflare.com → Workers & Pages → Plans
2. Upgrade to the **Workers Paid** plan ($5/month)
3. This unlocks Cloudflare Containers (required for this project)

**Enable Cloudflare Containers:**
1. Go to https://dash.cloudflare.com → Workers → Containers
2. Click **Enable Containers**

**Create R2 bucket + API token:**
1. Go to R2 → Overview → Create bucket
2. Name it exactly: `moltbot-data`
3. Go to R2 → Manage R2 API Tokens → Create API token
4. Set permissions: **Object Read & Write**
5. Scope to bucket: `moltbot-data`
6. Copy the **Access Key ID** and **Secret Access Key**
   - ⚠️ Secret Access Key is shown ONCE — save it immediately

**Find your Zero Trust team domain:**
1. Go to https://one.dash.cloudflare.com
2. Settings → Custom Pages
3. Your team domain is the subdomain before `.cloudflareaccess.com`
   - Example: if it shows `myteam.cloudflareaccess.com`, your domain is `myteam.cloudflareaccess.com`

**Add yourself to Zero Trust access:**
1. Go to Zero Trust → Settings → Authentication
2. Add your email as an allowed user

---

## 3. Anthropic API Key

**Cost:** Pay-per-use (~$5-20/month for typical personal assistant usage)

1. Go to https://console.anthropic.com/settings/keys
2. Create a new API key
3. Copy it — starts with `sk-ant-api03-...`

---

## 4. 1Password

**Cost:** Free tier available, or $3/month for individuals

**Why:** All your secrets are stored in 1Password instead of in files. This keeps them secure and makes re-deployment easy.

1. Download 1Password: https://1password.com/downloads/
2. Create an account or sign in
3. The `deploy.sh` script handles the rest

---

## 5. Telegram Bot (optional)

Only needed if you want to chat with your AI assistant via Telegram.

1. Open Telegram on your phone or computer
2. Search for `@BotFather`
3. Send `/newbot`
4. Follow the prompts to name your bot
5. Copy the bot token (looks like `1234567890:AABBcc...`)

---

## 6. Browser Automation / CDP (optional)

No extra accounts or credentials required.

When `deploy.sh` asks **"Do you want browser automation (CDP) support?"**, answer `y`. The script auto-generates a `CDP_SECRET` and stores it in 1Password. The secret is set as a Cloudflare Worker secret automatically.

After deploy, use the CDP endpoints at `https://<your-worker>/cdp/...?secret=<CDP_SECRET>` to control a headless browser from within OpenClaw.

---

## Cost Summary

| Item | Monthly Cost |
|------|-------------|
| Cloudflare Workers Paid plan | $5.00 |
| Cloudflare Container (24/7) | ~$29.50 |
| Anthropic API (typical usage) | ~$5-20 |
| 1Password (optional) | $0-3 |
| **Total** | **~$40-57/month** |

**To reduce costs:** After deploying, set `SANDBOX_SLEEP_AFTER=10m` via the Cloudflare dashboard. The container will sleep when idle, reducing compute costs to ~$5-6/month. Note: waking from sleep takes 1-2 minutes.
