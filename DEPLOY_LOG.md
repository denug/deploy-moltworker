# Deploy Log

Running log of issues, fixes, and updates discovered during deployment testing.
Most recent entries at the top.

---

## 2026-02-21 — Initial build

### Status: TESTED — end-to-end verified working (2026-02-22)

### What was built
- `deploy.sh` — full e2e automated deploy script
- `README.md`, `REQUIREMENTS.md`, `TROUBLESHOOTING.md` — user docs
- `CLAUDE.md` — agent context for future sessions

### Known gaps / not yet tested
- [ ] `deploy.sh` — CF account ID auto-detection via `wrangler whoami --json` (format may vary)
- [ ] `deploy.sh` — `op item edit` with conditional `${TELEGRAM_BOT_TOKEN:+...}` syntax needs bash validation
- [ ] `deploy.sh` — worker subdomain auto-detection (grep for workers.dev) may be fragile
- [ ] Full end-to-end test not yet run
- [ ] CF Access AUD step — browser open + paste flow not tested
- [ ] R2 bucket auto-creation not handled (assumes bucket already exists)

### Next steps
- [ ] Run `./deploy.sh` on a clean machine or test account
- [ ] Fix any issues found and log them here
- [ ] Validate all 9 phases complete successfully
- [ ] Test re-run behavior (idempotent — should not fail if run twice)

---

## 2026-02-21 — Docker not installed

### Issue
`npm run deploy` failed with: "The Docker CLI could not be launched."

### Root cause
Cloudflare Sandbox requires Docker to build the container image locally before deploying. Docker Desktop was not installed.

### Fix
- Added Docker Desktop to REQUIREMENTS.md as a prerequisite
- Updated `deploy.sh` Phase 2 to install and check Docker
- User must install via: `brew install --cask docker` (requires interactive sudo)
- Must open Docker Desktop and wait for daemon to start before deploying

### Status
FIXED in deploy.sh — Docker install added to Phase 2 prereqs check

---

## 2026-02-22 — Telegram DMs silently blocked on fresh deploy

### Issue
Telegram bot connected and healthy, but all DMs from users were silently ignored. No error visible in logs.

### Root cause
`dmPolicy` defaults to `allowlist` in OpenClaw config. With an empty allowlist, every DM is blocked silently — the sender receives no response and no error. On a fresh deploy the allowlist is empty.

### Fix
When a new user messages the bot, they get a pairing code. Approve it:
```bash
# Check pending pairings
open https://<worker-url>/debug/cli?cmd=openclaw%20pairing%20list%20telegram
# Approve
open https://<worker-url>/debug/cli?cmd=openclaw%20pairing%20approve%20telegram%20<CODE>
```
Or set `TELEGRAM_DM_POLICY=allow` as a wrangler secret to allow all DMs without pairing.

### Status
KNOWN BEHAVIOR — approve pairings or set open policy

---

## 2026-02-22 — AI silent / no response to chat messages (401 from Anthropic)

### Issue
After restoring from R2, all chat messages were silently processed (runs completed in ~100-200ms) with no AI response. Telegram showed `HTTP 401: authentication_error: invalid x-api-key`.

### Root cause
Two layered bugs in `start-openclaw.sh`:

**Bug 1 — API key never refreshed from env vars when config exists in R2**
`openclaw onboard` (which sets the API key) only runs when no config file exists:
```bash
if [ ! -f "$CONFIG_FILE" ]; then
    openclaw onboard ... --anthropic-api-key $ANTHROPIC_API_KEY
```
On subsequent boots, R2 restores `auth-profiles.json` with whatever key was last saved — which could be old, rotated, or invalid. The `ANTHROPIC_API_KEY` wrangler secret was never applied.

**Bug 2 — Patch wrote to wrong location in auth-profiles.json**
The fix attempted to patch `auth-profiles.json` but used the wrong structure:
- Wrote to: `authProfiles['anthropic:default'].apiKey` (root level, wrong field name)
- OpenClaw reads from: `authProfiles.profiles['anthropic:default'].key` (nested, different field name)

### Fix
Added a patch step to `start-openclaw.sh` that runs on every boot, after R2 restore, writing `ANTHROPIC_API_KEY` to the correct location:
```javascript
authProfiles.profiles['anthropic:default'] = Object.assign(
    authProfiles.profiles['anthropic:default'] || {},
    { type: 'api_key', provider: 'anthropic', key: process.env.ANTHROPIC_API_KEY }
);
```

### How to diagnose
1. Check `/debug/logs` for `Auth profiles patched with ANTHROPIC_API_KEY` in startup output
2. Check `/debug/cli?cmd=cat%20/root/.openclaw/agents/main/agent/auth-profiles.json` — look for `profiles['anthropic:default'].key` having the correct value
3. Confirm with `/debug/cli?cmd=openclaw%20models` — shows `anthropic:default=sk-ant-...`

### Status
FIXED in `start-openclaw.sh` (deployed 2026-02-22, image a92c02d6)

---

## Log format for future entries

```
## YYYY-MM-DD — description

### Issue
What went wrong / what was observed

### Root cause
Why it happened

### Fix
What was changed (file:line if applicable)

### Status
FIXED / WORKAROUND / KNOWN ISSUE / WONT FIX
```
