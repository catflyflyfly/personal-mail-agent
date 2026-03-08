# Catfly Spam Filter

Self-hosted spam filter for Gmail/Outlook IMAP accounts. Scans incoming mail with SpamAssassin, moves spam to a junk folder, and learns from corrections.

## How it works

```
INBOX (IMAP) --> scanner fetches UNSEEN --> SpamAssassin check --> spam? --> move to Junk
                                                               --> ham?  --> leave in INBOX
```

Two Docker services:
- **scanner** — imapfilter (Lua) connects to your IMAP accounts, fetches mail, pipes through SpamAssassin, moves spam
- **spamassassin** — spamd daemon with Bayes learning, DNS blocklists, and custom rules

## Setup

1. Copy and edit the config:

```bash
cp config.lua.example config.lua
```

2. Fill in your IMAP credentials:

```lua
config = {
    scan_interval = 300,
    spam_threshold = 5.0,
    dry_run = true,  -- set false when ready

    defaults = {
        port = 993,
        spam_folder = "Junk",
        learn_spam_folder = "LearnSpam",
        learn_ham_folder = "LearnHam",
    },

    accounts = {
        {
            host = "imap.gmail.com",
            user = "you@gmail.com",
            password = "your-app-password",
            spam_folder = "[Gmail]/Spam",
        },
    },
}
```

3. Start:

```bash
docker compose up -d
```

4. Check logs:

```bash
docker compose logs -f scanner
```

## Gmail setup

Gmail requires an App Password (not your regular password):
1. Enable 2-Step Verification on your Google account
2. Go to https://myaccount.google.com/apppasswords
3. Generate an app password, use it in `config.lua`

Gmail's spam folder is `[Gmail]/Spam`, not `Junk`.

## Training

### Automatic (via IMAP folders)

The scanner checks two training folders on each run:

- **LearnSpam** — move misclassified ham here, scanner learns it as spam and moves to Junk
- **LearnHam** — move misclassified spam here, scanner learns it as ham and moves to INBOX

Just drag messages into these folders from your mail client. The next scan picks them up.

### Manual

```bash
docker compose exec spamassassin sa-learn --spam /path/to/spam.eml
docker compose exec spamassassin sa-learn --ham /path/to/ham.eml
```

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `scan_interval` | `300` | Seconds between scans |
| `spam_threshold` | `5.0` | SpamAssassin score threshold |
| `dry_run` | `false` | Log only, don't move or learn |
| `defaults.spam_folder` | `Junk` | Where to move spam |
| `defaults.learn_spam_folder` | `LearnSpam` | Drop misclassified ham here |
| `defaults.learn_ham_folder` | `LearnHam` | Drop misclassified spam here |

Per-account overrides (e.g. `spam_folder`) take precedence over defaults.

## Multi-account

Add more accounts to the `accounts` table:

```lua
accounts = {
    { host = "imap.gmail.com", user = "one@gmail.com", password = "...", spam_folder = "[Gmail]/Spam" },
    { host = "outlook.office365.com", user = "two@outlook.com", password = "..." },
},
```

## Operations

```bash
docker compose up -d          # start
docker compose logs -f scanner # follow logs
docker compose down            # stop (keeps training data)
docker compose down -v         # stop and wipe training data
```

## Files

```
config.lua                  # your credentials and settings (git-ignored)
docker-compose.yml          # service definitions
spamassassin/local.cf       # SpamAssassin rules and Bayes config
scanner/
  Dockerfile                # Ubuntu + imapfilter + spamc
  config.lua                # scanning logic (Lua)
  entrypoint.sh             # sleep loop
```
