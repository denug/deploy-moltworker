# deploy-moltworker

One-command deploy of your own personal AI assistant (Claude-powered) on Cloudflare.

```bash
./deploy.sh
```

---

## What you get

- Personal AI assistant accessible from any browser
- Telegram bot integration
- Persistent memory across sessions
- Web admin dashboard
- ~$35/month to run 24/7

---

## Before you start — set these up first

You need accounts and credentials from **four services** before running the script. The script will prompt you for each.

### 1. Anthropic (Claude AI)
- Create account at [console.anthropic.com](https://console.anthropic.com)
- Add a payment method
- Generate an API key at Settings → API Keys

### 2. Cloudflare (hosting)
- Create account at [dash.cloudflare.com](https://dash.cloudflare.com)
- **Upgrade to the Workers Paid plan** ($5/mo) — required for containers
- Create an R2 bucket named exactly **`moltbot-data`** (R2 → Create bucket)
- Create R2 API credentials (R2 → Manage R2 API Tokens → Create API Token, Object Read & Write)
- Set up a Zero Trust team (one.dash.cloudflare.com → Settings → Custom Pages — note your team domain)

### 3. 1Password (secrets manager)
- Install [1Password](https://1password.com) desktop app
- Install the [1Password CLI](https://developer.1password.com/docs/cli/get-started): `brew install 1password-cli`
- Sign in: `op signin`

### 4. Telegram (optional, for chat)
- Message [@BotFather](https://t.me/botfather) on Telegram
- Send `/newbot` and follow prompts to get a bot token

---

## Deploy

```bash
./deploy.sh
```

Takes ~10 minutes. The script installs tools, collects all credentials once upfront, stores them in 1Password, and deploys everything.

---

## After deploying

Your assistant is live at:
```
https://moltbot-sandbox.<your-subdomain>.workers.dev/?token=<your-token>
```

Your gateway token is in 1Password → **Private → moltworker**.

First visit may take 1–2 minutes (container cold start). Visit `/_admin/` to pair your Telegram account.

---

## Redeploying / updating

```bash
cd ~/moltworker
git pull
./scripts/set-secrets.sh && npm run deploy
```

A daily cron job inside your assistant will notify you via Telegram when a new version is available.

---

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and fixes.
