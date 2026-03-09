local mime = require("mime")

local secret_keys = { password = true, token = true, secret = true, key = true }

local function dump(t, indent)
    indent = indent or ""
    for k, v in pairs(t) do
        if type(v) == "table" then
            print(indent .. tostring(k) .. ":")
            dump(v, indent .. "  ")
        elseif secret_keys[k] then
            print(indent .. tostring(k) .. " = ******")
        else
            print(indent .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

local function to_utf8(str, charset)
    charset = charset:upper()
    if charset == "UTF-8" or charset == "UTF8" or charset == "US-ASCII" then
        return str
    end
    local tmpfile = os.tmpname()
    local file = assert(io.open(tmpfile, "wb"))
    file:write(str)
    file:close()
    local _, result = pipe_from("iconv -f " .. charset .. " -t UTF-8 < " .. tmpfile .. " 2>/dev/null")
    os.remove(tmpfile)
    return result or str
end

-- Decode RFC 2047 MIME encoded-words (=?charset?B?...?= and =?charset?Q?...?=)
local function mime_decode(s)
    return s:gsub("=%?([^%?]+)%?([BbQq])%?([^%?]*)%?=", function(charset, encoding, data)
        local decoded
        if encoding:upper() == "B" then
            decoded = mime.unb64(data)
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

local function get_subject(mbox, uid)
    local field = mbox[uid]:fetch_field("Subject") or ""
    local subject = field:gsub("^Subject:%s*", "")
    subject = subject:gsub("%?=%s+=%?", "?==?")
    subject = subject:gsub("%s+", " ")
    return mime_decode(subject)
end

local function check_spam(raw)
    local tmpfile = os.tmpname()
    local file = assert(io.open(tmpfile, "w"))
    file:write(raw)
    file:close()

    local _, output = pipe_from("spamc -d spamassassin -p 783 -R < " .. tmpfile)
    os.remove(tmpfile)

    if output == nil then return 0 end
    return tonumber(output:match("^([%d%.%-]+)/")) or 0
end

local function process(account, acct_cfg, config)
    local defaults = config.defaults or {}
    local threshold = config.spam_threshold or 5.0
    local dry_run = config.dry_run or false
    local rescan = config.rescan or false
    local spam_folder = acct_cfg.spam_folder or defaults.spam_folder or "Junk"
    local learn_spam = acct_cfg.learn_spam_folder or defaults.learn_spam_folder or "LearnSpam"
    local learn_ham = acct_cfg.learn_ham_folder or defaults.learn_ham_folder or "LearnHam"

    print("Processing: " .. acct_cfg.user)

    account:create_mailbox(spam_folder)
    account:create_mailbox(learn_spam)
    account:create_mailbox(learn_ham)

    -- Scan INBOX and spam folder for unseen messages not yet processed
    local inbox_unseen = account.INBOX:is_unseen()
    local spam_unseen = account[spam_folder]:is_unseen()
    print("  INBOX unseen: " .. #inbox_unseen)
    print("  " .. spam_folder .. " unseen: " .. #spam_unseen)

    local unseen
    if rescan then
        unseen = inbox_unseen + spam_unseen
    else
        unseen = (inbox_unseen * account.INBOX:has_unkeyword("SpamChecked"))
               + (spam_unseen * account[spam_folder]:has_unkeyword("SpamChecked"))
    end
    print("  To scan: " .. #unseen)

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
                if raw then pipe_to("spamc -d spamassassin -p 783 -L spam", raw) end
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
                if raw then pipe_to("spamc -d spamassassin -p 783 -L ham", raw) end
            end
        end
        if not dry_run then
            to_learn_ham:add_flags({"SpamChecked"})
            to_learn_ham:move_messages(account.INBOX)
        end
    end
end

local function main()
    dofile("/app/config.lua")
    print("Config:")
    dump(CONFIG)

    if CONFIG.dry_run then
        print("*** DRY RUN MODE - no messages will be moved or learned ***")
    end

    local defaults = CONFIG.defaults or {}
    for _, acct_cfg in ipairs(CONFIG.accounts) do
        local account = IMAP {
            server = acct_cfg.host,
            username = acct_cfg.user,
            password = acct_cfg.password,
            port = acct_cfg.port or defaults.port or 993,
            ssl = "auto",
        }
        process(account, acct_cfg, CONFIG)
    end
end

main()
