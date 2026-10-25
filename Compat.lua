--[[
    RC-Translator: Compatibility Shim
    Normalises API differences across all WoW versions:
        Classic Era  (1.x  – Interface 11xxx)
        TBC Classic  (2.x  – Interface 20xxx)
        WotLK        (3.x  – Interface 30xxx)
        Cataclysm    (4.x  – Interface 40xxx)
        MoP Classic  (5.x  – Interface 50xxx)
        Retail       (11x  – Interface 110xxx+)
        Forever      (1.60 – Interface 16001; Classic-lineage, Mainline API → Retail)

    Load this file BEFORE Core.lua and UI.lua.
]]

-- ── Version detection ────────────────────────────────────────────────────────
local buildVersion = select(4, GetBuildInfo())  -- numeric interface version e.g. 50400

RCT_Compat = {}
local C = RCT_Compat

-- WoW: Forever is a Classic-lineage client (1.60.x, Interface 16001 in the 2026 beta)
-- that runs the RETAIL / Mainline UI + API, NOT the Classic-Era API. Its interface
-- number falls inside the Classic-Era band (11000-19999), so without special handling
-- it would be misdetected as Classic Era and run the wrong code path (instance chat
-- disabled, Retail branches skipped). Detect it explicitly and treat it as Retail-
-- flavored. Primary signal is a Mainline-only frame (Edit Mode / C_Traits, added in
-- Dragonflight and absent from every Classic flavor) paired with a sub-Retail interface
-- number -- that combination is unique to Forever and survives Blizzard renumbering the
-- interface at the Nov 2026 launch. The 16xxx-19xxx range is a secondary fallback.
local hasMainlineUI = (EditModeManagerFrame ~= nil) or (C_Traits ~= nil)
C.isForever = (hasMainlineUI and buildVersion >= 16000 and buildVersion < 100000)
              or (buildVersion >= 16000 and buildVersion < 20000)

C.isClassicEra = (buildVersion >= 11000  and buildVersion < 16000) and not C.isForever
C.isTBC        = (buildVersion >= 20000  and buildVersion < 30000)
C.isWrath      = (buildVersion >= 30000  and buildVersion < 40000)
C.isCata       = (buildVersion >= 40000  and buildVersion < 50000)
C.isMoP        = (buildVersion >= 50000  and buildVersion < 60000)
C.isRetail     = (buildVersion >= 100000) or C.isForever

-- Anything older than Cata lacks INSTANCE_CHAT (LFD introduced in WotLK 3.3).
-- Forever has it (Mainline architecture), and is excluded from isClassicEra above.
C.hasInstanceChat = not C.isClassicEra and not C.isTBC

-- Retail and WoW Forever can hand addons "secret" values (chat text in
-- instances during combat, for example): they can be displayed but not read,
-- compared or searched. Always false on clients without them.
function C.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

-- ── C_Timer polyfill ─────────────────────────────────────────────────────────
-- C_Timer exists in all supported clients (Classic got it ~2019), but guard anyway.
if not C_Timer then
    C_Timer = {}
    C_Timer.After = function(delay, fn)
        local f = CreateFrame("Frame")
        local elapsed = 0
        f:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= delay then
                self:SetScript("OnUpdate", nil)
                fn()
            end
        end)
    end
    C_Timer.NewTicker = function(interval, fn, iterations)
        local f     = CreateFrame("Frame")
        local acc   = 0
        local count = 0
        local ticker = { cancelled = false }
        function ticker:Cancel() self.cancelled = true f:SetScript("OnUpdate", nil) end
        f:SetScript("OnUpdate", function(self, dt)
            if ticker.cancelled then return end
            acc = acc + dt
            if acc >= interval then
                acc = acc - interval
                count = count + 1
                fn()
                if iterations and count >= iterations then ticker:Cancel() end
            end
        end)
        return ticker
    end
end

-- ── Backdrop helper ──────────────────────────────────────────────────────────
-- Shadowlands (9.0) moved SetBackdrop into a Mixin. Older clients have it natively.
-- Usage: RCT_Compat.SetBackdrop(frame, backdropTable)
function C.SetBackdrop(frame, backdrop)
    if frame.SetBackdrop then
        -- Classic / older retail: method exists directly on the frame
        frame:SetBackdrop(backdrop)
    else
        -- Modern retail: requires the BackdropTemplate mixin
        -- If the frame was created with "BackdropTemplate" this already works.
        -- If not, graft the mixin on at runtime.
        if not frame.SetBackdropColor then
            Mixin(frame, BackdropTemplateMixin)
        end
        frame:SetBackdrop(backdrop)
    end
