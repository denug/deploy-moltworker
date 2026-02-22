# deploy-new-moltworker — Claude Code Context

## What This Is
Automated deployment kit for moltworker (OpenClaw personal AI assistant on Cloudflare).
Goal: zip this folder and hand it to a non-technical friend for a 1-click deploy.

## Repo Being Deployed
https://github.com/denug/moltbot-sandbox

## Files
- `deploy.sh` — single entry point, fully automated e2e deploy
- `README.md` — user-facing overview
- `REQUIREMENTS.md` — all accounts, tools, costs with links
- `TROUBLESHOOTING.md` — common issues and fixes
- `DEPLOY_LOG.md` — running log of issues found during debug/testing
- `test/run.sh` — non-interactive smoke test using existing 1Password credentials
- `test/cleanup.sh` — tears down the test worker and local clone

## Agent Role
When working in this folder, your job is to:
1. **Track all issues** found during deploy testing in `DEPLOY_LOG.md`
2. **Fix deploy.sh** when issues are found — keep it always runnable
3. **Update docs** when steps change or new issues are discovered
4. **Never break the deploy path** — if changing deploy.sh, test the logic first

## Current Status
See `DEPLOY_LOG.md` for latest status and known issues.

## Key Design Decisions
- All prompts collected UPFRONT before any automation runs
- Secrets stored in 1Password immediately — never written to disk as plaintext
- CF Access AUD requires one manual browser step (cannot be fully automated)
- MOLTBOT_GATEWAY_TOKEN is auto-generated (never prompted)
- Script clones repo to `~/moltworker/` on the user's machine

## Testing Notes
- To test without deploying: comment out `npm run deploy` lines in deploy.sh
- To re-run cleanly: `op item delete "moltworker" --vault Private` first
- wrangler must be authenticated: `npx wrangler whoami`
