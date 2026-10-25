--[[
    RC-Translator: Real Language Chat Translator for World of Warcraft
    Author: RobClark
    Version: see .toc (## Version)
    
    Core engine: Handles chat event hooking, translation logic,
    dictionary management, and saved variables.
]]

-- Addon namespace
local ADDON_NAME = "RC-Translator"
RC_Translator = RC_Translator or {}
local T = RC_Translator

-- Version. Primary source is the .toc (so it can't drift); RCT_VERSION is a
-- fallback kept in lockstep with the .toc for clients where GetAddOnMetadata
-- returns nil. Both are bumped together at package time.
local RCT_VERSION = "3.4.61"
local _getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local _tocVer = _getMeta and _getMeta(ADDON_NAME, "Version")
T.version = (_tocVer and _tocVer ~= "" and _tocVer) or RCT_VERSION

-- Dictionary registry: language code -> { name, dictionary, reverse }
T.Languages = {}

-- Active translation settings (loaded from SavedVariables)
T.defaults = {
    enabled = true,
    targetLang = "es",           -- Overridden on first run by client locale (see ApplyDefaults)
    showOriginal = true,         -- Show original message alongside translation
    autoTranslate = false,       -- Button mode: [T] opens translation in the translator window
    showDetectionInfo = true,    -- Show detection method and confidence in translations
    autoTranslateToIM = false,   -- Send auto-translations to IM window instead of chat
    translatedTab = true,        -- Show a dedicated "Translated" chat tab (on by default)
    translatedTabShowOriginal = false,   -- Tab option: print the original line under each translation
    translatedTabTranslatedOnly = false, -- Tab option: only show messages that were actually translated
    tabChannels = {              -- Tab option: which channels feed the Translated tab
        -- Trade and LookingForGroup default OFF (they're spammy); the rest on.
        CHANNEL_GENERAL = true, CHANNEL_TRADE = false, CHANNEL_LFG = false,
        CHANNEL_WORLD = true, CHANNEL_OTHER = true,
        SAY = true, YELL = true, GUILD = true, OFFICER = true,
        PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true,
        EMOTE = true, GMOTD = true,
    },
    customChannels = {},         -- Tab option: user-added channel names -> on/off
    tabMessageGroups = {         -- Tab option: WoW message categories fed into the tab (opt-in)
        LOOT = false, MONEY = false, CURRENCY = false, SKILL = false, SYSTEM = false,
        XP = false, REP = false, HONOR = false, ACHIEVEMENT = false, BG = false,
        NPC = false, PET = false, PETBATTLE = false,
    },
    translateOutgoing = true,     -- Translate messages typed in the Translated tab before sending
    sendLang = nil,              -- Language to translate your outgoing messages into (nil = client locale)
    tabClassColors = true,       -- Tab option: class-color player names, like regular chat
    translationColor = {0.5, 1.0, 0.5}, -- Light green for translated text
    channels = RCT_Compat.GetDefaultChannelSettings(),  -- version-aware channel list
    enabledLanguages = {},       -- Which dictionary files to load (populated on first load)
    secretUnlocked = false,      -- Konami code easter egg
    sourceLang = "auto",         -- Source language (outgoing: "auto" for auto-detect, or a lang code)
    incomingSourceLang = "auto", -- Incoming pane source language ("auto" or lang code)
    incomingTargetLang = "en",   -- Incoming pane target language
    outgoingEnabled = false,     -- Translate outgoing messages
    outgoingLang = "es",         -- Language for outgoing translation
    ignoreWords = {              -- Words to skip during detection and translation
        -- Technical gaming abbreviations (universal, no translation needed)
        "wp", "brb", "afk", "bio",
        "glhf", "lfg", "lfm", "lf", "wts", "wtb", "wtt",
        "dps", "hps", "aoe", "dot", "hot", "cc", "cd", "gcd",
        "imo", "imho", "tbh", "ngl", "idk", "smh", "fyi",
        "ty", "tyvm", "np", "yw", "pls", "plz", "thx", "kk",
        "omg", "omw", "otw", "rn", "asap", "eta",
        "pvp", "pve", "rp", "bg", "rb", "ab", "wsg", "av",
        "bis", "gs", "ilvl", "os", "ms", "ui",
        "fps", "ping", "lag",
        "lf1m", "lf2m", "lf3m", "lfr",
        "inc", "oom", "brt", "gtg", "g2g",
        "op", "rng", "meta", "pog",
    },
    minimap = {
        position = 220,
        hide = false,
        locked = false,
    },
    customDictionary = {},  -- { [langCode] = { [english] = "translation", ... }, ... }
}

-- ============================================================
-- IGNORE LIST MANAGEMENT
-- ============================================================

T.IgnoreLookup = {}

function T:RebuildIgnoreLookup()
    self.IgnoreLookup = {}
    if self.db and self.db.ignoreWords then
        for _, word in ipairs(self.db.ignoreWords) do
            self.IgnoreLookup[word:lower()] = true
        end
    end
end

function T:IsIgnoredWord(word)
    return self.IgnoreLookup[word:lower()] or false
end

function T:AddIgnoreWord(word)
    if not word or word == "" then return false end
    word = word:lower():gsub("%s+", "")
    if self:IsIgnoredWord(word) then return false end
    table.insert(self.db.ignoreWords, word)
    self.IgnoreLookup[word] = true
    return true
end

function T:RemoveIgnoreWord(word)
    if not word or word == "" then return false end
    word = word:lower():gsub("%s+", "")
    if not self:IsIgnoredWord(word) then return false end
    for i, w in ipairs(self.db.ignoreWords) do
        if w:lower() == word then
            table.remove(self.db.ignoreWords, i)
            self.IgnoreLookup[word] = nil
            return true
        end
    end
    return false
end

-- ============================================================
-- CUSTOM DICTIONARY MANAGEMENT
-- ============================================================

--- Add a custom word/phrase pair to a language dictionary.
--- Persists in SavedVariables and injects into the live dictionary + reverse lookup.
function T:AddCustomEntry(langCode, english, translation)
    if not langCode or not english or not translation then return false, "Missing arguments" end
    english = english:lower():gsub("^%s+", ""):gsub("%s+$", "")
    translation = translation:gsub("^%s+", ""):gsub("%s+$", "")
    if english == "" or translation == "" then return false, "Empty word or translation" end
    if not self.Languages[langCode] then return false, "Unknown language: " .. langCode end
    if not self:EnsureLanguageLoaded(langCode) then
        return false, "Dictionary not installed: " .. langCode
    end

    -- Store in SavedVariables
    if not self.db.customDictionary then self.db.customDictionary = {} end
    if not self.db.customDictionary[langCode] then self.db.customDictionary[langCode] = {} end
    self.db.customDictionary[langCode][english] = translation

    -- Inject into live dictionary (english key → foreign value)
    self.Languages[langCode].dictionary[english] = translation
    -- Inject into reverse lookup (foreign → english)
    self.Languages[langCode].reverse[translation:lower()] = english
    -- Update word count
    local count = 0
    for _ in pairs(self.Languages[langCode].dictionary) do count = count + 1 end
    self.Languages[langCode].wordCount = count

    return true
end

--- Remove a custom word from a language dictionary.
function T:RemoveCustomEntry(langCode, english)
    if not langCode or not english then return false, "Missing arguments" end
    english = english:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if english == "" then return false, "Empty word" end
    if not self.Languages[langCode] then return false, "Unknown language: " .. langCode end

    if not self:EnsureLanguageLoaded(langCode) then
        return false, "Dictionary not installed: " .. langCode
    end

    -- Check it exists in custom dictionary
    if not self.db.customDictionary or not self.db.customDictionary[langCode]
       or not self.db.customDictionary[langCode][english] then
        return false, "Not a custom entry"
    end

    -- Remove reverse lookup
    local oldTranslation = self.db.customDictionary[langCode][english]
    if oldTranslation then
        self.Languages[langCode].reverse[oldTranslation:lower()] = nil
    end

    -- Remove from live dictionary
    self.Languages[langCode].dictionary[english] = nil

    -- Remove from SavedVariables
    self.db.customDictionary[langCode][english] = nil

    -- Update word count
    local count = 0
    for _ in pairs(self.Languages[langCode].dictionary) do count = count + 1 end
    self.Languages[langCode].wordCount = count

    return true
end

--- Load all custom entries from SavedVariables into live dictionaries.
--- Called once on ADDON_LOADED after dictionaries are registered.
function T:LoadCustomDictionary()
    if not self.db or not self.db.customDictionary then return end
    local total = 0
    for langCode, entries in pairs(self.db.customDictionary) do
        -- Only inject into dictionaries that are actually resident. Anything else
        -- is replayed by ApplyPendingCustomWords() the moment its sub-addon loads.
        if self:IsLanguageLoaded(langCode) then
            for english, translation in pairs(entries) do
                self.Languages[langCode].dictionary[english] = translation
                self.Languages[langCode].reverse[translation:lower()] = english
                total = total + 1
            end
            -- Recount
            local count = 0
            for _ in pairs(self.Languages[langCode].dictionary) do count = count + 1 end
            self.Languages[langCode].wordCount = count
        end
    end
    if total > 0 and T.debugMode then
        print("|cFF00FF00[RC-Translator]|r Loaded " .. total .. " custom dictionary entries.")
    end
end

--- Replay this language's saved custom entries into a dictionary that has just
--- been loaded on demand. Without this, custom words would silently vanish for
--- any language that was not resident at ADDON_LOADED time.
function T:ApplyPendingCustomWords(langCode)
    if not self.db or not self.db.customDictionary then return 0 end
    local entries = self.db.customDictionary[langCode]
    if not entries then return 0 end
    local d = self.Languages[langCode]
    if not d or not d.dictionary then return 0 end

    local n = 0
    for english, translation in pairs(entries) do
        d.dictionary[english] = translation
        d.reverse[translation:lower()] = english
        n = n + 1
    end
    local count = 0
    for _ in pairs(d.dictionary) do count = count + 1 end
    d.wordCount = count
    return n
end

--- Get count of custom entries for a language (or all languages if nil)
function T:GetCustomEntryCount(langCode)
    if not self.db or not self.db.customDictionary then return 0 end
    if langCode then
        if not self.db.customDictionary[langCode] then return 0 end
        local count = 0
        for _ in pairs(self.db.customDictionary[langCode]) do count = count + 1 end
        return count
    else
        local count = 0
        for _, entries in pairs(self.db.customDictionary) do
            for _ in pairs(entries) do count = count + 1 end
        end
        return count
    end
end

-- ============================================================
-- DICTIONARY REGISTRATION
-- ============================================================

T.PackedDicts = {}

--- Called by each Dictionaries/<code>.lua at load. Stores ONLY the raw string.
--- No tables are built here, so 33 dictionaries cost ~11 MB of flat string
--- rather than ~49 MB of Lua tables.
function RCT_PACK(code, name, blob)
    local T = RC_Translator
    if not T then return end
    T.PackedDicts[code] = blob
    local d = T.Languages[code]
    if d then
        d.name = d.name or name
    else
        T.Languages[code] = { code = code, name = name, loaded = false, wordCount = 0 }
    end
end

function T:RegisterDictionary(code, name, dict, hidden)
    if not code or not dict then return end

    local reverse = {}
    for eng, trans in pairs(dict) do
        if type(trans) == "string" and trans ~= "" then
            reverse[trans:lower()] = eng
        end
    end

    local count = 0
    for _ in pairs(dict) do count = count + 1 end

    -- Promote the existing stub in place (Languages.lua pre-created it) so any
    -- reference already handed out to the UI stays valid.
    local entry = self.Languages[code] or {}
    entry.name       = name or entry.name
    entry.code       = code
    entry.dictionary = dict
    entry.reverse    = reverse
    entry.wordCount  = count
    entry.loaded     = true
    entry.hidden     = hidden or entry.hidden or false
    self.Languages[code] = entry

    -- Custom words for this language were deferred until the dict existed.
    self:ApplyPendingCustomWords(code)

    if T.debugMode then
        print("|cFF00FF00[RC-Translator]|r Registered dictionary: " .. name .. " (" .. count .. " words)")
    end
end

-- ============================================================
-- LOAD-ON-DEMAND
-- ============================================================

--- Is this language's dictionary actually in memory?
function T:IsLanguageLoaded(code)
    local d = self.Languages[code]
    return (d and d.loaded and d.dictionary) and true or false
end

--- Shared English key table, expanded once on first use and then kept.
function T:GetKeyTable()
    if self.KeyTable then return self.KeyTable end
    local t = {}
    for k in RCT_KEYS:gmatch("([^\n]*)\n?") do
        t[#t + 1] = k
    end
    self.KeyTable = t
    return t
end

--- Expand a packed dictionary into real forward/reverse tables.
--- This is the moment a language actually costs memory. Before this it is a
--- flat string; after it, the string is released and only the tables remain.
function T:EnsureLanguageLoaded(code)
    if not code or code == "en" then return true end
    local d = self.Languages[code]
    if not d then return false end
    if d.loaded and d.dictionary then return true end

    local packed = self.PackedDicts and self.PackedDicts[code]
    if not packed then return false end

    local keys = self:GetKeyTable()
    local fwd, rev, i = {}, {}, 0
    for value in packed:gmatch("([^\n]*)\n?") do
        i = i + 1
        if value ~= "" then
            local key = keys[i]
            if key then
                fwd[key] = value
                rev[value:lower()] = key
            end
        end
    end

    self.PackedDicts[code] = nil      -- blob is now redundant; let it be collected

    self:RegisterDictionary(code, d.name, fwd, d.hidden)
    return true
end

--- Mark a language as one the user actually uses, and load it now.
function T:EnableLanguage(code)
    if not code or code == "en" then return true end
    if self.db then self.db.enabledLanguages[code] = true end
    return self:EnsureLanguageLoaded(code)
end

--- Every language whose dictionary is currently resident. Detection and
--- highlighting only ever scan these -- that is the whole point of LoD.
function T:LoadedLanguages()
    local out = {}
    for code, d in pairs(self.Languages) do
        if d.loaded and d.dictionary and code ~= "en" then
            out[#out + 1] = d
        end
    end
    return out
end

--- Load everything the user's settings actually reference.
function T:LoadEnabledLanguages()
    local want = {}

    -- Guard every insert: t[nil] = v throws "table index is nil" in Lua, and any
    -- of these settings can legitimately be unset on a fresh profile.
    local function add(code)
        if code and code ~= "en" and code ~= "auto" then want[code] = true end
    end

    for code in pairs(self.db.enabledLanguages or {}) do add(code) end
    add(self.db.targetLang)
    add(self.db.sourceLang)
    add(self.db.incomingSourceLang)
    add(self.db.incomingTargetLang)

    local n = 0
    for code in pairs(want) do
        if self:EnsureLanguageLoaded(code) then n = n + 1 end
    end
    return n
end

-- ============================================================
-- TRANSLATION ENGINE
-- ============================================================

--- Byte length of the UTF-8 character starting with byte b.
local function utf8CharLen(b)
    if b < 0x80 then return 1
    elseif b < 0xE0 then return 2
    elseif b < 0xF0 then return 3
    else return 4 end
end

--- No-space-script translator (Chinese, Japanese, Thai, ...).
--- The %w tokenizer in Translate() is blind to multibyte characters, so CJK
--- source text produces zero tokens and gets echoed back untranslated. Here we
--- instead walk the raw string and, at each position, greedily match the LONGEST
--- reverse-dictionary phrase that starts there (up to maxChars characters),
--- falling back to passing one character (or one ASCII word) through untouched.
--- srcReverse: foreign→english map (required). dstForward: english→foreign map
--- (only for foreign→foreign pivots; nil for foreign→english).
function T:TranslateCJK(text, srcReverse, dstForward)
    local out, translated, total = {}, 0, 0
    local n, i = #text, 1
    local maxChars = 12

    -- Emit a chunk, inserting a single separating space before word-like output
    -- when the previous chunk ended in a non-space (CJK has no spaces of its own,
    -- so "你好大家" would otherwise render as "helloguys").
    local function emit(chunk, wordLike)
        if wordLike and #out > 0 then
            local prev = out[#out]
            local pc = prev:sub(-1)
            if pc ~= "" and pc ~= " " and pc ~= "\n" then
                chunk = " " .. chunk
            end
        end
        out[#out+1] = chunk
    end

    while i <= n do
        local b = text:byte(i)

        -- ASCII word run: treat like a normal token (keeps mixed "需要治疗 lfg" sane)
        if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then
            local s = i
            while i <= n do
                local c = text:byte(i)
                if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
                   or c == 39 or c == 45 then
                    i = i + 1
                else break end
            end
            local word = text:sub(s, i - 1)
            total = total + 1
            local eng = srcReverse[word:lower()]
            local res = eng and (dstForward and dstForward[eng:lower()] or eng) or nil
            emit(res or word, true)
            if res then translated = translated + 1 end

        -- ASCII punctuation / whitespace: pass through verbatim, don't count
        elseif b < 0x80 then
            emit(text:sub(i, i), false)
            i = i + 1

        -- Multibyte (CJK / kana / Thai / ...): longest-phrase match at this position
        else
            local ends, j, chars = {}, i, 0
            while j <= n and chars < maxChars do
                j = j + utf8CharLen(text:byte(j))
                chars = chars + 1
                ends[#ends+1] = j - 1
            end
            total = total + 1
            local matched = false
            for k = #ends, 1, -1 do            -- longest first
                local sub = text:sub(i, ends[k])
                local eng = srcReverse[sub:lower()]
                if eng then
                    local res = dstForward and dstForward[eng:lower()] or eng
                    if res then
                        emit(res, true)
                        translated = translated + 1
                        i = ends[k] + 1
                        matched = true
                        break
                    end
                end
            end
            if not matched then
                emit(text:sub(i, ends[1]), false)   -- pass one char through
                i = ends[1] + 1
            end
        end
    end
    return table.concat(out, ""), translated, total
end

--- Replace URLs/links with placeholders so the tokenizer never translates
--- inside them (e.g. "discord.gg/abc" must survive intact). Returns masked text;
--- `store` collects the originals for RestoreLinks.
function T:MaskLinks(text, store)
    local function stash(u)
        store.n = store.n + 1
        store[store.n] = u
        return "RCTLINKZ" .. store.n .. "Z"
    end
    -- WoW hyperlinks first (|Hitem:...|h[Name]|h etc.) so loot/quest/spell links
    -- survive translation intact and stay clickable; the surrounding words still
    -- get translated around the placeholder.
    text = text:gsub("|H.-|h.-|h", stash)
    text = text:gsub("https?://%S+", stash)          -- scheme URLs
    text = text:gsub("www%.%S+", stash)              -- www.host/...
    text = text:gsub("[%w%-]+%.[%w%-][%w%-]+/%S+", stash)  -- host.tld/path (discord.gg/xyz)
    return text
end

--- Put the original URLs back after translation. Function replacement so any
--- % or other magic chars in the URL are inserted literally.
function T:RestoreLinks(text, store)
    for i = 1, (store.n or 0) do
        local url = store[i]
        text = text:gsub("RCTLINKZ" .. i .. "Z", function() return url end)
    end
    return text
end

--- Chinese and Japanese don't put spaces between words. Our word-by-word output
--- keeps the source's English spacing, which looks unnatural ("老铁 刚 升起"). This
--- removes spaces that sit between two CJK characters, so the result reads like
--- real Chinese/Japanese ("老铁刚升起"), while spaces around Latin words (kept
--- English, item links, etc.) are preserved. Korean uses spaces, so it's excluded.
-- Each no-space target maps to the UTF-8 byte pattern matching one character of
-- its script. zh/zhTW/ja share the CJK ideograph + kana range (lead bytes E3-E9).
-- Thai (U+0E00-U+0E7F) is also written without inter-word spaces, but lives in a
-- different range (E0 B8-B9 ..), so it needs its own pattern -- the CJK one never
-- matched it, which left composed Thai output with a space between every word.
local RCT_NOSPACE_CHAR = {
    zh   = "[\227-\233][\128-\191][\128-\191]",
    zhTW = "[\227-\233][\128-\191][\128-\191]",
    ja   = "[\227-\233][\128-\191][\128-\191]",
    th   = "\224[\184-\185][\128-\191]",
}
function T:CollapseCJKSpaces(text, toLang)
    local ch = RCT_NOSPACE_CHAR[toLang]
    if not ch then return text end
    local prev
    repeat
        prev = text
        text = text:gsub("(" .. ch .. ") +(" .. ch .. ")", "%1%2")
    until text == prev
    return text
end

function T:Translate(text, fromLang, toLang)
    if not text or text == "" then return text, 0, 0 end
    if fromLang == toLang then return text, 0, 0 end

    -- Protect URLs/links from being tokenized and translated.
    local __links = { n = 0 }
    text = self:MaskLinks(text, __links)
    
    -- Determine lookup strategy:
    --   en → foreign:      use toLang dictionary (forward)
    --   foreign → en:      use fromLang reverse dictionary
    --   foreign → foreign: pivot through English (reverse fromLang, then forward toLang)
    
    local srcReverse = nil   -- foreign→english step
    local dstForward = nil   -- english→foreign step
    
    -- Pull the dictionaries in off disk if they are not resident yet.
    if fromLang ~= "en" and not self:EnsureLanguageLoaded(fromLang) then return text, 0, 0 end
    if toLang   ~= "en" and not self:EnsureLanguageLoaded(toLang)   then return text, 0, 0 end

    if fromLang == "en" then
        -- English → target: just need forward dict
        local langData = self.Languages[toLang]
        if not langData or not langData.dictionary then return text, 0, 0 end
        dstForward = langData.dictionary
    elseif toLang == "en" then
        -- Source → English: just need reverse dict
        local langData = self.Languages[fromLang]
        if not langData or not langData.reverse then return text, 0, 0 end
        srcReverse = langData.reverse
    else
        -- Foreign → Foreign: need both
        local srcData = self.Languages[fromLang]
        local dstData = self.Languages[toLang]
        if not srcData or not srcData.reverse then return text, 0, 0 end
        if not dstData or not dstData.dictionary then return text, 0, 0 end
        srcReverse = srcData.reverse
        dstForward = dstData.dictionary
    end
    
    -- No-space scripts (CJK / Japanese kana / Thai) can't be word-tokenized by
    -- the %w loop below, so route them through the longest-match scanner. Only
    -- fires when a source reverse map exists (foreign→en / foreign→foreign);
    -- en→foreign source text is ASCII and uses the normal path.
    if srcReverse and (text:find("[\227-\233][\128-\191][\128-\191]")
                       or text:find("\224[\184-\185][\128-\191]")) then
        local __cjk, __w, __t = self:TranslateCJK(text, srcReverse, dstForward)
        return self:CollapseCJKSpaces(self:RestoreLinks(__cjk, __links), toLang), __w, __t
    end

    local translated = {}
    local wordsTranslated = 0
    local totalWords = 0

    -- Build a token list: {word, trailing} pairs preserving original spacing
    local tokens = {}
    for word, trailing in text:gmatch("([%w'%-]+)([^%w'%-]*)") do
        totalWords = totalWords + 1
        table.insert(tokens, { word = word, trailing = trailing })
    end

    -- Helper: lookup a phrase (space-joined) through the active dicts
    local function lookupPhrase(phrase)
        local lower = phrase:lower()
        if srcReverse and dstForward then
            local english = srcReverse[lower]
            if english then return dstForward[english:lower()] end
        elseif srcReverse then
            return srcReverse[lower]
        elseif dstForward then
            return dstForward[lower]
        end
        return nil
    end

    -- Phrase-aware pass: try longest match (up to 6 words) before falling back to 1 word
    local i = 1
    while i <= #tokens do
        local tok = tokens[i]
        local lower = tok.word:lower()

        if self:IsIgnoredWord(lower) then
            table.insert(translated, tok.word .. tok.trailing)
            i = i + 1
        else
            -- Try phrases of decreasing length (max 6 words)
            local matched = false
            local maxLen = math.min(6, #tokens - i + 1)
            for phraseLen = maxLen, 2, -1 do
                -- Build phrase from tokens i..i+phraseLen-1
                local parts = {}
                for j = i, i + phraseLen - 1 do
                    table.insert(parts, tokens[j].word)
                end
                local phrase = table.concat(parts, " ")
                local result = lookupPhrase(phrase)
                if result then
                    -- Use case of first word for the whole phrase
                    result = T:MatchCase(tok.word, result)
                    -- Trailing punctuation comes from the last token in the phrase
                    local lastTrailing = tokens[i + phraseLen - 1].trailing
                    table.insert(translated, result .. lastTrailing)
                    wordsTranslated = wordsTranslated + phraseLen
                    i = i + phraseLen
                    matched = true
                    break
                end
            end
            if not matched then
                -- Single word fallback
                local result = lookupPhrase(tok.word)
                if result then
                    result = T:MatchCase(tok.word, result)
                    wordsTranslated = wordsTranslated + 1
                    table.insert(translated, result .. tok.trailing)
                else
                    table.insert(translated, tok.word .. tok.trailing)
                end
                i = i + 1
            end
        end
    end

    local leading = text:match("^([^%w'%-]*)")
    return self:CollapseCJKSpaces(self:RestoreLinks((leading or "") .. table.concat(translated, ""), __links), toLang), wordsTranslated, totalWords
end

function T:MatchCase(source, result)
    -- Case only means something for ASCII/Latin. If the result contains ANY
    -- non-ASCII byte (CJK, Cyrillic, Greek, Arabic, Thai, ...), return it
    -- untouched: upper()/lower()/sub() would operate on individual UTF-8 bytes
    -- and split/mangle a multibyte character, turning it into boxes (□□).
    if result:find("[\128-\255]") then
        return result
    end
    if source == source:upper() then
        return result:upper()
    elseif source:sub(1,1) == source:sub(1,1):upper() then
        return result:sub(1,1):upper() .. result:sub(2)
    else
        return result:lower()
    end
end

-- ============================================================
-- LANGUAGE AUTO-DETECTION ENGINE
-- ============================================================

-- Order matters: the more specific patterns must be tested before the broad ones.
-- These are pure UTF-8 byte-range tests, so they cost nothing and -- critically --
-- need NO dictionary in memory. This is what lets [T] identify a language before
-- deciding which dictionary to pull off disk.
T.ScriptPatterns = {
    { lang = "ja", pattern = "\227\129[\128-\191]", name = "Hiragana", minChars = 1 },
    { lang = "ja", pattern = "\227\130[\128-\191]", name = "Katakana", minChars = 1 },
    { lang = "ko", pattern = "[\234-\237][\128-\191][\128-\191]", name = "Hangul", minChars = 1 },
    { lang = nil,  pattern = "[\208-\209][\128-\191]", name = "Cyrillic", minChars = 2 },
    { lang = "el", pattern = "[\206-\207][\128-\191]", name = "Greek", minChars = 2 },
    { lang = "he", pattern = "\215[\144-\170]", name = "Hebrew", minChars = 2 },
    { lang = "ar", pattern = "[\216-\219][\128-\191]", name = "Arabic", minChars = 2 },
    { lang = "th", pattern = "\224[\184-\185][\128-\191]", name = "Thai", minChars = 2 },
    { lang = "hi", pattern = "\224[\164-\165][\128-\191]", name = "Devanagari", minChars = 2 },
    { lang = nil,  pattern = "[\228-\233][\128-\191][\128-\191]", name = "CJK", minChars = 2 },
}

--- Cyrillic covers ru / uk / bg. Only a few letters are genuinely exclusive;
--- everything else has to be decided on marker words. Note that 'щ' is NOT a
--- Bulgarian tell -- Russian "помощь" has one -- so it must not be used here.
function T:DistinguishCyrillic(text)
    local lower = text:lower()

    -- Ukrainian-exclusive letters: і ї є ґ
    if lower:find("\209[\150\151\148]") or lower:find("\210\145") then return "uk", 0.93 end
    -- Russian-exclusive letters: ы э ё  (Bulgarian and Ukrainian have none of these)
    if lower:find("\209[\139\141]") or lower:find("\209\145") then return "ru", 0.92 end

    -- No exclusive letter. Fall back to marker words among the Cyrillic three.
    local padded = " " .. lower .. " "
    local best, bestHits = nil, 0
    for _, code in ipairs({ "ru", "uk", "bg" }) do
        local hits = 0
        for _, marker in ipairs(self.MarkerWords[code] or {}) do
            if padded:find("[%s%p]" .. marker .. "[%s%p]") then hits = hits + 1 end
        end
        if hits > bestHits then best, bestHits = code, hits end
    end
    if best and bestHits >= 1 then
        return best, math.min(0.60 + bestHits * 0.10, 0.92)
    end

    return "ru", 0.65   -- most common Cyrillic language on WoW realms
end

T.MarkerWords = {
    ["en"] = { "the", "and", "that", "have", "for", "not", "with", "you", "this", "but", "from", "they", "been", "said", "each", "which", "their", "will", "other", "about", "many", "then", "them", "these", "some", "would", "like", "into", "just", "your", "over", "think", "also", "hello", "goodbye", "thanks", "please", "sorry" },
    ["es"] = { "hola", "necesito", "tengo", "puedo", "quiero", "también", "dónde", "cómo", "grupo", "mazmorra", "busco", "alguien", "hermandad", "por", "pero", "está", "tiene", "somos", "vamos", "bueno", "gracias", "adiós", "buenos", "buenas", "noches", "días", "tardes" },
    ["pt"] = { "você", "não", "obrigado", "preciso", "também", "então", "muito", "para", "como", "onde", "ainda", "depois", "agora", "pronto", "tudo", "ninguém", "alguém", "olá", "oi", "tchau", "bom", "boa" },
    ["fr"] = { "bonjour", "merci", "oui", "je", "nous", "vous", "avec", "dans", "pour", "mais", "très", "bien", "quoi", "comment", "quête", "donjon", "guilde", "cherche", "salut", "bonsoir", "bonne", "nuit", "matin", "soir" },
    ["de"] = { "ich", "und", "nicht", "bitte", "danke", "nein", "jetzt", "schon", "noch", "sehr", "auch", "nur", "immer", "wieder", "zusammen", "gilde", "hilfe", "brauche", "hallo", "tschüss", "guten", "morgen", "abend", "nacht" },
    ["it"] = { "ciao", "grazie", "sono", "anche", "molto", "adesso", "ancora", "sempre", "insieme", "forse", "davvero", "quasi", "senza", "prima", "dopo", "perché", "buongiorno", "buonasera", "buonanotte", "arrivederci", "prego" },
    ["tl"] = { "ako", "ikaw", "siya", "tayo", "sila", "ang", "mga", "saan", "bakit", "paano", "hindi", "oo", "sige", "salamat", "kumusta", "meron", "kailangan", "gusto", "lang", "talaga", "tara", "astig" },
    ["pl"] = { "cześć", "dzień", "dobry", "dobranoc", "dziękuję", "proszę", "przepraszam", "tak", "nie", "hej", "siema", "witaj", "żegnaj" },
    ["nl"] = { "hallo", "dag", "goedemorgen", "goedenavond", "goedenacht", "dank", "alsjeblieft", "sorry", "ja", "nee", "doei" },
    ["sv"] = { "hej", "hallå", "god", "morgon", "kväll", "natt", "tack", "förlåt", "ja", "nej", "adjö", "hejdå" },
    ["no"] = { "hei", "hallo", "god", "morgen", "kveld", "natt", "takk", "unnskyld", "ja", "nei", "ha", "det" },
    ["da"] = { "hej", "godmorgen", "godaften", "godnat", "tak", "undskyld", "ja", "nej", "farvel", "hejsa" },
    ["tr"] = { "merhaba", "günaydın", "iyi", "akşamlar", "geceler", "teşekkürler", "lütfen", "özür", "evet", "hayır", "hoşça", "kal" },
    ["cs"] = { "ahoj", "dobrý", "ráno", "večer", "noc", "děkuji", "prosím", "promiňte", "ano", "ne", "nashle" },
    ["ro"] = { "bună", "salut", "dimineața", "seara", "noapte", "mulțumesc", "vă", "rog", "scuzați", "da", "nu", "la", "revedere" },
    ["hu"] = { "szia", "jó", "reggelt", "estét", "éjszakát", "köszönöm", "kérem", "bocsánat", "igen", "nem", "viszlát" },
    ["fi"] = { "hei", "huomenta", "iltaa", "yötä", "kiitos", "ole", "hyvä", "anteeksi", "kyllä", "ei", "heippa", "moi" },
    ["hr"] = { "bok", "zdravo", "dobro", "jutro", "večer", "laku", "noć", "hvala", "molim", "oprosti", "da", "ne", "doviđenja", "trebam", "gdje" },
    ["id"] = { "halo", "selamat", "pagi", "siang", "malam", "terima", "kasih", "tolong", "maaf", "ya", "tidak", "sampai", "jumpa", "saya", "kamu", "butuh" },
    ["ms"] = { "helo", "selamat", "pagi", "petang", "malam", "terima", "kasih", "tolong", "maaf", "ya", "tidak", "jumpa", "lagi", "saya", "awak", "nak" },
    ["vi"] = { "xin", "chào", "cảm", "ơn", "làm", "ơn", "xin lỗi", "vâng", "không", "tạm", "biệt", "tôi", "bạn", "cần", "được" },
    ["sk"] = { "ahoj", "dobrý", "deň", "ďakujem", "prosím", "prepáč", "áno", "nie", "dovidenia" },
    ["ru"] = { "привет", "здравствуйте", "спасибо", "пожалуйста", "извини", "нужна", "нужно", "помощь", "где", "что", "как", "хочу", "могу", "давай", "сейчас", "подземелье", "гильдия", "ищу", "группу", "рейд" },
    ["uk"] = { "привіт", "дякую", "будь", "ласка", "вибач", "потрібна", "потрібно", "допомога", "де", "що", "як", "хочу", "можу", "давай", "зараз", "підземелля", "гільдія", "шукаю", "групу", "рейд" },
    ["bg"] = { "здравей", "здрасти", "благодаря", "моля", "извинявай", "трябва", "помощ", "къде", "какво", "как", "искам", "мога", "хайде", "сега", "подземие", "гилдия", "търся", "група", "приятел", "добре" },
    ["ca"] = { "hola", "bon", "bona", "dia", "nit", "gràcies", "adéu", "sisplau", "perdó", "també", "vull", "necessito", "company", "amb", "què", "aquest", "fins", "molt", "ara", "sí" },
    ["sl"] = { "zdravo", "živjo", "živijo", "pozdravljeni", "dober", "hvala", "prosim", "oprosti", "nasvidenje", "potrebujem", "kje", "kaj", "kako", "tudi", "lahko", "sem", "ja", "ne" },
}

-- Latin-script languages that share marker words are separated by the letters
-- only they use. Cheap, dictionary-free, and a strong tiebreak.
T.DiacriticSignatures = {
    { lang = "es", pattern = "\195\177" },                        -- ñ
    { lang = "de", pattern = "\195\159" },                        -- ß
    { lang = "pl", pattern = "[\197\196][\130\132\188\186\189\153\135]" }, -- ł ą ż ź ż ę ć
    { lang = "tr", pattern = "\196[\177\159]" },                 -- ı ğ
    { lang = "ro", pattern = "\200[\153\155]" },                 -- ș ț
    { lang = "hu", pattern = "\197[\145\177]" },                 -- ő ű
    { lang = "cs", pattern = "\197[\153\190]" },                 -- ř ž
    { lang = "pt", pattern = "\195[\163\181]" },                 -- ã õ
    { lang = "da", pattern = "\195[\166\184]" },                 -- æ ø
    { lang = "sv", pattern = "\195\165" },                        -- å
    { lang = "ca", pattern = "l\194\183l" },                      -- l·l geminate (uniquely Catalan)
    { lang = "hr", pattern = "\196\145" },                        -- đ
    { lang = "sk", pattern = "\196\190" },                        -- ľ
    { lang = "sr", pattern = "\209[\146\153\154\155\159]" },      -- ђ љ њ ћ џ (Serbian Cyrillic)
}

--- Best-effort language guess using only script + markers + diacritics.
--- Never touches a dictionary, so it is safe to call before anything is loaded.
function T:DiacriticGuess(text)
    for _, sig in ipairs(self.DiacriticSignatures) do
        if text:find(sig.pattern) then return sig.lang, 0.60, "diacritic" end
    end
    return nil, 0, nil
end

function T:DetectScript(text)
    if not text or text == "" then return nil, nil end
    for _, script in ipairs(self.ScriptPatterns) do
        local count = 0
        for _ in text:gmatch(script.pattern) do
            count = count + 1
        end
        if count >= script.minChars then
            return script.name, script.lang
        end
    end
    return "Latin", nil
end

function T:DistinguishCJK(text)
    local hasHiragana = text:find("\227\129[\128-\191]") ~= nil
    local hasKatakana = text:find("\227\130[\128-\191]") ~= nil
    local hasCJK = text:find("[\228-\233][\128-\191][\128-\191]") ~= nil
    if hasHiragana or hasKatakana then
        return "ja"
    elseif hasCJK then
        return "zh"
    end
    return nil
end

--- THE [T] PATH.
--- Work out what language a message is in WITHOUT needing any dictionary
--- resident, then pull exactly that one dictionary off disk and remember the
--- choice so every later message in that language translates with no click.
--- Returns: langCode, confidence, method, didLoad
function T:ResolveAndLoad(text)
    if not text or text == "" then return nil, 0, nil, false end

    -- 1. Dictionary-free passes: script -> markers -> diacritics.
    local code, conf, method = self:DetectLanguage(text)

    -- 2. Nothing yet? Diacritics are the last dictionary-free resort.
    if not code or conf <= 0.15 then
        code, conf, method = self:DiacriticGuess(text)
    end

    if not code or code == "en" then return code, conf or 0, method, false end

    -- 3. Pull that one dictionary in, if it is not already resident.
    local wasLoaded = self:IsLanguageLoaded(code)
    if not wasLoaded then
        if not self:EnableLanguage(code) then
            return code, conf, method, false
        end
        local d = self.Languages[code]
        print(string.format(
            "|cFF00FF00[RC-Translator]|r Loaded |cFFFFFF00%s|r (%d words). "
            .. "Messages in this language will now translate automatically.",
            d.name or code, d.wordCount or 0))
    else
        -- Already in memory, but make sure it survives the next reload.
        if self.db then self.db.enabledLanguages[code] = true end
    end

    -- 4. Re-detect now that a real dictionary is available. A dictionary scan
    --    beats a marker/diacritic guess, and may correct it.
    if method ~= "script" then
        local code2, conf2, method2 = self:DetectLanguage(text)
        if code2 and conf2 and conf2 > (conf or 0) then
            code, conf, method = code2, conf2, method2
            if code ~= "en" then self:EnableLanguage(code) end
        end
    end

    return code, conf, method, (not wasLoaded)
end

function T:DetectLanguage(text)
    if not text or text == "" then return nil, 0, nil end
    
    local scriptName, scriptLang = self:DetectScript(text)
    
    if scriptName == "Cyrillic" then
        local cyr, conf = self:DistinguishCyrillic(text)
        return cyr, conf, "script"
    elseif scriptName == "Hangul" then return "ko", 0.95, "script"
    elseif scriptName == "Hiragana" or scriptName == "Katakana" then return "ja", 0.95, "script"
    elseif scriptName == "CJK" then
        local cjkLang = self:DistinguishCJK(text)
        if cjkLang then return cjkLang, 0.90, "script" end
    elseif scriptLang then
        -- Greek, Hebrew, Arabic, Thai, Devanagari: script IS the language.
        return scriptLang, 0.95, "script"
    end
    
    local lowerText = " " .. text:lower() .. " "
    local markerScores = {}
    for code, markers in pairs(self.MarkerWords) do
        local hits = 0
        for _, marker in ipairs(markers) do
            if not self:IsIgnoredWord(marker) then
                if lowerText:find("[%s%p]" .. marker .. "[%s%p]") then
                    hits = hits + 1
                end
            end
        end
        if hits > 0 then markerScores[code] = hits end
    end

    -- Score on RAW HITS, not hits/#markers. The old ratio meant a language was
    -- penalised for having a longer marker list -- adding markers to a language
    -- made it HARDER to detect, which is backwards.
    local wordCount = 0
    for _ in lowerText:gmatch("[^%s%p]+") do wordCount = wordCount + 1 end

    local bestMarkerLang, bestMarkerHits = nil, 0
    for code, hits in pairs(markerScores) do
        if hits > bestMarkerHits then
            bestMarkerHits = hits
            bestMarkerLang = code
        end
    end

    -- Confidence rises with hits and with the share of the message they cover.
    local coverage = (wordCount > 0) and (bestMarkerHits / wordCount) or 0
    local bestMarkerScore = math.min(0.45 + (bestMarkerHits * 0.12) + (coverage * 0.3), 0.95)

    -- Two markers is convincing. One is only convincing in a very short message.
    if bestMarkerHits >= 2 or (bestMarkerHits == 1 and wordCount <= 3) then
        return bestMarkerLang, bestMarkerScore, "marker"
    end
    
    local words = {}
    for word in text:gmatch("[%w'%-]+") do
        local lower = word:lower()
        if not self:IsIgnoredWord(lower) then
            table.insert(words, lower)
        end
    end
    if #words == 0 then return nil, 0, nil end
    
    -- Only resident dictionaries participate in detection.
    local loaded = self:LoadedLanguages()

    local englishHits = 0
    for _, word in ipairs(words) do
        for _, langData in ipairs(loaded) do
            if langData.dictionary[word] then
                englishHits = englishHits + 1
                break
            end
        end
    end
    local englishScore = englishHits / #words
    
    local bestLang, bestScore = nil, 0
    for _, langData in ipairs(loaded) do
        local code = langData.code
        -- Skip hidden/novelty dicts (Orcish, Common) from auto-detection
        if not langData.hidden then
            local matches = 0
            if langData.reverse then
                for _, word in ipairs(words) do
                    if langData.reverse[word] then matches = matches + 1 end
                end
            end
            local score = matches / #words
            if score > bestScore then
                bestScore = score
                bestLang = code
            end
        end
    end
    
    -- Only declare a foreign language if it scores significantly better than
    -- what we'd expect from coincidental English words appearing as translations.
    -- Require foreign score to be well above a simple 50% tie with English.
    if bestScore > 0.2 and bestScore >= englishScore * 0.7 then
        return bestLang, bestScore, "dictionary"
    end
    -- If target language is not English, allow English to be detected as a source
    -- so it can be translated to the user's preferred language.
    -- Also prefer English when englishScore is high and foreign score isn't convincing.
    if self.db and self.db.targetLang and self.db.targetLang ~= "en" then
        if englishScore > 0.3 then
            return "en", englishScore, "dictionary"
        end
    end
    if bestMarkerLang and bestMarkerHits > 0 then
        -- Don't flag English as foreign if target IS English
        if bestMarkerLang == "en" and (not self.db or not self.db.targetLang or self.db.targetLang == "en") then
            return nil, 0, nil
        end
        return bestMarkerLang, bestMarkerScore, "marker"
    end
    return nil, 0, nil
end

-- ============================================================
-- FOREIGN WORD DETECTION (per-word, for chat highlighting)
-- ============================================================

--- Check if a single word is likely foreign.
-- Returns the language code if foreign, nil if English or unknown.
function T:IsWordForeign(word)
    if not word or word == "" then return nil end
    local lower = word:lower()
    if self:IsIgnoredWord(lower) then return nil end
    -- Allow known short foreign words; skip truly ambiguous 1-char tokens
    local knownShortForeign = { ["ja"]=true, ["da"]=true, ["si"]=true, ["sí"]=true,
        ["oui"]=true, ["hai"]=true, ["nee"]=true, ["ne"]=true, ["jo"]=true,
        ["hei"]=true, ["hej"]=true, ["yo"]=true, ["oi"]=true, ["ay"]=true,
        ["hi"]=true }
    if #lower <= 2 and not knownShortForeign[lower] then return nil end  -- Too short, too many false positives

    local loaded = self:LoadedLanguages()

    -- Check if it's a known English word (exists as a key in any forward dictionary)
    local isEnglish = false
    for _, langData in ipairs(loaded) do
        if langData.dictionary[lower] then
            isEnglish = true
            break
        end
    end

    -- Check if it exists in any foreign reverse dictionary
    local foreignLang = nil
    for _, langData in ipairs(loaded) do
        if langData.reverse and langData.reverse[lower] then
            foreignLang = langData.code
            break
        end
    end

    -- Foreign = in a reverse dict but NOT a known English word
    if foreignLang and not isEnglish then
        return foreignLang
    end
    return nil
end

--- Highlight foreign words by wrapping them in colored hyperlinks.
-- Hyperlinks in WoW appear underlined on hover — this is the "underline" effect.
function T:HighlightForeignWords(text, msgId)
    if not text or text == "" then return text end

    local parts = {}
    for word, trailing in text:gmatch("([%w'%-]+)([^%w'%-]*)") do
        local foreignLang = self:IsWordForeign(word)
        if foreignLang then
            -- Gold-colored hyperlink: visually distinct + underlined on hover
            local link = string.format("|cFFFFCC00|Hrctword:%d:%s:%s|h%s|h|r",
                msgId, foreignLang, word:lower(), word)
            table.insert(parts, link .. trailing)
        else
            table.insert(parts, word .. trailing)
        end
    end

    local leading = text:match("^([^%w'%-]*)")
    return (leading or "") .. table.concat(parts, "")
end

-- ============================================================
-- CHAT EVENT HANDLING
-- ============================================================

local chatFrame = CreateFrame("Frame")
T.chatFrame = chatFrame

-- Chat events populated at runtime based on WoW version (see Compat.lua)
local CHAT_EVENTS = RCT_Compat.GetValidChatEvents()

local eventToChannel = {
    CHAT_MSG_SAY = "SAY",
    CHAT_MSG_YELL = "YELL",
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY_LEADER",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID_LEADER",
    CHAT_MSG_GUILD = "GUILD",
    CHAT_MSG_OFFICER = "OFFICER",
    CHAT_MSG_WHISPER = "WHISPER",
    CHAT_MSG_CHANNEL = "CHANNEL",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT_LEADER",
    CHAT_MSG_EMOTE = "EMOTE",
    CHAT_MSG_TEXT_EMOTE = "EMOTE",
}

-- Non-chat categories that can be routed into the Translated tab AND translated
-- (loot, skill-ups, NPC dialogue, etc.). Each maps to a tabMessageGroups toggle
-- key + the [tag] shown in the tab.
local eventToMsgGroup = {
    CHAT_MSG_LOOT                 = { key = "LOOT",        label = "Loot" },
    CHAT_MSG_CURRENCY             = { key = "CURRENCY",    label = "Currency" },
    CHAT_MSG_MONEY                = { key = "MONEY",       label = "Money" },
    CHAT_MSG_SKILL                = { key = "SKILL",       label = "Skill" },
    CHAT_MSG_SYSTEM               = { key = "SYSTEM",      label = "System" },
    CHAT_MSG_COMBAT_XP_GAIN       = { key = "XP",          label = "XP" },
    CHAT_MSG_COMBAT_FACTION_CHANGE= { key = "REP",         label = "Rep" },
    CHAT_MSG_COMBAT_HONOR_GAIN    = { key = "HONOR",       label = "Honor" },
    CHAT_MSG_ACHIEVEMENT          = { key = "ACHIEVEMENT", label = "Achievement" },
    CHAT_MSG_GUILD_ACHIEVEMENT    = { key = "ACHIEVEMENT", label = "Achievement" },
    CHAT_MSG_MONSTER_SAY          = { key = "NPC",         label = "NPC" },
    CHAT_MSG_MONSTER_YELL         = { key = "NPC",         label = "NPC" },
    CHAT_MSG_MONSTER_EMOTE        = { key = "NPC",         label = "NPC" },
    CHAT_MSG_MONSTER_WHISPER      = { key = "NPC",         label = "NPC" },
    CHAT_MSG_MONSTER_BOSS_EMOTE   = { key = "NPC",         label = "NPC" },
    CHAT_MSG_MONSTER_BOSS_WHISPER = { key = "NPC",         label = "NPC" },
    CHAT_MSG_BG_SYSTEM_ALLIANCE   = { key = "BG",          label = "BG" },
    CHAT_MSG_BG_SYSTEM_HORDE      = { key = "BG",          label = "BG" },
    CHAT_MSG_BG_SYSTEM_NEUTRAL    = { key = "BG",          label = "BG" },
    CHAT_MSG_PET_INFO             = { key = "PET",         label = "Pet" },
}

T.recentMessages = {}
T.maxRecentMessages = 100

-- Global message counter
local msgCounter = 0

function T:StoreMessage(id, text, sender, channel, timestamp)
    table.insert(self.recentMessages, 1, {
        id = id,
        text = text,
        sender = sender,
        channel = channel,
        timestamp = timestamp or time(),
    })
    while #self.recentMessages > self.maxRecentMessages do
        table.remove(self.recentMessages)
    end
end

function T:TranslateMessage(msgData)
    if not msgData then return end
    
    local detectedLang, confidence, method = self:ResolveSourceLang(msgData.text)
    
    -- Only translate if a language is detected/set
    if not detectedLang or confidence <= 0.15 then
        return  -- silently skip, no spam
    end
    
    -- Translate to the user's chosen target language
    local fromLang = detectedLang
    local toLang = self.db.targetLang or "en"
    
    -- Don't translate if detected language matches target
    if fromLang == toLang then return end
    
    local result, wordsTranslated, totalWords = self:Translate(msgData.text, fromLang, toLang)
    
    if wordsTranslated > 0 then
        local fromName = self.Languages[fromLang] and self.Languages[fromLang].name or fromLang
        local r, g, b = unpack(self.db.translationColor)
        local colorHex = string.format("|cFF%02x%02x%02x", r * 255, g * 255, b * 255)
        
        local confPct = math.floor((confidence or 0) * 100)
        local methodStr = method and (" via " .. method) or ""
        local detectInfo = ""
        if self.db.showDetectionInfo then
            detectInfo = string.format(" |cFF888888[detected: %s %d%%%s]|r", fromName, confPct, methodStr)
        end
        
        local toName = toLang == "en" and "English" or (self.Languages[toLang] and self.Languages[toLang].name or toLang)
        local header = string.format("|cFFFFAA00[RC-T %s→%s]|r ", fromName, toName)
        local translatedText = string.format("%s%s|r", colorHex, result)
        local stats = string.format(" |cFF888888(%d/%d words)|r", wordsTranslated, totalWords)
        
        local originalLine = ""
        if self.db.showOriginal and msgData.sender then
            originalLine = string.format("|cFF666666[%s]: %s|r\n", msgData.sender, msgData.text)
        end
        
        DEFAULT_CHAT_FRAME:AddMessage(originalLine .. header .. translatedText .. stats .. detectInfo)
    end
end

-- Chat event handler (auto-translate only — message storage is done in ChatFilter)
chatFrame:SetScript("OnEvent", function(self, event, text, sender, ...)
    if not T.db or not T.db.enabled then return end
    if RCT_Compat.IsSecret(text) or RCT_Compat.IsSecret(sender) then return end -- hidden by the game

    -- Non-chat categories (loot, skill-ups, NPC dialogue, system, ...) routed into
    -- the Translated tab AND translated, when their toggle is on.
    local mg = eventToMsgGroup[event]
    if mg then
        if not T.db.translatedTab then return end
        if not T:IsTabMessageGroupEnabled(mg.key) then return end
        if not text or text == "" then return end
        T:FeedTranslatedTab(text, nil, "MSGGROUP:" .. mg.label, nil)
        return
    end

    local channelKey = eventToChannel[event]
    if not channelKey then return end

    local playerName = RCT_Compat.GetPlayerName()
    local isSelf = (sender and playerName and sender:find(playerName, 1, true)) and true or false
    local isEmote = (channelKey == "EMOTE")

    -- Dedicated translated tab: has its OWN channel picker (independent of the
    -- global channel settings that gate the inline/[T] path below). For numbered
    -- channels, classify into General/Trade/LFG/World/Other so each toggles alone.
    -- The tab mirrors chat, so it also shows your OWN emotes (which aren't echoed
    -- anywhere else); your own other lines stay out to avoid double echoes.
    if T.db.translatedTab and (not isSelf or isEmote) then
        local tabKey = channelKey
        if event == "CHAT_MSG_CHANNEL" then
            -- arg4 = channelName, arg9 = channelBaseName; check both so localized
            -- or numbered channels still classify correctly.
            local _, chanName, _t, _f, _z, _idx, chanBase = ...
            tabKey = T:ClassifyChannel(((chanName or "") .. " " .. (chanBase or "")))
        end
        if T:IsTabChannelEnabled(tabKey) then
            local guid = select(10, ...)   -- arg12 of CHAT_MSG_* is the sender GUID
            T:FeedTranslatedTab(text, sender, tabKey, guid)
        end
    end

    -- Inline / IM auto-translate path never handles your own outgoing chat.
    if isSelf then return end

    -- Everything below (inline / IM auto-translate) uses the global channel list.
    if not T.db.channels[channelKey] then return end

    -- For numbered channels, also honor the per-channel picker (General/Trade/LFG/
    -- World/Other) so a disabled channel like LFG stays quiet in inline mode too.
    if event == "CHAT_MSG_CHANNEL" then
        local _, cn, _t, _f, _z, _idx, cb = ...
        if not T:IsTabChannelEnabled(T:ClassifyChannel(((cn or "") .. " " .. (cb or "")))) then
            return
        end
    end

    if not T.db.autoTranslate then return end

    -- If the Translated tab is on, it IS the destination for auto-translations —
    -- don't also dump them inline into the main chat window.
    if T.db.translatedTab then return end

    -- Find the stored message for this text (ChatFilter already stored it)
    local msgData = nil
    for _, m in ipairs(T.recentMessages) do
        if m.text == text and m.sender == sender then
            msgData = m
            break
        end
    end
    if not msgData then return end
    
    local detectedLang, confidence, method = T:DetectLanguage(text)
    if detectedLang and confidence >= 0.20 then
        if T.db.autoTranslateToIM and T.TranslateToIM then
            T:TranslateToIM(msgData)
        else
            T:TranslateMessage(msgData)
        end
    end
end)

-- ============================================================
-- CHAT HOOKS ([T] button + foreign word highlighting)
-- ============================================================

function T:SetupChatHooks()
    -- Message filters: add [T] button + foreign word highlights
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", T.ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", T.ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", T.ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", T.ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", T.ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", T.ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", T.ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", T.ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", T.ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_EMOTE", T.ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", T.ChatFilter)
    if RCT_Compat.hasInstanceChat then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT", T.ChatFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT_LEADER", T.ChatFilter)
    end

    -- Hook OnHyperlinkClick on every chat frame so our [T] and word links work.
    -- Frames created or reset AFTER login (e.g. deleting/recreating the Guild tab,
    -- opening a whisper tab) lose their scripts, which is why clicking [T] there did
    -- nothing. So we hook idempotently, re-capture whatever handler is currently on
    -- the frame, and re-apply whenever the chat windows change.
    T:HookAllChatFrames()

    local rehook = CreateFrame("Frame")
    rehook:RegisterEvent("UPDATE_CHAT_WINDOWS")
    rehook:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
    rehook:SetScript("OnEvent", function() T:HookAllChatFrames() end)
    if type(FCF_OpenTemporaryWindow) == "function" then
        hooksecurefunc("FCF_OpenTemporaryWindow", function() T:HookAllChatFrames() end)
    end
    if type(FCF_OpenNewWindow) == "function" then
        hooksecurefunc("FCF_OpenNewWindow", function() T:HookAllChatFrames() end)
    end
end

--- Our OnHyperlinkClick handler: try our links first, else fall through to the
--- frame's previous handler (captured per-frame in rctOrigOnHyperlinkClick).
function T:HyperlinkClickHandler(frame, link, text, button)
    if T:HandleHyperlinkClick(frame, link, text, button) then return end
    local orig = frame.rctOrigOnHyperlinkClick
    if orig then orig(frame, link, text, button) end
end

--- Install our handler on one chat frame (idempotent + self-healing). If the
--- current script isn't ours (fresh frame, or Blizzard reset it), capture it as
--- the fall-through and install ours.
function T:HookChatFrame(cf)
    if not cf or not cf.GetScript then return end
    local handler = T.__hyperlinkHandler
    if not handler then
        handler = function(frame, link, text, button)
            T:HyperlinkClickHandler(frame, link, text, button)
        end
        T.__hyperlinkHandler = handler
    end
    if cf:GetScript("OnHyperlinkClick") == handler then return end  -- already ours
    cf.rctOrigOnHyperlinkClick = cf:GetScript("OnHyperlinkClick")   -- may be nil
    cf:SetScript("OnHyperlinkClick", handler)
end

--- (Re)hook every chat window, including any created/reset since last time.
function T:HookAllChatFrames()
    local n = NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        self:HookChatFrame(_G["ChatFrame" .. i])
    end
end

-- ============================================================
-- TRANSLATED CHAT TAB
-- ============================================================
-- A dedicated chat tab that shows every incoming message translated into the
-- target language (e.g. Chinese -> English), leaving normal chat untouched.

local TRANSLATED_TAB_NAME = "Translated"

-- Channels the user can route into the Translated tab, and the label for each.
-- The numbered CHANNEL event is split into named sub-channels so General and
-- LookingForGroup (etc.) can be toggled independently.
T.TAB_CHANNEL_LIST = {
    { key = "CHANNEL_GENERAL", label = "General" },
    { key = "CHANNEL_TRADE",   label = "Trade" },
    { key = "CHANNEL_LFG",     label = "LookingForGroup" },
    { key = "CHANNEL_WORLD",   label = "World" },
    { key = "CHANNEL_OTHER",   label = "Other channels" },
    { key = "SAY",             label = "Say" },
    { key = "YELL",            label = "Yell" },
    { key = "GUILD",           label = "Guild" },
    { key = "OFFICER",         label = "Officer" },
    { key = "PARTY",           label = "Party" },
    { key = "RAID",            label = "Raid" },
    { key = "INSTANCE_CHAT",   label = "Instance" },
    { key = "WHISPER",         label = "Whisper" },
    { key = "EMOTE",           label = "Emotes" },
    { key = "GMOTD",           label = "Guild MOTD" },
}
-- Leader/variant channels fold onto their base for the tab filter.
local TAB_CHANNEL_BASE = {
    PARTY_LEADER = "PARTY", RAID_LEADER = "RAID",
    INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
}
-- Per-channel default used when a channel has no saved value yet. Trade and LFG
-- default OFF (spammy) so they stay quiet even on installs whose SavedVariables
-- predate that default — never fall back to a blanket "on" for these.
local TAB_CHANNEL_DEFAULT = {
    CHANNEL_TRADE = false, CHANNEL_LFG = false,
}
-- Friendly label for the [tag] shown in the tab.
local TAB_CHANNEL_LABEL = {
    CHANNEL_GENERAL = "General", CHANNEL_TRADE = "Trade",
    CHANNEL_LFG = "LFG", CHANNEL_WORLD = "World", CHANNEL_OTHER = "Channel",
    EMOTE = "Emote", GMOTD = "GMOTD",
}

--- Classify a numbered-channel message (General/Trade/LFG/World/Other) by its
--- channel name. Matches English and Simplified/Traditional Chinese names so it
--- works on localized clients like TitanForge.
function T:ClassifyChannel(name)
    if not name or name == "" then return "CHANNEL_OTHER" end
    local n = name:lower()
    -- User-added custom channels take precedence (plain substring match).
    if self.db and self.db.customChannels then
        for cname in pairs(self.db.customChannels) do
            if cname ~= "" and n:find(cname:lower(), 1, true) then
                return "CUSTOM:" .. cname
            end
        end
    end
    if n:find("general") or n:find("综合") or n:find("綜合") then return "CHANNEL_GENERAL" end
    if n:find("trade") or n:find("交易") then return "CHANNEL_TRADE" end
    if n:find("lookingforgroup") or n:find("looking for group") or n:find("lfg") or n:find("lfm")
       or n:find("premade") or n:find("寻求组队") or n:find("尋求組隊") or n:find("寻求") or n:find("尋求")
       or n:find("组队") or n:find("組隊") or n:find("找队") or n:find("找隊") then
        return "CHANNEL_LFG"
    end
    if n:find("world") or n:find("世界") then return "CHANNEL_WORLD" end
    return "CHANNEL_OTHER"
end

--- Add / remove a user-defined custom channel by name (trimmed).
function T:AddCustomChannel(name)
    if not name then return false end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false end
    if not self.db.customChannels then self.db.customChannels = {} end
    self.db.customChannels[name] = true
    return true
end
function T:RemoveCustomChannel(name)
    if not name or not self.db.customChannels then return end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    self.db.customChannels[name] = nil
end

--- Display label + chat color for a tab line's channel key.
function T:TabChannelDisplay(key)
    if type(key) == "string" and key:find("^CUSTOM:") then
        local info = ChatTypeInfo and ChatTypeInfo["CHANNEL"]
        if info then return key:sub(8), info.r, info.g, info.b end
        return key:sub(8), 1, 1, 1
    end
    if type(key) == "string" and key:find("^MSGGROUP:") then
        -- Loot/skill/system/etc.: use WoW's system-message color.
        local info = ChatTypeInfo and ChatTypeInfo["SYSTEM"]
        if info then return key:sub(10), info.r, info.g, info.b end
        return key:sub(10), 1, 1, 0.5
    end
    local label = TAB_CHANNEL_LABEL[key] or key
    local colorKey = (type(key) == "string" and key:find("^CHANNEL")) and "CHANNEL" or key
    if key == "GMOTD" then colorKey = "GUILD" end
    local info = ChatTypeInfo and ChatTypeInfo[colorKey]
    if info then return label, info.r, info.g, info.b end
    return label, 1, 1, 1
end

--- Is this channel currently routed into the Translated tab? (defaults on)
function T:IsTabChannelEnabled(channelKey)
    if type(channelKey) == "string" and channelKey:find("^CUSTOM:") then
        local t = self.db and self.db.customChannels
        if not t then return true end
        local v = t[channelKey:sub(8)]
        if v == nil then return true end
        return v and true or false
    end
    local base = TAB_CHANNEL_BASE[channelKey] or channelKey
    local default = TAB_CHANNEL_DEFAULT[base]
    if default == nil then default = true end
    local t = self.db and self.db.tabChannels
    if not t then return default end
    local v = t[base]
    if v == nil then return default end
    return v and true or false
end

-- Which WoW native message categories the Translated tab can carry, as a real
-- chat tab would. Each logical toggle maps to one or more native message groups
-- (the same identifiers WoW's own "chat settings" checkboxes use).
T.TAB_MSGGROUP_LIST = {
    { key = "LOOT",        label = "Loot" },
    { key = "MONEY",       label = "Money" },
    { key = "CURRENCY",    label = "Currency" },
    { key = "SKILL",       label = "Skill / profession ups" },
    { key = "SYSTEM",      label = "System & errors" },
    { key = "XP",          label = "Experience gains" },
    { key = "REP",         label = "Reputation" },
    { key = "HONOR",       label = "Honor" },
    { key = "ACHIEVEMENT", label = "Achievements" },
    { key = "BG",          label = "Battleground alerts" },
    { key = "NPC",         label = "NPC / creature dialogue" },
    { key = "PET",         label = "Pet info" },
    { key = "PETBATTLE",   label = "Pet battle" },
}
local RCT_MSGGROUP_MAP = {
    LOOT = { "LOOT" }, MONEY = { "MONEY" }, CURRENCY = { "CURRENCY" }, SKILL = { "SKILL" },
    SYSTEM = { "SYSTEM", "ERRORS" }, XP = { "COMBAT_XP_GAIN" }, REP = { "COMBAT_FACTION_CHANGE" },
    HONOR = { "COMBAT_HONOR_GAIN" }, ACHIEVEMENT = { "ACHIEVEMENT", "GUILD_ACHIEVEMENT" },
    BG = { "BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL" },
    NPC = { "MONSTER_SAY", "MONSTER_YELL", "MONSTER_EMOTE", "MONSTER_WHISPER",
            "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER" },
    PET = { "PET_INFO" }, PETBATTLE = { "PET_BATTLE_COMBAT_LOG", "PET_BATTLE_INFO" },
}

function T:IsTabMessageGroupEnabled(key)
    local t = self.db and self.db.tabMessageGroups
    if not t then return false end
    return t[key] and true or false
end

-- The extra categories are now translated and fed into the tab via the event
-- handler (see eventToMsgGroup), not shown raw via native message groups. This
-- strips any native groups a previous version may have added, so lines aren't
-- duplicated (one raw + one translated).
function T:ApplyTabMessageGroups()
    local f = self:GetTranslatedFrame()
    if not f then return end
    if type(ChatFrame_RemoveMessageGroup) ~= "function" then return end
    for _, item in ipairs(self.TAB_MSGGROUP_LIST) do
        for _, grp in ipairs(RCT_MSGGROUP_MAP[item.key] or {}) do
            pcall(ChatFrame_RemoveMessageGroup, f, grp)
        end
    end
end

--- Find our translated tab's chat frame (by stored index, then by name).
function T:GetTranslatedFrame()
    local n = NUM_CHAT_WINDOWS or 10
    local idx = self.db and self.db.translatedTabIndex
    if idx and GetChatWindowInfo then
        local name = GetChatWindowInfo(idx)
        if name == TRANSLATED_TAB_NAME then return _G["ChatFrame" .. idx] end
    end
    if GetChatWindowInfo then
        for i = 1, n do
            if GetChatWindowInfo(i) == TRANSLATED_TAB_NAME then
                if self.db then self.db.translatedTabIndex = i end
                return _G["ChatFrame" .. i]
            end
        end
    end
    return nil
end

--- Create the translated tab if it doesn't exist; make it translation-only.
function T:EnsureTranslatedTab()
    local f = self:GetTranslatedFrame()
    if not f then
        if InCombatLockdown and InCombatLockdown() then return nil end
        if type(FCF_OpenNewWindow) ~= "function" then return nil end
        FCF_OpenNewWindow(TRANSLATED_TAB_NAME, true)   -- 2nd arg = no default channels
        f = self:GetTranslatedFrame()
        if f then
            if ChatFrame_RemoveAllMessageGroups then ChatFrame_RemoveAllMessageGroups(f) end
            if ChatFrame_RemoveAllChannels then ChatFrame_RemoveAllChannels(f) end
            f:AddMessage("|cFF00FF88RC-Translator:|r translated chat will appear here.")
        end
    end
    if f then self:HookChatFrame(f) end   -- so [T] works in this tab too
    if f then self:HookTranslatedEditBox(f) end   -- so typing here translates outgoing
    if f then self:ApplyTabMessageGroups() end   -- loot/skill/system/etc. per user toggles
    if f then self:ProcessGuildMOTD(self._pendingMOTD) end   -- replay MOTD that fired pre-tab
    return f
end

--- Translate an outgoing message: from the language you read/type in (targetLang)
--- into your send language (sendLang, defaults to client locale). Returns nil if
--- nothing to do (no send language, same language, or no translation produced).
function T:TranslateOutgoing(text)
    if not text or text == "" then return nil end
    local src = (self.db and self.db.targetLang) or "en"
    local dst = (self.db and self.db.sendLang) or self:DefaultTargetFromLocale()
    if not dst or dst == "" or dst == src then return nil end
    local out = self:Translate(text, src, dst)
    if out and out ~= "" and out ~= text then return out end
    return nil
end

--- Translate the Guild MOTD into the tab. Handles the login race: GUILD_MOTD
--- often fires before the tab exists, so we stash it and replay on tab creation,
--- and we also fetch the current MOTD directly. Deduped so it prints once.
function T:ProcessGuildMOTD(motd)
    if not (self.db and self.db.enabled and self.db.translatedTab) then return end
    if RCT_Compat.IsSecret(motd) then return end
    if not self:IsTabChannelEnabled("GMOTD") then return end
    if (not motd or motd == "") and GetGuildRosterMOTD then motd = GetGuildRosterMOTD() end
    if not motd or motd == "" then return end
    local frame = self:GetTranslatedFrame()
    if not frame then
        self._pendingMOTD = motd   -- tab not built yet; replay when it is
        return
    end
    if self._lastMOTD == motd then return end   -- already shown this exact MOTD
    self._lastMOTD = motd
    self._pendingMOTD = nil
    self:FeedTranslatedTab(motd, "Guild MOTD", "GMOTD")
end

--- Hook the Translated tab's edit box so typing there translates before sending.
function T:HookTranslatedEditBox(cf)
    if not cf then return end
    local eb = cf.editBox or _G[(cf:GetName() or "") .. "EditBox"]
    if not eb or eb.__rctOutHooked then return end
    eb.__rctOutHooked = true
    if eb.SetText then
        local orig = eb:GetScript("OnEnterPressed")
        eb:SetScript("OnEnterPressed", function(box)
            if T.db and T.db.enabled and T.db.translateOutgoing then
                local txt = box:GetText()
                -- Skip slash commands and empty lines.
                if txt and txt ~= "" and txt:sub(1, 1) ~= "/" then
                    local tr = T:TranslateOutgoing(txt)
                    if tr then
                        box:SetText(tr)
                        local frame = T:GetTranslatedFrame()
                        if frame then frame:AddMessage("|cFF888888you \226\134\146|r " .. tr) end
                    end
                end
            end
            if orig then orig(box) end
        end)
    end
end

--- Close the translated tab (user turned the feature off).
function T:RemoveTranslatedTab()
    local f = self:GetTranslatedFrame()
    if f and type(FCF_Close) == "function" and not (InCombatLockdown and InCombatLockdown()) then
        FCF_Close(f)
    end
    if self.db then self.db.translatedTabIndex = nil end
end

-- Class-color a player's name from their GUID, like the regular chat does.
local function rctClassColorName(name, guid)
    if not name then return "?" end
    if guid and guid ~= "" and GetPlayerInfoByGUID then
        local ok, _localizedClass, classToken = pcall(GetPlayerInfoByGUID, guid)
        if ok and classToken then
            local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
            if c then
                if c.colorStr then return "|c" .. c.colorStr .. name .. "|r" end
                return string.format("|cff%02x%02x%02x%s|r",
                    math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5),
                    math.floor(c.b * 255 + 0.5), name)
            end
        end
    end
    return name
end

-- Timestamp prefix that respects the game's "showTimestamps" chat setting.
local function rctTimestamp()
    local fmt = GetCVar and GetCVar("showTimestamps")
    if fmt and fmt ~= "" and fmt ~= "none" then
        local ok, s = pcall(BetterDate or date, fmt, time())
        if ok and s then return s end
    end
    return ""
end

--- Translate one incoming message into the target language and print it to the tab.
function T:FeedTranslatedTab(text, sender, channelKey, guid)
    local frame = self:GetTranslatedFrame()
    if not frame then return end
    local target = (self.db and self.db.targetLang) or "en"
    local detected = self:DetectLanguage(text)
    local out, wasTranslated = text, false
    if detected and detected ~= target then
        local translated = self:Translate(text, detected, target)
        if translated and translated ~= "" and translated ~= text then
            out = translated
            wasTranslated = true
        end
    end
    -- Tab option: skip messages that were already in the target language.
    if self.db and self.db.translatedTabTranslatedOnly and not wasTranslated then
        return
    end
    local ts = rctTimestamp()
    -- Friendly channel label + the channel's own chat color (guild green, whisper
    -- pink, etc.) so the Translated tab matches the regular chat window.
    local label, r, g, b = self:TabChannelDisplay(channelKey)
    local tag = label and ("[" .. label .. "] ") or ""
    local shownSender = tostring(sender or "?")
    if not (self.db and self.db.tabClassColors == false) then
        shownSender = rctClassColorName(shownSender, guid)
    end
    if sender == nil or sender == "" then
        -- System / message-group line: no speaker, just [tag] translated text.
        frame:AddMessage(string.format("%s%s%s", ts, tag, out), r, g, b)
    else
        frame:AddMessage(string.format("%s%s%s: %s", ts, tag, shownSender, out), r, g, b)
    end
    -- Tab option: show the original line underneath (only when we changed it).
    if self.db and self.db.translatedTabShowOriginal and wasTranslated then
        frame:AddMessage("      " .. text, r * 0.55, g * 0.55, b * 0.55)
    end
end

--- Chat filter: highlights suspected foreign words + appends clickable [T].
-- This runs BEFORE OnEvent, so we store the message here to ensure the [T] link ID is correct.
function T.ChatFilter(self, event, text, sender, ...)
    if not T.db or not T.db.enabled then
        return false, text, sender, ...
    end
    -- Retail and WoW Forever can hide chat text from addons (secret values, e.g.
    -- in instances during combat). Those lines can't be read or changed: pass
    -- them through untouched.
    if RCT_Compat.IsSecret(text) or RCT_Compat.IsSecret(sender) then
        return false, text, sender, ...
    end
    
    local playerName = RCT_Compat.GetPlayerName()
    if sender and sender:find(playerName) then
        return false, text, sender, ...
    end
    
    local channelKey = event and eventToChannel[event] or nil

    -- Respect the per-channel settings for numbered channels so a disabled
    -- category (LookingForGroup, Trade, ...) is NOT decorated with [T]/foreign-word
    -- highlights. ChatFilter runs the VISIBLE inline path, so without this gate the
    -- highlight still fired on LFG lines and looked like translation even with
    -- LookingForGroup turned off. Mirrors the numbered-channel gate in OnEvent.
    if event == "CHAT_MSG_CHANNEL" then
        if not (T.db.channels and T.db.channels[channelKey]) then
            return false, text, sender, ...
        end
        local _, cn, _t, _f, _z, _idx, cb = ...
        if not T:IsTabChannelEnabled(T:ClassifyChannel(((cn or "") .. " " .. (cb or "")))) then
            return false, text, sender, ...
        end
    end

    -- Increment and store HERE — ChatFilter fires before OnEvent,
    -- so this ensures the [T] link ID matches the stored message.
    msgCounter = msgCounter + 1
    T:StoreMessage(msgCounter, text, sender, channelKey)
    
    -- Highlight foreign words (gold colored hyperlinks = underlined on hover)
    local highlighted = T:HighlightForeignWords(text, msgCounter)
    
    -- Append clickable [T] that opens IM translation window
    local translateLink = "|cFF00CCFF|Hrctranslate:" .. msgCounter .. "|h[T]|h|r"
    local newText = highlighted .. " " .. translateLink
    
    return false, newText, sender, ...
end

-- ============================================================
-- HYPERLINK CLICK HANDLER
-- ============================================================

--- Handle clicks on our custom [T] and foreign-word hyperlinks.
-- Hooked onto each ChatFrame's OnHyperlinkClick (SetItemRef does NOT fire for custom link types).
function T:HandleHyperlinkClick(chatFrame, link, text, button)
    -- Scan progress link -> open the dictionary-scan window
    if link == "rctscan" then
        T:ShowScanProgress()
        return true
    end

    -- [T] click -> open IM window with translation
    local msgId = link:match("^rctranslate:(%d+)")
    if msgId then
        msgId = tonumber(msgId)
        for _, msgData in ipairs(T.recentMessages) do
            if msgData.id == msgId then
                T:TranslateToIM(msgData)
                return true
            end
        end
        -- Fallback: translate most recent message
        if T.recentMessages[1] then
            T:TranslateToIM(T.recentMessages[1])
        end
        return true
    end

    -- Foreign word click -> quick single-word translation in chat
    local wordMsgId, wordLang, wordText = link:match("^rctword:(%d+):(%w+):(.+)")
    if wordText and wordLang then
        T:EnsureLanguageLoaded(wordLang)
        local langData = T.Languages[wordLang]
        if langData and langData.reverse then
            local translated = langData.reverse[wordText:lower()]
            if translated then
                local targetName = T.db and T.Languages[T.db.targetLang] and T.Languages[T.db.targetLang].name or "Target"
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cFFFFAA00[RC-T]|r |cFFFFCC00%s|r (%s) = |cFF80FF80%s|r",
                        wordText, langData.name or wordLang, translated))
            end
        end
        return true
    end

    return false  -- Not our link, let WoW handle it
end

-- ============================================================
-- FIRST-RUN DICTIONARY SCAN
-- ============================================================
-- On first install we (1) read the player's client language from their game
-- settings and set that as the translation target, and (2) walk the packed
-- dictionary DB counting indexed phrases so the user sees the addon prepare
-- itself. The walk is NON-DESTRUCTIVE (it counts lines in the packed blobs and
-- leaves them intact for lazy loading) and is spread across frames so it never
-- freezes the client. A chat line announces it with a clickable progress link.

T.scanState = { running = false, done = false, index = 0, total = 0,
                phrases = 0, currentName = "", localeName = "", targetName = "" }

local LOCALE_NAMES = {
    enUS="English", enGB="English", deDE="German", frFR="French", itIT="Italian",
    esES="Spanish", esMX="Spanish (LatAm)", ptBR="Portuguese", ptPT="Portuguese",
    ruRU="Russian", koKR="Korean", zhCN="Simplified Chinese", zhTW="Traditional Chinese",
}

--- Count translated (non-empty) lines in a packed blob WITHOUT expanding it.
function T:CountPackedEntries(code)
    local blob = self.PackedDicts and self.PackedDicts[code]
    if not blob then
        local d = self.Languages[code]
        return (d and d.wordCount) or 0     -- already expanded earlier
    end
    local count = 0
    for value in blob:gmatch("([^\n]*)\n?") do
        if value ~= "" then count = count + 1 end
    end
    return count
end

--- Build the list of language codes to scan (everything with a dictionary).
function T:BuildScanList()
    local list = {}
    if self.LanguageRegistry then
        for _, info in ipairs(self.LanguageRegistry) do
            if info.code ~= "en" then
                list[#list+1] = { code = info.code, name = info.name }
            end
        end
    end
    return list
end

--- Kick off (or restart) the first-run scan. announce=true prints the chat line.
function T:StartFirstRunScan(announce)
    local s = self.scanState
    if s.running then
        if announce then self:ShowScanProgress() end
        return
    end

    local loc = (GetLocale and GetLocale()) or "enUS"
    s.localeName = LOCALE_NAMES[loc] or "English"
    local tgt = self.db and self.db.targetLang or "en"
    s.targetName = (self.Languages[tgt] and self.Languages[tgt].name)
                   or (tgt == "en" and "English") or tgt

    s.list       = self:BuildScanList()
    s.total      = #s.list
    s.index      = 0
    s.phrases    = 0
    s.currentName= ""
    s.running    = true
    s.done       = false

    if announce then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[RC-Translator]|r Translator scan has started. "
            .. "|cFF00CCFF|Hrctscan|h[Show progress]|h|r")
    end

    self:EnsureScanFrame()
    self:UpdateScanFrame()

    -- Incremental driver: one language per tick, ~50/sec, so no frame hitch.
    if not self.scanDriver then
        self.scanDriver = CreateFrame("Frame")
    end
    local acc = 0
    self.scanDriver:SetScript("OnUpdate", function(drv, elapsed)
        acc = acc + elapsed
        if acc < 0.02 then return end
        acc = 0
        local st = self.scanState
        if st.index >= st.total then
            drv:SetScript("OnUpdate", nil)
            st.running = false
            st.done = true
            st.currentName = ""
            if self.db then self.db.firstRunScanDone = true end
            self:UpdateScanFrame()
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cFF00FF00[RC-Translator]|r Scan complete — %d phrases across %d languages indexed. "
                .. "Click the |cFF00CCFF[T]|r on a message to open its translation in the translator window.  "
                .. "|cFF00CCFF|Hrctscan|h[Change reading language]|h|r",
                st.phrases, st.total))
            return
        end
        st.index = st.index + 1
        local item = st.list[st.index]
        st.currentName = item.name
        st.phrases = st.phrases + self:CountPackedEntries(item.code)
        self:UpdateScanFrame()
    end)
end

--- Build the progress window (once).
function T:EnsureScanFrame()
    if self.scanFrame then return end
    local f = CreateFrame("Frame", "RCT_ScanWindow", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(430, 220)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", f.TitleBg or f, "TOP", 0, f.TitleBg and -3 or -5)
    f.title:SetText("|cFF00FF00RC-Translator|r  Dictionary Scan")

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.status:SetPoint("TOP", f, "TOP", 0, -34)

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetSize(370, 20)
    bar:SetPoint("TOP", f, "TOP", 0, -64)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.30, 0.80, 0.35)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar); bg:SetColorTexture(0, 0, 0, 0.5)
    f.bar = bar

    f.detail = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.detail:SetPoint("TOP", bar, "BOTTOM", 0, -8)

    -- Reading-language picker: choose the language foreign chat is translated INTO.
    f.readLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.readLabel:SetPoint("TOP", f.detail, "BOTTOM", -70, -12)
    f.readLabel:SetText("Read chat in:")

    local dd = CreateFrame("Frame", "RCT_ScanTargetDD", f, "UIDropDownMenuTemplate")
    dd:SetPoint("LEFT", f.readLabel, "RIGHT", -6, -2)
    UIDropDownMenu_SetWidth(dd, 150)
    UIDropDownMenu_Initialize(dd, function(_, level)
        local sorted = {}
        for code, langData in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then
                sorted[#sorted+1] = { code = code, name = langData.name }
            end
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        for _, e in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = e.name .. " (" .. e.code .. ")"
            info.value = e.code
            info.checked = (e.code == T.db.targetLang)
            info.func = function(self)
                T:EnableLanguage(self.value)
                T.db.targetLang = self.value
                T.scanState.targetName = (T.Languages[self.value] and T.Languages[self.value].name) or self.value
                UIDropDownMenu_SetText(dd, T.scanState.targetName .. " (" .. self.value .. ")")
                if T.IMUpdateOutLabel then T:IMUpdateOutLabel() end
                T:UpdateScanFrame()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    f.targetDD = dd

    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.footer:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    f.footer:SetWidth(400); f.footer:SetJustifyH("CENTER")

    self.scanFrame = f
end

--- Push current scanState into the window.
function T:UpdateScanFrame()
    local f = self.scanFrame
    if not f then return end
    local s = self.scanState
    if f.bar then
        f.bar:SetMinMaxValues(0, math.max(1, s.total))
        f.bar:SetValue(s.done and s.total or s.index)
    end
    if f.targetDD then
        local tgt = self.db and self.db.targetLang or "en"
        local nm = (self.Languages[tgt] and self.Languages[tgt].name) or tgt
        UIDropDownMenu_SetText(f.targetDD, nm .. " (" .. tgt .. ")")
    end
    if s.done then
        f.status:SetText("|cFF80FF80Scan complete|r")
        f.detail:SetText(string.format("%d languages  ·  %d phrases indexed", s.total, s.phrases))
        f.footer:SetText(string.format(
            "Detected your game client as |cFFFFD100%s|r.  Pick your reading language above;\n"
            .. "foreign chat gets a clickable |cFF00CCFF[T]|r that opens the translation in the translator window.",
            s.localeName))
    else
        f.status:SetText("Scanning dictionaries...")
        f.detail:SetText(string.format("%s   (%d / %d)   ·   %d phrases",
            s.currentName ~= "" and s.currentName or "...", s.index, s.total, s.phrases))
        f.footer:SetText(string.format("Detected your game client as |cFFFFD100%s|r", s.localeName))
    end
end

--- Open the progress window (works during or after the scan).
function T:ShowScanProgress()
    self:EnsureScanFrame()
    self:UpdateScanFrame()
    self.scanFrame:Show()
end

-- ============================================================
-- PROFILE SYSTEM
-- ============================================================

--- Initialize profile system. Migrates old flat DB to profiles on first run.
function T:InitProfiles()
    local db = RC_TranslatorDB

    -- Already migrated?
    if db.profiles and db.activeProfile then
        -- Load active profile
        local name = db.activeProfile
        if not db.profiles[name] then
            name = next(db.profiles) or "Default"
            db.activeProfile = name
        end
        T.db = db.profiles[name]
        T.profileName = name
        return
    end

    -- First time: migrate existing flat settings into "Default" profile
    db.profiles = {}
    db.activeProfile = "Default"

    local profile = {}
    for k, v in pairs(T.defaults) do
        if db[k] ~= nil then
            profile[k] = db[k]
        elseif type(v) == "table" then
            profile[k] = {}
            for kk, vv in pairs(v) do profile[k][kk] = vv end
        else
            profile[k] = v
        end
    end
    db.profiles["Default"] = profile

    -- Clean old flat keys (now stored in profile)
    for k in pairs(T.defaults) do
        db[k] = nil
    end

    T.db = db.profiles["Default"]
    T.profileName = "Default"
end

--- Apply defaults to active profile (fill missing keys)
--- Map the WoW client locale to a dictionary code, so a fresh install
--- translates foreign chat into the language the player actually reads,
--- with zero configuration. Falls back to English.
function T:DefaultTargetFromLocale()
    local loc = (GetLocale and GetLocale()) or "enUS"
    local map = {
        enUS = "en",  enGB = "en",
        deDE = "de",  frFR = "fr",  itIT = "it",
        esES = "es",  esMX = "esMX",
        ptBR = "ptBR", ptPT = "pt",
        ruRU = "ru",  koKR = "ko",
        zhCN = "zh",  zhTW = "zhTW",
    }
    return map[loc] or "en"
end

function T:ApplyDefaults()
    for k, v in pairs(T.defaults) do
        if T.db[k] == nil then
            if type(v) == "table" then
                T.db[k] = {}
                for kk, vv in pairs(v) do T.db[k][kk] = vv end
            else
                T.db[k] = v
            end
        elseif type(v) == "table" and type(T.db[k]) == "table" then
            for kk, vv in pairs(v) do
                if T.db[k][kk] == nil then T.db[k][kk] = vv end
            end
        end
    end

    -- One-time "just works" defaults, applied in versioned steps.
    local sv = T.db.smartDefaultsVersion or 0
    -- v2: target follows the client's language (moves only the arbitrary old
    -- Spanish default; a target the user deliberately chose is preserved).
    if sv < 2 then
        if T.db.targetLang == nil or T.db.targetLang == "es" then
            T.db.targetLang = T:DefaultTargetFromLocale()
        end
    end
    -- v3: default to button-driven translation. Foreign messages get a clickable
    -- [T] that opens the translation in the translator window, instead of being
    -- auto-dumped inline into chat.
    if sv < 3 then
        T.db.autoTranslate = false
        T.db.smartDefaultsVersion = 3
    end
    -- v4: Translated tab on by default (new feature; enable once).
    if sv < 4 then
        T.db.translatedTab = true
        T.db.smartDefaultsVersion = 4
    end
    -- v5: turn on the useful message-type categories for the Translated tab so
    -- loot, currency, reputation, NPC dialogue, etc. translate there out of the
    -- box (System/XP/Honor/Pet stay off — spammy/numeric; toggle any as desired).
    if sv < 5 then
        T.db.tabMessageGroups = T.db.tabMessageGroups or {}
        for _, k in ipairs({ "LOOT", "MONEY", "CURRENCY", "SKILL", "REP",
                             "ACHIEVEMENT", "BG", "NPC" }) do
            T.db.tabMessageGroups[k] = true
        end
        T.db.smartDefaultsVersion = 5
    end
end

function T:CreateProfile(name)
    if not name or name == "" then return false, "Empty name" end
    if RC_TranslatorDB.profiles[name] then return false, "Profile already exists" end

    local profile = {}
    for k, v in pairs(T.defaults) do
        if type(v) == "table" then
            profile[k] = {}
            for kk, vv in pairs(v) do profile[k][kk] = vv end
        else
            profile[k] = v
        end
    end
    RC_TranslatorDB.profiles[name] = profile
    return true
end

function T:SwitchProfile(name)
    if not name or not RC_TranslatorDB.profiles[name] then return false, "Profile not found" end

    RC_TranslatorDB.activeProfile = name
    T.db = RC_TranslatorDB.profiles[name]
    T.profileName = name
    T:ApplyDefaults()
    T:RebuildIgnoreLookup()
    T:LoadCustomDictionary()
    T:IMUpdateOutLabel()
    return true
end

function T:DeleteProfile(name)
    if not name or not RC_TranslatorDB.profiles[name] then return false, "Profile not found" end
    if name == T.profileName then return false, "Cannot delete active profile" end

    -- Count profiles
    local count = 0
    for _ in pairs(RC_TranslatorDB.profiles) do count = count + 1 end
    if count <= 1 then return false, "Cannot delete last profile" end

    RC_TranslatorDB.profiles[name] = nil
    return true
end

function T:CopyProfile(fromName, toName)
    if not fromName or not RC_TranslatorDB.profiles[fromName] then return false, "Source not found" end
    if not toName or toName == "" then return false, "Empty target name" end
    if RC_TranslatorDB.profiles[toName] then return false, "Target already exists" end

    -- Deep copy
    local source = RC_TranslatorDB.profiles[fromName]
    local copy = {}
    for k, v in pairs(source) do
        if type(v) == "table" then
            copy[k] = {}
            for kk, vv in pairs(v) do
                if type(vv) == "table" then
                    copy[k][kk] = {}
                    for kkk, vvv in pairs(vv) do copy[k][kk][kkk] = vvv end
                else
                    copy[k][kk] = vv
                end
            end
        else
            copy[k] = v
        end
    end
    RC_TranslatorDB.profiles[toName] = copy
    return true
end

function T:GetProfileList()
    local list = {}
    for name in pairs(RC_TranslatorDB.profiles) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

-- ============================================================
-- DICTIONARY SHARING (Addon Messages)
-- ============================================================

local ADDON_MSG_PREFIX = "RCT"
T.shareIncoming = {}  -- Buffer for incoming chunked data: { [sender] = { lang=, chunks={}, total=, received= } }

--- Serialize custom dictionary entries for a language into a string
function T:SerializeCustomDict(langCode)
    if not self.db.customDictionary or not self.db.customDictionary[langCode] then return nil end
    local parts = {}
    for eng, trans in pairs(self.db.customDictionary[langCode]) do
        -- Escape pipe characters (WoW uses | for color codes)
        local safeEng = eng:gsub("|", "||"):gsub("~", "~~")
        local safeTrans = trans:gsub("|", "||"):gsub("~", "~~")
        table.insert(parts, safeEng .. "=" .. safeTrans)
    end
    return table.concat(parts, "~")
end

--- Deserialize a dictionary string back into key-value pairs
function T:DeserializeCustomDict(data)
    local entries = {}
    for pair in data:gmatch("[^~]+") do
        local eng, trans = pair:match("^(.-)=(.+)")
        if eng and trans then
            eng = eng:gsub("||", "|"):gsub("~~", "~")
            trans = trans:gsub("||", "|"):gsub("~~", "~")
            entries[eng] = trans
        end
    end
    return entries
end

--- Send custom dictionary to a player or channel
--- channel: "WHISPER", "PARTY", "RAID", "GUILD"
--- target: player name (required for WHISPER)
function T:ShareDictionary(langCode, channel, target)
    if not langCode then return false, "No language specified" end
    if not self.db.customDictionary or not self.db.customDictionary[langCode] then
        return false, "No custom entries for " .. langCode
    end

    local data = self:SerializeCustomDict(langCode)
    if not data or data == "" then return false, "Nothing to share" end

    local langName = self.Languages[langCode] and self.Languages[langCode].name or langCode
    local entryCount = self:GetCustomEntryCount(langCode)

    -- Chunk into 230-byte pieces (leave room for header)
    local chunks = {}
    local chunkSize = 220
    for i = 1, #data, chunkSize do
        table.insert(chunks, data:sub(i, i + chunkSize - 1))
    end

    -- Send header: SHARE_HDR:langCode:langName:totalChunks:entryCount
    local header = string.format("SHARE_HDR:%s:%s:%d:%d", langCode, langName, #chunks, entryCount)
    if channel == "WHISPER" then
        RCT_Compat.SendAddonMessage(ADDON_MSG_PREFIX, header, "WHISPER", target)
    else
        RCT_Compat.SendAddonMessage(ADDON_MSG_PREFIX, header, channel)
    end

    -- Send chunks: SHARE_CHK:langCode:chunkNum:data
    for i, chunk in ipairs(chunks) do
        local msg = string.format("SHARE_CHK:%s:%d:%s", langCode, i, chunk)
        if channel == "WHISPER" then
            RCT_Compat.SendAddonMessage(ADDON_MSG_PREFIX, msg, "WHISPER", target)
        else
            RCT_Compat.SendAddonMessage(ADDON_MSG_PREFIX, msg, channel)
        end
    end

    print(string.format("|cFF00FF00[RC-Translator]|r Shared %d custom %s entries (%d chunks) via %s%s",
        entryCount, langName, #chunks, channel, target and (" to " .. target) or ""))
    return true
end

--- Handle incoming addon messages
function T:HandleAddonMessage(prefix, message, channel, sender)
    if RCT_Compat.IsSecret(prefix) or RCT_Compat.IsSecret(message) or RCT_Compat.IsSecret(sender) then return end
    if prefix ~= ADDON_MSG_PREFIX then return end

    -- Don't process our own messages
    local playerName = RCT_Compat.GetPlayerName()
    if sender and sender:find(playerName) then return end

    -- Strip realm name from sender if present
    local shortSender = sender:match("^([^-]+)") or sender

    -- SHARE_HDR:langCode:langName:totalChunks:entryCount
    local msgType, rest = message:match("^(%u+_%u+):(.+)")
    if not msgType then return end

    if msgType == "SHARE_HDR" then
        local langCode, langName, totalChunks, entryCount = rest:match("^([^:]+):([^:]+):(%d+):(%d+)")
        if langCode and totalChunks then
            totalChunks = tonumber(totalChunks)
            entryCount = tonumber(entryCount)
            self.shareIncoming[shortSender] = {
                lang = langCode,
                langName = langName,
                chunks = {},
                total = totalChunks,
                received = 0,
                entryCount = entryCount,
                time = time(),
            }
            if T.debugMode then
                print(string.format("|cFF00FF00[RC-T]|r Receiving %d %s entries from %s (%d chunks)...",
                    entryCount, langName, shortSender, totalChunks))
            end
        end

    elseif msgType == "SHARE_CHK" then
        local langCode, chunkNum, data = rest:match("^([^:]+):(%d+):(.+)")
        if langCode and chunkNum and data then
            chunkNum = tonumber(chunkNum)
            local incoming = self.shareIncoming[shortSender]
            if incoming and incoming.lang == langCode then
                incoming.chunks[chunkNum] = data
                incoming.received = incoming.received + 1

                -- All chunks received?
                if incoming.received >= incoming.total then
                    -- Reassemble
                    local ordered = {}
                    for i = 1, incoming.total do
                        table.insert(ordered, incoming.chunks[i] or "")
                    end
                    local fullData = table.concat(ordered, "")
                    local entries = self:DeserializeCustomDict(fullData)

                    local count = 0
                    for _ in pairs(entries) do count = count + 1 end

                    -- Store pending import and show confirmation popup
                    self.pendingImport = {
                        sender = shortSender,
                        langCode = langCode,
                        langName = incoming.langName,
                        entries = entries,
                        count = count,
                    }
                    self.shareIncoming[shortSender] = nil

                    -- Show accept/reject popup
                    T:ShowSharePopup()
                end
            end
        end
    end
end

--- Show a popup asking the user to accept/reject shared dictionary entries
function T:ShowSharePopup()
    if not self.pendingImport then return end
    local p = self.pendingImport

    StaticPopupDialogs["RCT_SHARE_ACCEPT"] = {
        text = string.format(
            "|cFF00FF00[RC-Translator]|r\n\n|cFFFFFF00%s|r wants to share |cFF00CCFF%d|r custom dictionary entries for |cFFFFAA00%s|r.\n\nAccept?",
            p.sender, p.count, p.langName),
        button1 = "Accept",
        button2 = "Decline",
        OnAccept = function()
            T:AcceptSharedDictionary()
        end,
        OnCancel = function()
            print("|cFF00FF00[RC-Translator]|r Declined shared dictionary from " .. p.sender)
            T.pendingImport = nil
        end,
        timeout = 60,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("RCT_SHARE_ACCEPT")
end

--- Accept pending shared dictionary entries
function T:AcceptSharedDictionary()
    if not self.pendingImport then return end
    local p = self.pendingImport
    local added = 0

    for eng, trans in pairs(p.entries) do
        local ok = self:AddCustomEntry(p.langCode, eng, trans)
        if ok then added = added + 1 end
    end

    print(string.format("|cFF00FF00[RC-Translator]|r Imported |cFFFFFF00%d|r entries for %s from %s!",
        added, p.langName, p.sender))
    self.pendingImport = nil

    -- Refresh UI if open
    if T.RefreshCustomDisplay then T:RefreshCustomDisplay() end
end

--- Register the addon message prefix and event
function T:InitSharing()
    RCT_Compat.RegisterAddonMessagePrefix(ADDON_MSG_PREFIX)

    local shareFrame = CreateFrame("Frame")
    shareFrame:RegisterEvent("CHAT_MSG_ADDON")
    shareFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
        T:HandleAddonMessage(prefix, message, channel, sender)
    end)
end

-- ============================================================
-- INITIALIZATION & SAVED VARIABLES
-- ============================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("GUILD_MOTD")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "GUILD_MOTD" then
        -- Guild Message of the Day arrives on its own event (not a chat message).
        T:ProcessGuildMOTD(arg1)
        return
    end
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        if not RC_TranslatorDB then
            RC_TranslatorDB = {}
        end
        
        -- Initialize profile system (migrates old flat DB if needed)
        T:InitProfiles()
        T:ApplyDefaults()

        for _, evt in ipairs(CHAT_EVENTS) do
            chatFrame:RegisterEvent(evt)
        end
        -- Extra categories for the Translated tab (loot, skill, system, NPC, ...).
        -- Guarded: some events don't exist on older clients.
        chatFrame:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
        for evt in pairs(eventToMsgGroup) do
            pcall(function() chatFrame:RegisterEvent(evt) end)
        end
        
        T:RebuildIgnoreLookup()
        T:LoadCustomDictionary()
        T:InitSharing()
        
        -- Register English as a selectable target language
        -- (English is the implicit pivot — all dictionaries are English↔Foreign)
        if not T.Languages["en"] then
            T.Languages["en"] = {
                name = "English",
                code = "en",
                dictionary = {},
                reverse = {},
                wordCount = 0,
                loaded = true,
            }
        end

        -- Pull in only the dictionaries this profile actually uses.
        T:LoadEnabledLanguages()
        
    elseif event == "PLAYER_LOGIN" then
        T:PrintWelcome()
        T:SetupChatHooks()

        if T.db and T.db.translatedTab then
            if C_Timer and C_Timer.After then
                C_Timer.After(1, function() T:EnsureTranslatedTab() end)
                -- The MOTD may have fired before we loaded; request the roster and
                -- fetch it directly once it's available.
                C_Timer.After(4, function()
                    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
                    elseif GuildRoster then GuildRoster() end
                    if C_Timer and C_Timer.After then
                        C_Timer.After(1, function() T:ProcessGuildMOTD() end)
                    end
                end)
            else
                T:EnsureTranslatedTab()
            end
        end

        -- First install: read the player's client language and run a one-time
        -- dictionary scan with a clickable progress link. Deferred a moment so
        -- it lands after the usual login chat spam.
        if T.db and not T.db.firstRunScanDone then
            if C_Timer and C_Timer.After then
                C_Timer.After(2, function() T:StartFirstRunScan(true) end)
            else
                T:StartFirstRunScan(true)
            end
        end
    end
end)

-- ============================================================
-- LANGUAGE VISIBILITY
-- ============================================================

--- "15,595 words" or "not loaded", for UI display.
function T:LangSizeLabel(code)
    if code == "en" then return "base language" end
    local d = self.Languages[code]
    if not d then return "?" end
    if not (d.loaded and d.dictionary) then return "not loaded" end
    return d.wordCount .. " words"
end

function T:IsLanguageVisible(code)
    local langData = self.Languages[code]
    if not langData then return false end
    if not langData.hidden then return true end
    return self.db.secretUnlocked == true
end

--- Resolve the source language for a given text.
--- If sourceLang is "auto", auto-detect. Otherwise use the manual setting.
function T:ResolveSourceLang(text)
    if not self.db or self.db.sourceLang == "auto" then
        local detected, confidence, method = self:DetectLanguage(text)
        if detected and confidence and confidence > 0.15 then
            return detected, confidence, method
        end
        return nil, 0, nil
    else
        -- Manual source language selected
        return self.db.sourceLang, 1.0, "manual"
    end
end

function T:UnlockSecretLanguages()
    self.db.secretUnlocked = true
    -- Epic unlock message
    print(" ")
    print("|cFFFF00FF====================================|r")
    print("|cFFFF00FF  SECRET LANGUAGES UNLOCKED!|r")
    print("|cFFFF00FF====================================|r")
    print("|cFF00FF00  >> Orcish (Horde Chat)|r")
    print("|cFF00FF00  >> Common (Alliance Chat)|r")
    print("|cFFFFFF00  Cross-faction languages are now|r")
    print("|cFFFFFF00  available in the language picker!|r")
    print("|cFFFF00FF====================================|r")
    print(" ")
    -- Play a sound for extra flair
    PlaySoundFile(RCT_Compat.SOUND_LEVELUP)  -- works across all versions
end

-- ============================================================
-- SECRET CODE CHECKER
-- ============================================================

local SECRET_CODE = "uuddlrlrba"

function T:CheckSecretCode(input)
    if not input then return false end
    if input:lower() == SECRET_CODE then
        self:UnlockSecretLanguages()
        return true
    end
    return false
end

-- ============================================================
-- SLASH COMMANDS
-- ============================================================

SLASH_RCTRANSLATOR1 = "/rct"
SLASH_RCTRANSLATOR2 = "/translate"
SLASH_RCTRANSLATOR3 = "/rctranslator"

SlashCmdList["RCTRANSLATOR"] = function(msg)
    local cmd, arg = msg:match("^(%S+)%s*(.*)")
    cmd = cmd and cmd:lower() or msg:lower()
    
    if cmd == "" or cmd == "help" then
        T:PrintHelp()
        
    elseif cmd == "scan" then
        T:StartFirstRunScan(true)
        T:ShowScanProgress()

    elseif cmd == "tab" then
        T.db.translatedTab = not T.db.translatedTab
        if T.db.translatedTab then
            T:EnsureTranslatedTab()
            print("|cFF00FF00[RC-Translator]|r Translated chat tab |cFF00FF00ON|r.")
        else
            T:RemoveTranslatedTab()
            print("|cFF00FF00[RC-Translator]|r Translated chat tab |cFFFF0000OFF|r.")
        end

    elseif cmd == "on" or cmd == "enable" then
        T.db.enabled = true
        print("|cFF00FF00[RC-Translator]|r Enabled!")
        
    elseif cmd == "off" or cmd == "disable" then
        T.db.enabled = false
        print("|cFF00FF00[RC-Translator]|r Disabled.")

    elseif cmd == "secret" then
        T:OpenSecretPanel()
        
    elseif cmd == "lang" or cmd == "language" then
        if arg and arg ~= "" then
            local code = arg:lower()
            if T.Languages[code] and T:EnableLanguage(code) then
                T.db.targetLang = code
                print("|cFF00FF00[RC-Translator]|r Target language set to: " .. T.Languages[code].name)
            else
                print("|cFFFF0000[RC-Translator]|r Unknown language code: " .. code)
                T:PrintLanguages()
            end
        else
            T:PrintLanguages()
        end
        
    elseif cmd == "auto" then
        T.db.autoTranslate = not T.db.autoTranslate
        print("|cFF00FF00[RC-Translator]|r Auto-translate: " .. (T.db.autoTranslate and "ON" or "OFF"))
        
    elseif cmd == "last" then
        local count = tonumber(arg) or 1
        for i = 1, math.min(count, 5) do
            if T.recentMessages[i] then
                T:TranslateToIM(T.recentMessages[i])
            end
        end
        
    elseif cmd == "t" or cmd == "say" then
        if arg and arg ~= "" then
            -- Resolve source language (auto-detect or manual)
            local detectedLang, confidence, method = T:ResolveSourceLang(arg)
            local fromLang = detectedLang or "en"
            local result, wt, tw = T:Translate(arg, fromLang, T.db.targetLang)
            if wt > 0 then
                local fromName = fromLang == "en" and "English" or (T.Languages[fromLang] and T.Languages[fromLang].name or fromLang)
                local langName = T.Languages[T.db.targetLang] and T.Languages[T.db.targetLang].name or T.db.targetLang
                print("|cFFFFAA00[RC-T " .. fromName .. " -> " .. langName .. "]|r " .. result .. " |cFF888888(" .. wt .. "/" .. tw .. " words)|r")
            else
                print("|cFFFF0000[RC-Translator]|r Could not translate. Dictionary may not have those words.")
            end
        end
        
    elseif cmd == "detect" then
        if arg and arg ~= "" then
            local lang, score, method = T:DetectLanguage(arg)
            if lang then
                local langName = lang == "en" and "English" or (T.Languages[lang] and T.Languages[lang].name or lang)
                local confPct = math.floor(score * 100)
                print(string.format("|cFF00FF00[RC-Translator]|r Detected: |cFFFFFF00%s|r (%d%% confidence, via %s)", langName, confPct, method or "unknown"))
            else
                print("|cFF00FF00[RC-Translator]|r Could not detect language.")
            end
        end
        
    elseif cmd == "stats" then
        T:PrintStats()
        
    elseif cmd == "config" or cmd == "options" then
        T:ToggleOptionsUI()
        
    elseif cmd == "debug" then
        T.debugMode = not T.debugMode
        print("|cFF00FF00[RC-Translator]|r Debug mode: " .. (T.debugMode and "ON" or "OFF"))
        
    elseif cmd == "im" or cmd == "chat" or cmd == "window" then
        T:ToggleIMWindow()
        
    elseif cmd == "ignore" then
        if arg and arg ~= "" then
            local subCmd, subArg = arg:match("^(%S+)%s*(.*)")
            if subCmd == "remove" or subCmd == "del" or subCmd == "delete" then
                if subArg and subArg ~= "" then
                    if T:RemoveIgnoreWord(subArg) then
                        print("|cFF00FF00[RC-Translator]|r Removed '|cFFFFFF00" .. subArg .. "|r' from ignore list.")
                    else
                        print("|cFF00FF00[RC-Translator]|r '|cFFFFFF00" .. subArg .. "|r' is not in the ignore list.")
                    end
                end
            elseif subCmd == "list" then
                local count = #T.db.ignoreWords
                print("|cFF00FF00[RC-Translator]|r Ignore list (" .. count .. " words):")
                for i = 1, count, 10 do
                    local chunk = {}
                    for j = i, math.min(i + 9, count) do
                        table.insert(chunk, T.db.ignoreWords[j])
                    end
                    print("  " .. table.concat(chunk, ", "))
                end
            elseif subCmd == "clear" then
                T.db.ignoreWords = {}
                T:RebuildIgnoreLookup()
                print("|cFF00FF00[RC-Translator]|r Ignore list cleared.")
            else
                local added = {}
                for word in arg:gmatch("%S+") do
                    if T:AddIgnoreWord(word) then
                        table.insert(added, word)
                    end
                end
                if #added > 0 then
                    print("|cFF00FF00[RC-Translator]|r Added to ignore list: |cFFFFFF00" .. table.concat(added, ", ") .. "|r")
                else
                    print("|cFF00FF00[RC-Translator]|r Those words are already ignored.")
                end
            end
        else
            print("|cFF00FF00[RC-Translator]|r Ignore commands:")
            print("  |cFFFFFF00/rct ignore <word>|r - Add word(s) to ignore list")
            print("  |cFFFFFF00/rct ignore remove <word>|r - Remove a word")
            print("  |cFFFFFF00/rct ignore list|r - Show all ignored words")
            print("  |cFFFFFF00/rct ignore clear|r - Clear the entire ignore list")
        end
        
    elseif cmd == "add" then
        -- /rct add <lang> <english> = <translation>
        if arg and arg ~= "" then
            local langCode, rest = arg:match("^(%S+)%s+(.*)")
            if langCode and rest then
                local english, translation = rest:match("^(.-)%s*=%s*(.+)")
                if english and translation then
                    langCode = langCode:lower()
                    local ok, err = T:AddCustomEntry(langCode, english, translation)
                    if ok then
                        local langName = T.Languages[langCode] and T.Languages[langCode].name or langCode
                        print(string.format("|cFF00FF00[RC-Translator]|r Added custom entry to %s: |cFFFFFF00%s|r = |cFFFFCC00%s|r", langName, english:lower(), translation))
                    else
                        print("|cFFFF0000[RC-Translator]|r Failed to add: " .. (err or "unknown error"))
                    end
                else
                    print("|cFFFF0000[RC-Translator]|r Usage: /rct add <lang> <english> = <translation>")
                    print("|cFF888888  Example: /rct add es awesome = genial|r")
                end
            else
                print("|cFFFF0000[RC-Translator]|r Usage: /rct add <lang> <english> = <translation>")
                print("|cFF888888  Example: /rct add fr mount up = en selle|r")
            end
        else
            print("|cFFFF0000[RC-Translator]|r Usage: /rct add <lang> <english> = <translation>")
            print("|cFF888888  Example: /rct add de pull now = jetzt pullen|r")
        end

    elseif cmd == "remove" or cmd == "del" then
        -- /rct remove <lang> <english>
        if arg and arg ~= "" then
            local langCode, english = arg:match("^(%S+)%s+(.*)")
            if langCode and english then
                langCode = langCode:lower()
                local ok, err = T:RemoveCustomEntry(langCode, english)
                if ok then
                    print("|cFF00FF00[RC-Translator]|r Removed custom entry: |cFFFFFF00" .. english .. "|r")
                else
                    print("|cFFFF0000[RC-Translator]|r " .. (err or "Could not remove"))
                end
            else
                print("|cFFFF0000[RC-Translator]|r Usage: /rct remove <lang> <english word>")
            end
        end

    elseif cmd == "custom" then
        -- /rct custom [lang] - list custom entries
        local total = T:GetCustomEntryCount()
        if total == 0 then
            print("|cFF00FF00[RC-Translator]|r No custom dictionary entries.")
            print("|cFF888888  Use /rct add <lang> <english> = <translation> to add one.|r")
        else
            local filterLang = (arg and arg ~= "") and arg:lower() or nil
            print("|cFF00FF00===== Custom Dictionary Entries =====|r")
            for langCode, entries in pairs(T.db.customDictionary) do
                if not filterLang or langCode == filterLang then
                    local langName = T.Languages[langCode] and T.Languages[langCode].name or langCode
                    local count = 0
                    for _ in pairs(entries) do count = count + 1 end
                    if count > 0 then
                        print("|cFFFFAA00" .. langName .. " (" .. langCode .. "):|r " .. count .. " entries")
                        for eng, trans in pairs(entries) do
                            print("  |cFFFFFF00" .. eng .. "|r = |cFFFFCC00" .. trans .. "|r")
                        end
                    end
                end
            end
            print("|cFF00FF00Total custom entries: " .. total .. "|r")
        end

    elseif cmd == "profile" then
        if not arg or arg == "" or arg == "list" then
            local profiles = T:GetProfileList()
            print("|cFF00FF00===== RC-Translator Profiles =====|r")
            for _, name in ipairs(profiles) do
                local active = (name == T.profileName) and " |cFF00FF00<< ACTIVE|r" or ""
                print("  |cFFFFFF00" .. name .. "|r" .. active)
            end
            print("|cFF888888Usage: /rct profile switch|create|delete|copy <name>|r")
        else
            local subCmd, subArg = arg:match("^(%S+)%s*(.*)")
            subCmd = subCmd:lower()

            if subCmd == "switch" or subCmd == "use" then
                if subArg and subArg ~= "" then
                    local ok, err = T:SwitchProfile(subArg)
                    if ok then
                        print("|cFF00FF00[RC-Translator]|r Switched to profile: |cFFFFFF00" .. subArg .. "|r")
                    else
                        print("|cFFFF0000[RC-Translator]|r " .. (err or "Failed"))
                    end
                else
                    print("|cFFFF0000[RC-Translator]|r Usage: /rct profile switch <name>")
                end

            elseif subCmd == "create" or subCmd == "new" then
                if subArg and subArg ~= "" then
                    local ok, err = T:CreateProfile(subArg)
                    if ok then
                        print("|cFF00FF00[RC-Translator]|r Created profile: |cFFFFFF00" .. subArg .. "|r")
                    else
                        print("|cFFFF0000[RC-Translator]|r " .. (err or "Failed"))
                    end
                else
                    print("|cFFFF0000[RC-Translator]|r Usage: /rct profile create <name>")
                end

            elseif subCmd == "delete" or subCmd == "del" then
                if subArg and subArg ~= "" then
                    local ok, err = T:DeleteProfile(subArg)
                    if ok then
                        print("|cFF00FF00[RC-Translator]|r Deleted profile: |cFFFFFF00" .. subArg .. "|r")
                    else
                        print("|cFFFF0000[RC-Translator]|r " .. (err or "Failed"))
                    end
                else
                    print("|cFFFF0000[RC-Translator]|r Usage: /rct profile delete <name>")
                end

            elseif subCmd == "copy" then
                local from, to = subArg:match("^(%S+)%s+(%S+)")
                if from and to then
                    local ok, err = T:CopyProfile(from, to)
                    if ok then
                        print("|cFF00FF00[RC-Translator]|r Copied profile |cFFFFFF00" .. from .. "|r → |cFFFFFF00" .. to .. "|r")
                    else
                        print("|cFFFF0000[RC-Translator]|r " .. (err or "Failed"))
                    end
                else
                    print("|cFFFF0000[RC-Translator]|r Usage: /rct profile copy <source> <target>")
                end
            else
                print("|cFF00FF00[RC-Translator]|r Profile commands:")
                print("  |cFFFFFF00/rct profile|r - List profiles")
                print("  |cFFFFFF00/rct profile switch <name>|r - Switch active profile")
                print("  |cFFFFFF00/rct profile create <name>|r - Create new profile")
                print("  |cFFFFFF00/rct profile delete <name>|r - Delete a profile")
                print("  |cFFFFFF00/rct profile copy <from> <to>|r - Copy a profile")
            end
        end

    elseif cmd == "share" then
        if not arg or arg == "" then
            print("|cFF00FF00[RC-Translator]|r Share commands:")
            print("  |cFFFFFF00/rct share <lang> <player>|r - Whisper custom dict to a player")
            print("  |cFFFFFF00/rct share <lang> party|r - Share with party")
            print("  |cFFFFFF00/rct share <lang> raid|r - Share with raid")
            print("  |cFFFFFF00/rct share <lang> guild|r - Share with guild")
            print("|cFF888888  Example: /rct share es Playerone|r")
        else
            local langCode, target = arg:match("^(%S+)%s+(.+)")
            if langCode and target then
                langCode = langCode:lower()
                local channel, whisperTarget
                local tLower = target:lower()
                if tLower == "party" then
                    channel = "PARTY"
                elseif tLower == "raid" then
                    channel = "RAID"
                elseif tLower == "guild" then
                    channel = "GUILD"
                else
                    channel = "WHISPER"
                    whisperTarget = target
                end
                local ok, err = T:ShareDictionary(langCode, channel, whisperTarget)
                if not ok then
                    print("|cFFFF0000[RC-Translator]|r " .. (err or "Failed to share"))
                end
            else
                print("|cFFFF0000[RC-Translator]|r Usage: /rct share <lang> <player|party|raid|guild>")
            end
        end

    else
        print("|cFFFF0000[RC-Translator]|r Unknown command: " .. cmd)
        T:PrintHelp()
    end
end

-- ============================================================
-- INFO & HELP DISPLAY
-- ============================================================

function T:PrintWelcome()
    local langCount, loadedCount, totalWords = 0, 0, 0
    for _, langData in pairs(self.Languages) do
        langCount = langCount + 1
        if langData.loaded and langData.dictionary then
            loadedCount = loadedCount + 1
            totalWords = totalWords + langData.wordCount
        end
    end
    local profileInfo = T.profileName and (" | Profile: |cFFFFFF00" .. T.profileName .. "|r") or ""
    print("|cFF00FF00[RC-Translator]|r v" .. self.version .. " loaded! " .. langCount
        .. " languages available, " .. loadedCount .. " in memory ("
        .. totalWords .. " words)." .. profileInfo)
    print("|cFF00FF00[RC-Translator]|r Type |cFFFFFF00/rct help|r for commands.")
end

function T:PrintHelp()
    print("|cFF00FF00===== RC-Translator Commands =====|r")
    print("|cFFFFFF00/rct on|off|r - Enable/disable the addon")
    print("|cFFFFFF00/rct lang <code>|r - Set target language (e.g., es, pt, fr, de, ja, tl)")
    print("|cFFFFFF00/rct auto|r - Toggle auto-translate foreign messages to English")
    print("|cFFFFFF00/rct last [n]|r - Translate last N received messages (default 1)")
    print("|cFFFFFF00/rct t <text>|r - Translate typed text to target language")
    print("|cFFFFFF00/rct detect <text>|r - Detect the language of text (shows method + confidence)")
    print("|cFFFFFF00/rct im|r - Toggle the translation chat window")
    print("|cFFFFFF00/rct ignore <word>|r - Add word to ignore list (skip in detection)")
    print("|cFFFFFF00/rct ignore remove/list/clear|r - Manage ignore list")
    print("|cFFFFFF00/rct add <lang> <english> = <translation>|r - Add custom dictionary entry")
    print("|cFFFFFF00/rct remove <lang> <english>|r - Remove custom entry")
    print("|cFFFFFF00/rct custom [lang]|r - List custom entries")
    print("|cFFFFFF00/rct profile|r - List/manage profiles")
    print("|cFFFFFF00/rct profile switch|create|delete|copy|r")
    print("|cFFFFFF00/rct share <lang> <player|party|raid|guild>|r - Share custom dict")
    print("|cFFFFFF00/rct stats|r - Show dictionary statistics")
    print("|cFFFFFF00/rct config|r - Open options panel")
    print("|cFFFF00FF/rct secret|r - Open secret language unlock panel")
    print("|cFF00FF00================================|r")
end

function T:PrintLanguages()
    print("|cFF00FF00===== Available Languages =====|r")
    for code, langData in pairs(self.Languages) do
        if self:IsLanguageVisible(code) then
            local active = (code == self.db.targetLang) and " |cFFFFFF00<< ACTIVE|r" or ""
            local size = (code == "en") and "|cFFAAAAAAbase language|r"
                or (self:IsLanguageLoaded(code)
                    and string.format("%d words", langData.wordCount)
                    or "|cFF888888not loaded|r")
            print(string.format("  |cFFFFFF00%s|r - %s (%s)%s", code, langData.name, size, active))
        end
    end
    print("|cFF00FF00Usage:|r /rct lang <code>")
end

function T:PrintStats()
    print("|cFF00FF00===== RC-Translator Stats =====|r")
    print("  Profile: |cFFFFFF00" .. (T.profileName or "Default") .. "|r")
    print("  Status: " .. (self.db.enabled and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
    print("  Target Language: " .. (self.Languages[self.db.targetLang] and self.Languages[self.db.targetLang].name or "Unknown"))
    print("  Auto-Translate: " .. (self.db.autoTranslate and "ON" or "OFF"))
    print("  Messages Buffered: " .. #self.recentMessages)
    print("  Custom Entries: " .. self:GetCustomEntryCount())
    print("|cFF00FF00  --- Dictionaries ---|r")
    for code, langData in pairs(self.Languages) do
        if self:IsLanguageVisible(code) and self:IsLanguageLoaded(code) then
            print(string.format("  %s (%s): %d words", langData.name, code, langData.wordCount))
        end
    end
    print("|cFF888888  (unloaded dictionaries are not counted -- /rct lang <code> loads one)|r")
end

-- ============================================================
-- OPTIONS UI TOGGLE (overridden in UI.lua)
-- ============================================================

function T:ToggleOptionsUI()
    if T.OptionsFrame then
        if T.OptionsFrame:IsShown() then
            T.OptionsFrame:Hide()
        else
            T.OptionsFrame:Show()
        end
    else
        print("|cFF00FF00[RC-Translator]|r Options UI not yet loaded.")
    end
end