end

-- Convenience: apply the standard dialog backdrop to any frame
function C.ApplyDialogBackdrop(frame)
    C.SetBackdrop(frame, {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
end

-- ── CreateFrame with BackdropTemplate ────────────────────────────────────────
-- Classic clients don't know "BackdropTemplate" as a registered template,
-- so we strip it and apply the mixin manually.
local _CreateFrame = CreateFrame
function C.CreateFrameWithBackdrop(name, parent)
    -- Try the modern way first. Capture the frame directly rather than fishing it
    -- back out of _G -- an anonymous frame has no global, so the old code silently
    -- created a SECOND frame and leaked the first.
    local ok, frame = pcall(_CreateFrame, "Frame", name, parent, "BackdropTemplate")
    if ok and frame then return frame end

    -- Fallback: plain frame + manual mixin
    local f = _CreateFrame("Frame", name, parent)
    if BackdropTemplateMixin and Mixin then
        Mixin(f, BackdropTemplateMixin)
    end
    return f
end

-- ── PlaySound compatibility ───────────────────────────────────────────────────
-- Sound IDs differ by version; use file paths that work everywhere.
C.SOUND_LEVELUP  = "Sound\\Interface\\LevelUp.ogg"
C.SOUND_COMPLETE = "Sound\\Interface\\iQuestComplete.ogg"
C.SOUND_CLICK    = "Sound\\Interface\\uiButtonClick.ogg"

function C.PlaySoundSafe(soundId, fallbackFile)
    -- soundId is a numeric kitID (retail). On classic, use file path instead.
    if C.isRetail or C.isMoP then
        -- soundId is a numeric kitID here, so PlaySound is the correct call.
        if PlaySound then
            PlaySound(soundId)
        elseif fallbackFile and PlaySoundFile then
            PlaySoundFile(fallbackFile)
        end
    else
        if fallbackFile then
            PlaySoundFile(fallbackFile)
        end
    end
end

-- ── Chat channel availability ────────────────────────────────────────────────
-- Returns only the chat event types valid for this client version.
function C.GetValidChatEvents()
    local events = {
        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
        "CHAT_MSG_WHISPER",
        "CHAT_MSG_CHANNEL",
        "CHAT_MSG_EMOTE",
    }
    -- INSTANCE_CHAT introduced in WotLK 3.3 (LFD)
    if C.hasInstanceChat then
        table.insert(events, "CHAT_MSG_INSTANCE_CHAT")
        table.insert(events, "CHAT_MSG_INSTANCE_CHAT_LEADER")
    end
    return events
end

-- ── Default channel settings ─────────────────────────────────────────────────
function C.GetDefaultChannelSettings()
    local ch = {
        SAY            = true,
        YELL           = true,
        PARTY          = true,
        PARTY_LEADER   = true,
        RAID           = true,
        RAID_LEADER    = true,
        GUILD          = true,
        OFFICER        = true,
        WHISPER        = true,
        CHANNEL        = true,
        EMOTE          = false,
    }
    if C.hasInstanceChat then
        ch.INSTANCE_CHAT        = true
        ch.INSTANCE_CHAT_LEADER = true
    end
    return ch
end

-- ── UnitName helper ───────────────────────────────────────────────────────────
-- Retail UnitName returns name, realm. Classic returns just name.
function C.GetPlayerName()
    local name = UnitName("player")
    return name or "Unknown"
end

-- ============================================================
-- ADDON LOADING (LoadOnDemand support)
-- Retail 10.x+ moved these into the C_AddOns namespace.
-- ============================================================

RCT_LoadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
RCT_IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

-- ── Addon comms ──────────────────────────────────────────────────────────────
-- Patch 8.0 moved SendAddonMessage / RegisterAddonMessagePrefix into C_ChatInfo
-- and removed the globals. Calling the bare global errors on every modern client.
function C.SendAddonMessage(prefix, message, chatType, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return C_ChatInfo.SendAddonMessage(prefix, message, chatType, target)
    elseif SendAddonMessage then
        return SendAddonMessage(prefix, message, chatType, target)
    end
end

function C.RegisterAddonMessagePrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        return C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    elseif RegisterAddonMessagePrefix then
        return RegisterAddonMessagePrefix(prefix)
    end
end
