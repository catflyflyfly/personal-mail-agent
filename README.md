# Personal Mail Agent

Self-hosted mail agent for Gmail/Outlook IMAP accounts. Screens incoming mail with SpamAssassin, moves spam to a junk folder, and learns from your corrections.

## How it works

```
INBOX --> fetch UNSEEN --> SpamAssassin check --> spam? --> move to Junk
                                              --> ham?  --> leave in INBOX
```

Two Docker services:
- **personal-mail-agent** — connects to your IMAP accounts, fetches mail, pipes through SpamAssassin, moves spam
- **spamassassin** — spamd daemon with Bayes learning, DNS blocklists, and custom rules

## Setup

```bash
curl -fsSL https://raw.githubusercontent.com/catflyflyfly/personal-mail-agent/main/setup.sh | sh
```

This downloads `docker-compose.yml` and config files into the current directory. Then:

1. Edit `config/agent.lua` with your IMAP credentials
2. Run `docker compose up -d`

## Gmail setup

Gmail requires an App Password (not your regular password):
1. Enable 2-Step Verification on your Google account
2. Go to https://myaccount.google.com/apppasswords
3. Generate an app password, use it in `config/agent.lua`

Gmail's spam folder is `[Gmail]/Spam`, not `Junk`.

## Training

### Automatic (via IMAP folders)

The agent checks two training folders on each run:

- **LearnSpam** — move misclassified ham here, agent learns it as spam and moves to Junk
- **LearnHam** — move misclassified spam here, agent learns it as ham and moves to INBOX

Just drag messages into these folders from your mail client. The next scan picks them up.

### Manual

```bash
docker compose exec spamassassin sa-learn --spam /path/to/spam.eml
docker compose exec spamassassin sa-learn --ham /path/to/ham.eml
```

## Configuration

| Option                       | Default     | Description                   |
| ---------------------------- | ----------- | ----------------------------- |
| `scan_interval`              | `300`       | Seconds between scans         |
| `spam_threshold`             | `5.0`       | SpamAssassin score threshold  |
| `dry_run`                    | `false`     | Log only, don't move or learn |
| `defaults.spam_folder`       | `Junk`      | Where to move spam            |
| `defaults.learn_spam_folder` | `LearnSpam` | Drop misclassified ham here   |
| `defaults.learn_ham_folder`  | `LearnHam`  | Drop misclassified spam here  |

Per-account overrides (e.g. `spam_folder`) take precedence over defaults.

## SpamAssassin config

All `*.cf` files in `config/spamassassin/` are mounted into the SpamAssassin container. Drop any `.cf` file there and it gets picked up automatically.

Included files:

- **`local.cf`** — main SpamAssassin config: scoring rules, Bayes settings, network checks. This is committed to the repo.
- **`custom.cf`** — your personal overrides: allow/blocklists, score tweaks, extra rules. Copy from `custom.cf.example` to get started:

```bash
cp config/spamassassin/custom.cf.example config/spamassassin/custom.cf
```

```
whitelist_from  alerts@mynas.local
blacklist_from  *@sketchy-domain.com
```

Whitelisted senders bypass spam checks (-100 points). Blacklisted senders are always marked as spam (+100 points).

### Bayes scoring

The default `local.cf` weighs Bayes training heavier than SpamAssassin's defaults. This means your LearnSpam/LearnHam training has more influence over the final score than DNS blocklists and header checks. The tradeoff is that a few bad training examples could have more impact — be deliberate about what you put in the training folders.

## Multi-account

Add more accounts to the `accounts` table:

```lua
accounts = {
    { host = "imap.gmail.com", user = "one@gmail.com", password = "...", spam_folder = "[Gmail]/Spam" },
    { host = "outlook.office365.com", user = "two@outlook.com", password = "..." },
},
```

## Local development

To build from source instead of pulling the pre-built image, uncomment `build: .` in `docker-compose.yml`:

```yaml
image: ghcr.io/catflyflyfly/personal-mail-agent:latest
build: .  # uncomment this line
```

## Operations

```bash
docker compose up -d                        # start
docker compose logs -f personal-mail-agent  # follow logs
docker compose down                         # stop (keeps training data)
docker compose down -v                      # stop and wipe training data
```

## Files

```
Dockerfile                      # Ubuntu + imapfilter + spamc
main.lua                        # agent logic
entrypoint.sh                   # sleep loop
config/
  agent.lua.example             # agent config template
  spamassassin/
    local.cf                    # SpamAssassin rules and Bayes config
    custom.cf.example           # custom rules template
docker-compose.yml              # service definitions
```
