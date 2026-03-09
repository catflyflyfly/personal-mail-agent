dofile("/app/config.lua")

local defaults = config.defaults or {}
local threshold = config.spam_threshold or 5.0
local dry_run = config.dry_run or false

if dry_run then
    print("*** DRY RUN MODE - no messages will be moved or learned ***")
end

function check_spam(raw)
    local tmpfile = os.tmpname()
    local f = io.open(tmpfile, "w")
    f:write(raw)
    f:close()

    local exit_code, output = pipe_from("spamc -d spamassassin -R < " .. tmpfile)
    os.remove(tmpfile)

    if output == nil then return 0 end
    return tonumber(output:match("^([%d%.%-]+)/")) or 0
end

-- Base64 decode
local b64 = {}
for i, c in ipairs({'A','B','C','D','E','F','G','H','I','J','K','L','M',
    'N','O','P','Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d',
    'e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u',
    'v','w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/'}) do
    b64[string.byte(c)] = i - 1
end

function base64_decode(s)
    local out = {}
    local val, bits = 0, 0
    for i = 1, #s do
        local v = b64[string.byte(s, i)]
        if v then
            val = val * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                table.insert(out, string.char(math.floor(val / 2^bits) % 256))
                val = val % (2^bits)
            end
        end
    end
    return table.concat(out)
end

-- Convert charset to UTF-8 via iconv
function to_utf8(str, charset)
    charset = charset:upper()
    if charset == "UTF-8" or charset == "UTF8" or charset == "US-ASCII" then
        return str
    end
    local tmpfile = os.tmpname()
    local f = io.open(tmpfile, "wb")
    f:write(str)
    f:close()
    local _, result = pipe_from("iconv -f " .. charset .. " -t UTF-8 < " .. tmpfile .. " 2>/dev/null")
    os.remove(tmpfile)
    return result or str
end

-- Decode RFC 2047 MIME encoded-words (=?charset?B?...?= and =?charset?Q?...?=)
function mime_decode(s)
    return s:gsub("=%?([^%?]+)%?([BbQq])%?([^%?]*)%?=", function(charset, encoding, data)
        local decoded
        if encoding:upper() == "B" then
            decoded = base64_decode(data)
        elseif encoding:upper() == "Q" then
            decoded = data:gsub("_", " "):gsub("=(%x%x)", function(hex)
                return string.char(tonumber(hex, 16))
            end)
        else
            return data
        end
        return to_utf8(decoded, charset)
    end)
end

function get_subject(mbox, uid)
    local field = mbox[uid]:fetch_field("Subject") or ""
    -- Unfold header (remove CRLF + whitespace between encoded words)
    local subject = field:gsub("^Subject:%s*", "")
    subject = subject:gsub("%?=%s+=%?", "?==?")
    subject = subject:gsub("%s+", " ")
    return mime_decode(subject)
end

function process(account, acct_cfg)
    local spam_folder = acct_cfg.spam_folder or defaults.spam_folder or "Junk"
    local learn_spam = acct_cfg.learn_spam_folder or defaults.learn_spam_folder or "LearnSpam"
    local learn_ham = acct_cfg.learn_ham_folder or defaults.learn_ham_folder or "LearnHam"

    print("Processing: " .. acct_cfg.user)

    account:create_mailbox(spam_folder)
    account:create_mailbox(learn_spam)
    account:create_mailbox(learn_ham)

    -- Scan INBOX for unseen messages not yet processed
    local unseen = account.INBOX:is_unseen() * account.INBOX:has_unkeyword("SpamChecked")
    print("  INBOX: " .. #unseen .. " to scan")

    local spam_set = Set()
    local ham_set = Set()
    for _, msg in ipairs(unseen) do
        local mbox, uid = table.unpack(msg)
        local raw = mbox[uid]:fetch_message()
        if raw then
            local subject = get_subject(mbox, uid)
            local score = check_spam(raw)

            if score >= threshold then
                print(string.format("  SPAM (%.1f): %s", score, subject))
                table.insert(spam_set, {mbox, uid})
            else
                print(string.format("  HAM  (%.1f): %s", score, subject))
                table.insert(ham_set, {mbox, uid})
            end
        end
    end

    -- Mark ham as processed so we don't rescan
    if #ham_set > 0 and not dry_run then
        Set(ham_set):add_flags({"SpamChecked"})
    end

    if #spam_set > 0 and not dry_run then
        Set(spam_set):move_messages(account[spam_folder])
    end

    -- Learn from LearnSpam folder
    local to_learn_spam = account[learn_spam]:select_all()
    if #to_learn_spam > 0 then
        print("  " .. learn_spam .. ": " .. #to_learn_spam .. " to learn as spam")
        for _, msg in ipairs(to_learn_spam) do
            local mbox, uid = table.unpack(msg)
            print("    -> " .. get_subject(mbox, uid))
            if not dry_run then
                local raw = mbox[uid]:fetch_message()
                if raw then pipe_to("spamc -d spamassassin -L spam", raw) end
            end
        end
        if not dry_run then
            to_learn_spam:move_messages(account[spam_folder])
        end
    end

    -- Learn from LearnHam folder
    local to_learn_ham = account[learn_ham]:select_all()
    if #to_learn_ham > 0 then
        print("  " .. learn_ham .. ": " .. #to_learn_ham .. " to learn as ham")
        for _, msg in ipairs(to_learn_ham) do
            local mbox, uid = table.unpack(msg)
            print("    -> " .. get_subject(mbox, uid))
            if not dry_run then
                local raw = mbox[uid]:fetch_message()
                if raw then pipe_to("spamc -d spamassassin -L ham", raw) end
            end
        end
        if not dry_run then
            to_learn_ham:add_flags({"SpamChecked"})
            to_learn_ham:move_messages(account.INBOX)
        end
    end
end

for _, acct_cfg in ipairs(config.accounts) do
    local account = IMAP {
        server = acct_cfg.host,
        username = acct_cfg.user,
        password = acct_cfg.password,
        port = acct_cfg.port or defaults.port or 993,
        ssl = "auto",
    }
    process(account, acct_cfg)
end
