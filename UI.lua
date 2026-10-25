--[[
    RC-Translator: UI Module
    - Minimap button (supports both round AND square minimaps)
    - IM-style translation chat window (anchored above Blizzard chat)
    - Full options/settings panel
]]

local T = RC_Translator
local ADDON_NAME = "RC-Translator"

-- ============================================================
-- MINIMAP BUTTON (Round + Square Minimap Support)
-- ============================================================

function T:CreateMinimapButton()
    if self.MinimapButton then return end

    if not self.db.minimap then
        self.db.minimap = {
            position = 220,
            hide = false,
            locked = false,
        }
    end

    -- Utility: clamp angle to [0, 360)
    local function NormalizeAngle(angle)
        angle = angle % 360
        if angle < 0 then angle = angle + 360 end
        return angle
    end

    -- Calculate position on minimap edge (same math as RCSpellFlash)
    local function GetMinimapButtonPosition(angle)
        local size = Minimap:GetWidth() / 2 - 10
        local rad = math.rad(angle)
        local x = math.cos(rad)
        local y = math.sin(rad)
        local absX, absY = math.abs(x), math.abs(y)
        local edge = size / math.max(absX, absY)
        return x * edge, y * edge
    end

    -- Create button frame
    local btn = CreateFrame("Button", "RCT_MinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetMovable(true)

    -- Icon (scroll/note — fits a translator addon)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_06")
    icon:SetSize(28, 28)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.icon = icon

    -- Square border (Blizzard quickslot style — same as RCSpellFlash)
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetSize(40, 40)
    border:SetPoint("CENTER", btn, "CENTER", 0, 0)
    border:SetAlpha(1)
    btn.border = border

    -- ---- Position update ----
    local function UpdatePosition()
        local angle = T.db.minimap.position or 220
        local x, y = GetMinimapButtonPosition(angle)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    -- ---- OnUpdate handler (dragging) ----
    local function MinimapButtonOnUpdate(self, elapsed)
        if self.isDragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx = cx / scale
            cy = cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            T.db.minimap.position = NormalizeAngle(angle)
            UpdatePosition()
        end
    end

    -- ---- Dragging ----
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnDragStart", function(self)
        if T.db.minimap.locked then return end
        self.isDragging = true
        btn:SetScript("OnUpdate", MinimapButtonOnUpdate)
    end)

    btn:SetScript("OnDragStop", function(self)
        self.isDragging = false
        -- Snap to minimap edge
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx = cx / scale
        cy = cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        T.db.minimap.position = NormalizeAngle(angle)
        UpdatePosition()
        btn:SetScript("OnUpdate", nil)
    end)

    -- ---- Click handlers ----
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and not self.isDragging then
            T:ToggleOptionsUI()
        elseif button == "RightButton" then
            T.db.autoTranslate = not T.db.autoTranslate
            local state = T.db.autoTranslate and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
            print("|cFF00FF00[RC-Translator]|r Auto-translate: " .. state)
            if T.db.autoTranslate then
                btn.icon:SetVertexColor(0.3, 1.0, 0.3)
            else
                btn.icon:SetVertexColor(1, 1, 1)
            end
        end
    end)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- ---- Tooltip ----
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cFF00FF00RC-Translator|r v" .. T.version)
        GameTooltip:AddLine(" ")

        local status = T.db.enabled and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"
        GameTooltip:AddDoubleLine("Status:", status)

        local langName = T.Languages[T.db.targetLang] and T.Languages[T.db.targetLang].name or "Unknown"
        GameTooltip:AddDoubleLine("Target Language:", "|cFFFFFF00" .. langName .. "|r")

        local autoState = T.db.autoTranslate and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
        GameTooltip:AddDoubleLine("Auto-Translate:", autoState)

        local langCount, totalWords = 0, 0
        for code, langData in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then
                langCount = langCount + 1
                totalWords = totalWords + langData.wordCount
            end
        end
        GameTooltip:AddDoubleLine("Dictionaries:", "|cFFFFFF00" .. langCount .. "|r (" .. totalWords .. " words)")

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFAAAAFFLeft-Click:|r Open settings")
        GameTooltip:AddLine("|cFFAAAAFFRight-Click:|r Toggle auto-translate")
        GameTooltip:AddLine("|cFFAAAAFFDrag:|r Reposition button")
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Initial state
    if T.db.autoTranslate then
        btn.icon:SetVertexColor(0.3, 1.0, 0.3)
    end

    UpdatePosition()

    if T.db.minimap.hide then btn:Hide() else btn:Show() end

    self.MinimapButton = btn
    self.UpdateMinimapPosition = UpdatePosition
end

-- ============================================================
-- IM-STYLE TRANSLATION CHAT WINDOW
-- (Anchored ABOVE Blizzard's default chat frame)
-- ============================================================

function T:CreateIMWindow()
    if self.IMFrame then return end

    local f = CreateFrame("Frame", "RCT_IMWindow", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(500, 440)
    f:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 30)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:SetResizable(true)
    f:Hide()

    if f.SetMinResize then
        f:SetMinResize(380, 320)
        f:SetMaxResize(800, 700)
    elseif f.SetResizeBounds then
        f:SetResizeBounds(380, 320, 800, 700)
    end

    local resizeGrip = CreateFrame("Button", nil, f)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizeGrip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.title:SetPoint("TOP", f.TitleBg, "TOP", 0, -3)
    f.title:SetText("|cFF00FF00RC-Translator|r")

    -- Clear button in title bar
    local clearBtn = CreateFrame("Button", "RCT_IM_Clear", f, "UIPanelButtonTemplate")
    clearBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -1)
    clearBtn:SetSize(50, 20)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        f.incomingMessages = {}
        f.outgoingMessages = {}
        f.outgoingTranslations = {}
        f.outgoingCounter = 0
        T:IMRefreshIncoming()
        if f.outMsg then f.outMsg:Clear() end
    end)

    -- ================================================================
    -- TOP PANE: Incoming Translations (foreign → target)
    -- ================================================================
    local inLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    inLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -28)
    inLabel:SetText("|cFF00CCFF▼ Incoming|r")

    -- Incoming source language picker (FROM)
    local inSrcPicker = CreateFrame("Frame", "RCT_IM_InSrcPicker", f, "UIDropDownMenuTemplate")
    inSrcPicker:SetPoint("LEFT", inLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(inSrcPicker, 85)
    f.inSrcPicker = inSrcPicker

    local function InSrcPicker_SetDisplay()
        if T.db.incomingSourceLang == "auto" then
            UIDropDownMenu_SetText(inSrcPicker, "|cFF00FF00Auto|r")
        else
            local name = T.Languages[T.db.incomingSourceLang] and T.Languages[T.db.incomingSourceLang].name or T.db.incomingSourceLang
            UIDropDownMenu_SetText(inSrcPicker, name)
        end
    end

    UIDropDownMenu_Initialize(inSrcPicker, function(self, level)
        local autoInfo = UIDropDownMenu_CreateInfo()
        autoInfo.text = "|cFF00FF00Auto-detect|r"
        autoInfo.value = "auto"
        autoInfo.checked = (T.db.incomingSourceLang == "auto")
        autoInfo.func = function(btn)
            T.db.incomingSourceLang = "auto"
            InSrcPicker_SetDisplay()
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(autoInfo, level)

        local sorted = {}
        for code, langData in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then
                table.insert(sorted, { code = code, name = langData.name })
            end
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        for _, entry in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.name .. "  |cFF888888(" .. entry.code .. ")|r"
            info.value = entry.code
            info.checked = (T.db.incomingSourceLang == entry.code)
            info.func = function(btn)
                T:EnableLanguage(btn.value)
                T.db.incomingSourceLang = btn.value
                InSrcPicker_SetDisplay()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    InSrcPicker_SetDisplay()

    -- Arrow between incoming pickers
    local inArrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    inArrow:SetPoint("LEFT", inSrcPicker, "RIGHT", -12, 2)
    inArrow:SetText("|cFF888888→|r")

    -- Incoming target language picker (TO)
    local inTgtPicker = CreateFrame("Frame", "RCT_IM_InTgtPicker", f, "UIDropDownMenuTemplate")
    inTgtPicker:SetPoint("LEFT", inArrow, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(inTgtPicker, 85)
    f.inTgtPicker = inTgtPicker

    local function InTgtPicker_SetDisplay()
        local code = T.db.incomingTargetLang
        local name = T.Languages[code] and T.Languages[code].name or code
        UIDropDownMenu_SetText(inTgtPicker, name)
    end

    UIDropDownMenu_Initialize(inTgtPicker, function(self, level)
        local sorted = {}
        for code, langData in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then
                table.insert(sorted, { code = code, name = langData.name })
            end
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        for _, entry in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.name .. "  |cFF888888(" .. entry.code .. ")|r"
            info.value = entry.code
            info.checked = (T.db.incomingTargetLang == entry.code)
            info.func = function(btn)
                T:EnableLanguage(btn.value)
                T.db.incomingTargetLang = btn.value
                InTgtPicker_SetDisplay()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    InTgtPicker_SetDisplay()

    -- Incoming display: a ScrollingMessageFrame (same robust widget as the
    -- outgoing pane). The previous multi-line EditBox could clear itself / lock
    -- up when the text grew or gained focus.
    local inMsg = CreateFrame("ScrollingMessageFrame", "RCT_IM_InMsg", f)
    inMsg:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -44)
    inMsg:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    inMsg:SetHeight(140)
    inMsg:SetFontObject(ChatFontNormal)
    inMsg:SetJustifyH("LEFT")
    inMsg:SetFading(false)
    inMsg:SetMaxLines(400)
    inMsg:SetHyperlinksEnabled(false)
    inMsg:EnableMouseWheel(true)
    inMsg:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)

    f.inMsg = inMsg
    f.incomingMessages = {}

    -- ================================================================
    -- DIVIDER
    -- ================================================================
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetTexture(1,1,1,1) divider:SetVertexColor(0.4, 0.4, 0.4, 0.8)
    divider:SetPoint("LEFT", f, "LEFT", 10, 0)
    divider:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    divider:SetPoint("TOP", inMsg, "BOTTOM", 0, -2)

    -- ================================================================
    -- BOTTOM PANE: Outgoing Translations (type → target language)
    -- Uses ScrollingMessageFrame so hyperlinks ([T]) are clickable.
    -- ================================================================
    local outLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    outLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 2, -4)
    f.outLabel = outLabel

    -- Source language picker (FROM)
    local srcPicker = CreateFrame("Frame", "RCT_IM_SrcPicker", f, "UIDropDownMenuTemplate")
    srcPicker:SetPoint("LEFT", outLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(srcPicker, 95)
    f.srcPicker = srcPicker

    local function SrcPicker_SetDisplay()
        if T.db.sourceLang == "auto" then
            UIDropDownMenu_SetText(srcPicker, "|cFF00FF00Auto|r")
        else
            local name = T.Languages[T.db.sourceLang] and T.Languages[T.db.sourceLang].name or T.db.sourceLang
            UIDropDownMenu_SetText(srcPicker, name)
        end
    end

    UIDropDownMenu_Initialize(srcPicker, function(self, level)
        -- Auto-detect option
        local autoInfo = UIDropDownMenu_CreateInfo()
        autoInfo.text = "|cFF00FF00Auto-detect|r"
        autoInfo.value = "auto"
        autoInfo.checked = (T.db.sourceLang == "auto")
        autoInfo.func = function(btn)
            T.db.sourceLang = "auto"
            SrcPicker_SetDisplay()
            T:IMUpdateOutLabel()
            -- Sync settings panel
            local optSrc = _G["RCT_SrcLangDropdown"]
            if optSrc then UIDropDownMenu_SetText(optSrc, "|cFF00FF00Auto-detect|r") end
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(autoInfo, level)

        local sorted = {}
        for code, langData in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then
                table.insert(sorted, { code = code, name = langData.name })
            end
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)

        for _, entry in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.name .. "  |cFF888888(" .. entry.code .. ")|r"
            info.value = entry.code
            info.checked = (T.db.sourceLang == entry.code)
            info.func = function(btn)
                T:EnableLanguage(btn.value)
                T.db.sourceLang = btn.value
                SrcPicker_SetDisplay()
                T:IMUpdateOutLabel()
                local optSrc = _G["RCT_SrcLangDropdown"]
                if optSrc then UIDropDownMenu_SetText(optSrc, T.Languages[btn.value].name .. " (" .. btn.value .. ")") end
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    SrcPicker_SetDisplay()

    -- Arrow label between pickers
    local arrowLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrowLabel:SetPoint("LEFT", srcPicker, "RIGHT", -12, 2)
    arrowLabel:SetText("|cFF888888→|r")

    -- Target language picker (TO)
    local langPicker = CreateFrame("Frame", "RCT_IM_LangPicker", f, "UIDropDownMenuTemplate")
    langPicker:SetPoint("LEFT", arrowLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(langPicker, 95)

    local function LangPicker_SetDisplay()
        local code = T.db.targetLang
        local name = T.Languages[code] and T.Languages[code].name or code
        UIDropDownMenu_SetText(langPicker, name)
    end

    UIDropDownMenu_Initialize(langPicker, function(self, level)
        -- Build sorted list of loaded languages
        local sorted = {}
        for code, langData in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then
                table.insert(sorted, { code = code, name = langData.name })
            end
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)

        for _, entry in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.name .. "  |cFF888888(" .. entry.code .. ")|r"
            info.value = entry.code
            info.checked = (T.db.targetLang == entry.code)
            info.func = function(btn)
                T:EnableLanguage(btn.value)
                T.db.targetLang = btn.value
                LangPicker_SetDisplay()
                T:IMUpdateOutLabel()
                -- Also update the options panel dropdown if it exists
                if T.OptionsFrame then
                    local optDrop = _G["RCT_LangDropdown"]
                    if optDrop then
                        UIDropDownMenu_SetText(optDrop, T.Languages[btn.value].name .. " (" .. btn.value .. ")")
                    end
                end
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    LangPicker_SetDisplay()
    f.langPicker = langPicker

    local outMsg = CreateFrame("ScrollingMessageFrame", "RCT_IM_OutMsg", f)
    outMsg:SetPoint("TOPLEFT", outLabel, "BOTTOMLEFT", -2, -24)
    outMsg:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    outMsg:SetPoint("BOTTOM", f, "BOTTOM", 0, 55)
    outMsg:SetFontObject(ChatFontNormal)
    outMsg:SetJustifyH("LEFT")
    outMsg:SetFading(false)
    outMsg:SetMaxLines(200)
    outMsg:SetHyperlinksEnabled(true)
    outMsg:EnableMouseWheel(true)
    outMsg:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)

    -- Handle [T] clicks in the outgoing pane → copy translated text to Blizzard chat input
    outMsg:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local outId = link:match("^rctsend:(%d+)")
        if outId then
            outId = tonumber(outId)
            local stored = f.outgoingTranslations and f.outgoingTranslations[outId]
            if stored then
                -- Open Blizzard's chat edit box and insert the translated text
                local editBox = ChatFrame1EditBox or _G["ChatFrame1EditBox"]
                if editBox then
                    if not editBox:IsShown() then
                        ChatFrame_OpenChat("")
                    end
                    editBox:SetText(stored)
                    editBox:SetFocus()
                end
            end
        end
    end)

    f.outMsg = outMsg
    f.outgoingMessages = {}
    f.outgoingTranslations = {}  -- [id] = translated text, for [T] click lookup
    f.outgoingCounter = 0

    -- ================================================================
    -- INPUT BAR (bottom of frame — type here to translate outgoing)
    -- ================================================================
    local inputBg = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
    inputBg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    inputBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    inputBg:SetHeight(40)

    local inputBox = CreateFrame("EditBox", "RCT_IM_Input", inputBg, "InputBoxTemplate")
    inputBox:SetPoint("LEFT", inputBg, "LEFT", 10, 0)
    inputBox:SetPoint("RIGHT", inputBg, "RIGHT", -80, 0)
    inputBox:SetHeight(20)
    inputBox:SetAutoFocus(false)
    inputBox:SetMaxLetters(256)

    local sendBtn = CreateFrame("Button", "RCT_IM_Send", inputBg, "UIPanelButtonTemplate")
    sendBtn:SetPoint("RIGHT", inputBg, "RIGHT", -6, 0)
    sendBtn:SetSize(68, 26)
    sendBtn:SetText("Translate")

    sendBtn:SetScript("OnClick", function()
        local text = inputBox:GetText()
        if text and text ~= "" then
            T:IMTranslateOutgoing(text)
            inputBox:SetText("")
            inputBox:ClearFocus()
        end
    end)

    inputBox:SetScript("OnEnterPressed", function(self)
        sendBtn:Click()
    end)

    f.inputBox = inputBox

    tinsert(UISpecialFrames, "RCT_IMWindow")
    self.IMFrame = f

    -- Update outgoing label with current language settings
    T:IMUpdateOutLabel()
end

--- Update the outgoing pane label to reflect current target language
function T:IMUpdateOutLabel()
    if not self.IMFrame or not self.IMFrame.outLabel then return end
    local srcName = "Auto"
    if self.db.sourceLang ~= "auto" then
        srcName = self.Languages[self.db.sourceLang] and self.Languages[self.db.sourceLang].name or self.db.sourceLang
    end
    local targetName = self.Languages[self.db.targetLang] and self.Languages[self.db.targetLang].name or self.db.targetLang
    self.IMFrame.outLabel:SetText("|cFF00FF80▲ Translate|r")
    -- Sync outgoing source picker display
    if self.IMFrame.srcPicker then
        if self.db.sourceLang == "auto" then
            UIDropDownMenu_SetText(self.IMFrame.srcPicker, "|cFF00FF00Auto|r")
        else
            UIDropDownMenu_SetText(self.IMFrame.srcPicker, srcName)
        end
    end
    -- Sync outgoing target picker display
    if self.IMFrame.langPicker then
        UIDropDownMenu_SetText(self.IMFrame.langPicker, targetName)
    end
    -- Sync incoming pickers
    if self.IMFrame.inSrcPicker then
        if self.db.incomingSourceLang == "auto" then
            UIDropDownMenu_SetText(self.IMFrame.inSrcPicker, "|cFF00FF00Auto|r")
        else
            local inSrcName = self.Languages[self.db.incomingSourceLang] and self.Languages[self.db.incomingSourceLang].name or self.db.incomingSourceLang
            UIDropDownMenu_SetText(self.IMFrame.inSrcPicker, inSrcName)
        end
    end
    if self.IMFrame.inTgtPicker then
        local inTgtName = self.Languages[self.db.incomingTargetLang] and self.Languages[self.db.incomingTargetLang].name or self.db.incomingTargetLang
        UIDropDownMenu_SetText(self.IMFrame.inTgtPicker, inTgtName)
    end
end

--- Add an incoming translation (from clicking [T] — foreign → English)
function T:IMAddIncoming(sender, original, translated, fromLang, toLang, confidence, method)
    if not self.IMFrame then self:CreateIMWindow() end

    local timestamp = date("%H:%M:%S")
    table.insert(self.IMFrame.incomingMessages, {
        timestamp = timestamp,
        sender = sender or "Unknown",
        original = original,
        translated = translated,
        fromLang = fromLang or "?",
        toLang = toLang or "?",
        confidence = confidence and (math.floor(confidence * 100) .. "%") or "",
        method = method or "",
    })
    while #self.IMFrame.incomingMessages > 100 do
        table.remove(self.IMFrame.incomingMessages, 1)
    end
    self:IMRefreshIncoming()
end

--- Add an outgoing translation (typed by user → target language)
--- Displays in ScrollingMessageFrame with clickable [T] to send to Blizzard chat.
function T:IMAddOutgoing(original, translated, toLang)
    if not self.IMFrame then self:CreateIMWindow() end

    local f = self.IMFrame
    f.outgoingCounter = (f.outgoingCounter or 0) + 1
    local id = f.outgoingCounter

    -- Store translated text so [T] click can retrieve it
    f.outgoingTranslations[id] = translated

    local timestamp = date("%H:%M:%S")
    local sendLink = string.format("|cFF00CCFF|Hrctsend:%d|h[T]|h|r", id)

    f.outMsg:AddMessage(string.format("|cFF888888[%s]|r |cFF666666(→ %s)|r", timestamp, toLang))
    f.outMsg:AddMessage("  |cFFCCCCCC" .. original .. "|r")
    f.outMsg:AddMessage("  |cFFFFCC00" .. translated .. "|r  " .. sendLink)
    f.outMsg:AddMessage(" ")
end

--- Refresh the incoming pane
function T:IMRefreshIncoming()
    if not self.IMFrame or not self.IMFrame.inMsg then return end
    local m = self.IMFrame.inMsg
    m:Clear()
    for _, msg in ipairs(self.IMFrame.incomingMessages) do
        m:AddMessage(string.format("|cFF888888[%s]|r |cFFAAAAFF%s|r |cFF666666(%s → %s)|r",
            msg.timestamp, msg.sender, msg.fromLang, msg.toLang))
        m:AddMessage("  |cFFCCCCCC" .. msg.original .. "|r")
        m:AddMessage("  |cFF80FF80" .. msg.translated .. "|r")
        if msg.confidence ~= "" and T.db.showDetectionInfo then
            m:AddMessage(string.format("  |cFF555555[%s confidence, %s]|r", msg.confidence, msg.method))
        end
        m:AddMessage(" ")
    end
    if m.ScrollToBottom then m:ScrollToBottom() end
end

--- Translate text typed in the input bar (resolves source language → target language)
function T:IMTranslateOutgoing(text)
    if not text or text == "" then return end
    local targetLang = self.db.targetLang
    local targetName = self.Languages[targetLang] and self.Languages[targetLang].name or targetLang

    -- Resolve source language (auto-detect or manual)
    local detectedLang, confidence = self:ResolveSourceLang(text)
    local fromLang = detectedLang or "en"
    
    -- Don't translate if source matches target
    if fromLang == targetLang then
        self:IMAddOutgoing(text, "(already in target language)", targetName)
        return
    end

    local result, wt, tw = self:Translate(text, fromLang, targetLang)
    if wt and wt > 0 then
        self:IMAddOutgoing(text, result, targetName)
    else
        self:IMAddOutgoing(text, "(no translation available)", targetName)
    end
end

function T:ShowIMWindow()
    if not self.IMFrame then
        self:CreateIMWindow()
    end
    self.IMFrame:Show()
end

function T:ToggleIMWindow()
    if not self.IMFrame then
        self:CreateIMWindow()
    end
    if self.IMFrame:IsShown() then
        self.IMFrame:Hide()
    else
        self.IMFrame:Show()
    end
end

-- ============================================================
-- HOOK: [T] CLICK -> IM WINDOW (always)
-- ============================================================

function T:TranslateToIM(msgData, targetLang)
    if not msgData then return end
    -- Use incoming pane settings unless explicitly overridden
    targetLang = targetLang or self.db.incomingTargetLang or self.db.targetLang or "en"

    -- Resolve source language using incoming-specific setting
    local detectedLang, confidence, method
    if self.db.incomingSourceLang and self.db.incomingSourceLang ~= "auto" then
        detectedLang = self.db.incomingSourceLang
        confidence = 1.0
        method = "manual"
    else
        -- Clicking [T] is an explicit, user-driven action -- the one safe place to
        -- hit the disk. Identify the language with zero dictionaries resident,
        -- then load just that one.
        detectedLang, confidence, method = self:ResolveAndLoad(msgData.text)
    end

    -- The target dictionary has to be resident too (unless it is English).
    if detectedLang and targetLang and targetLang ~= "en" then
        self:EnsureLanguageLoaded(targetLang)
    end

    -- No language detected/set — still show the message but note it
    if not detectedLang or confidence <= 0.15 then
        self:ShowIMWindow()
        self:IMAddIncoming(msgData.sender or "Unknown", msgData.text,
            "(no foreign language detected)", "?", "English", nil, nil)
        return
    end

    -- Don't translate if detected matches target
    if detectedLang == targetLang then
        self:ShowIMWindow()
        local fromName = self.Languages[detectedLang] and self.Languages[detectedLang].name or detectedLang
        self:IMAddIncoming(msgData.sender or "Unknown", msgData.text,
            "(already in target language)", fromName, fromName, confidence, method)
        return
    end

    local fromName = self.Languages[detectedLang] and self.Languages[detectedLang].name or detectedLang
    local toName = targetLang == "en" and "English" or (self.Languages[targetLang] and self.Languages[targetLang].name or targetLang)

    local result, wordsTranslated, totalWords = self:Translate(msgData.text, detectedLang, targetLang)

    self:ShowIMWindow()
    if wordsTranslated and wordsTranslated > 0 then
        self:IMAddIncoming(msgData.sender or "Unknown", msgData.text, result, fromName, toName, confidence, method)
    else
        self:IMAddIncoming(msgData.sender or "Unknown", msgData.text, msgData.text, fromName, toName, confidence, method)
    end
end

-- ============================================================
-- HELPER FUNCTIONS (for Options Panel)
-- ============================================================

local function CreateSectionHeader(parent, text, yOffset, leftPad)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", leftPad, yOffset)
    header:SetText("|cFFFFAA00" .. text .. "|r")

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    line:SetSize(380, 1)
    line:SetTexture(1,1,1,1) line:SetVertexColor(0.5, 0.4, 0.1, 0.6)

    return header, yOffset - 20
end

local function CreateCheckbox(parent, name, text, yOffset, leftPad, dbKey)
    local cb = CreateFrame("CheckButton", "RCT_" .. name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", leftPad, yOffset)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    cb.text:SetText(text)
    cb:SetChecked(T.db[dbKey])
    cb._dbKey = dbKey
    cb:SetScript("OnClick", function(self)
        T.db[dbKey] = self:GetChecked()
    end)
    return cb, yOffset - 26
end

-- ============================================================
-- OPTIONS PANEL
-- ============================================================

function T:CreateOptionsUI()
    if self.OptionsFrame then return end

    local f = CreateFrame("Frame", "RC_TranslatorOptions", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(440, 620)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.title:SetPoint("TOP", f.TitleBg, "TOP", 0, -3)
    f.title:SetText("RC-Translator v" .. T.version)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "RCT_ScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 10)

    local content = CreateFrame("Frame", "RCT_ScrollContent", scrollFrame)
    content:SetSize(390, 1750)
    scrollFrame:SetScrollChild(content)

    local yOffset = -5
    local leftPad = 10

    -- ===================== General Settings =====================
    local _, newY = CreateSectionHeader(content, "General Settings", yOffset, leftPad)
    yOffset = newY

    local enableCB
    enableCB, yOffset = CreateCheckbox(content, "Enable", "Enable RC-Translator", yOffset, leftPad, "enabled")

    local minimapCB = CreateFrame("CheckButton", "RCT_MinimapCB", content, "UICheckButtonTemplate")
    minimapCB:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad, yOffset)
    minimapCB.text = minimapCB:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    minimapCB.text:SetPoint("LEFT", minimapCB, "RIGHT", 5, 0)
    minimapCB.text:SetText("Show minimap button")
    minimapCB:SetChecked(not T.db.minimap.hide)
    minimapCB:SetScript("OnClick", function(self)
        T.db.minimap.hide = not self:GetChecked()
        if T.MinimapButton then
            if T.db.minimap.hide then T.MinimapButton:Hide() else T.MinimapButton:Show() end
        end
    end)
    yOffset = yOffset - 26

    -- Open IM Window button
    local imBtn = CreateFrame("Button", "RCT_OpenIM", content, "UIPanelButtonTemplate")
    imBtn:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    imBtn:SetSize(200, 24)
    imBtn:SetText("Open Translation Chat Window")
    imBtn:SetScript("OnClick", function()
        T:ToggleIMWindow()
    end)
    yOffset = yOffset - 34

    -- ===================== Target Language =====================
    local _, newY = CreateSectionHeader(content, "Translation Languages", yOffset, leftPad)
    yOffset = newY

    -- Source language ("Translate from:")
    local srcLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    srcLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    srcLabel:SetText("Translate from:")

    local srcDropdown = CreateFrame("Frame", "RCT_SrcLangDropdown", content, "UIDropDownMenuTemplate")
    srcDropdown:SetPoint("TOPLEFT", srcLabel, "BOTTOMLEFT", -15, -2)
    f.srcDropdown = srcDropdown

    local function SrcDropdown_Initialize(self, level)
        -- Auto-detect option first
        local autoInfo = UIDropDownMenu_CreateInfo()
        autoInfo.text = "|cFF00FF00Auto-detect|r"
        autoInfo.value = "auto"
        autoInfo.checked = (T.db.sourceLang == "auto")
        autoInfo.func = function(self)
            T.db.sourceLang = "auto"
            UIDropDownMenu_SetText(srcDropdown, "|cFF00FF00Auto-detect|r")
            T:IMUpdateOutLabel()
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(autoInfo, level)

        -- All visible languages
        local sorted = {}
        for code, langData in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then
                table.insert(sorted, { code = code, data = langData })
            end
        end
        table.sort(sorted, function(a, b) return a.data.name < b.data.name end)

        for _, entry in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.data.name .. "  |cFF888888(" .. entry.code .. ")|r"
            info.value = entry.code
            info.checked = (entry.code == T.db.sourceLang)
            info.func = function(self)
                T:EnableLanguage(self.value)
                T.db.sourceLang = self.value
                UIDropDownMenu_SetText(srcDropdown, T.Languages[self.value].name .. " (" .. self.value .. ")")
                T:IMUpdateOutLabel()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_SetWidth(srcDropdown, 280)
    UIDropDownMenu_Initialize(srcDropdown, SrcDropdown_Initialize)
    if T.db.sourceLang == "auto" then
        UIDropDownMenu_SetText(srcDropdown, "|cFF00FF00Auto-detect|r")
    elseif T.Languages[T.db.sourceLang] then
        UIDropDownMenu_SetText(srcDropdown, T.Languages[T.db.sourceLang].name .. " (" .. T.db.sourceLang .. ")")
    end
    yOffset = yOffset - 55

    -- Target language ("Translate to:")
    local langLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    langLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    langLabel:SetText("Translate to:")

    local langDropdown = CreateFrame("Frame", "RCT_LangDropdown", content, "UIDropDownMenuTemplate")
    langDropdown:SetPoint("TOPLEFT", langLabel, "BOTTOMLEFT", -15, -2)
    f.langDropdown = langDropdown

    local function LangDropdown_Initialize(self, level)
        local sorted = {}
        for code, langData in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then
                table.insert(sorted, { code = code, data = langData })
            end
        end
        table.sort(sorted, function(a, b) return a.data.name < b.data.name end)

        for _, entry in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.data.name .. "  |cFF888888(" .. entry.code .. " - " .. T:LangSizeLabel(entry.code) .. ")|r"
            info.value = entry.code
            info.checked = (entry.code == T.db.targetLang)
            info.func = function(self)
                T:EnableLanguage(self.value)
                T.db.targetLang = self.value
                UIDropDownMenu_SetText(langDropdown, T.Languages[self.value].name .. " (" .. self.value .. ")")
                T:IMUpdateOutLabel()  -- sync IM window dropdown + label
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_SetWidth(langDropdown, 280)
    UIDropDownMenu_Initialize(langDropdown, LangDropdown_Initialize)
    if T.Languages[T.db.targetLang] then
        UIDropDownMenu_SetText(langDropdown, T.Languages[T.db.targetLang].name .. " (" .. T.db.targetLang .. ")")
    end
    yOffset = yOffset - 55

    -- ===================== Auto-Detection & Translation =====================
    local _, newY = CreateSectionHeader(content, "Auto-Detection & Translation", yOffset, leftPad)
    yOffset = newY

    local autoCB
    autoCB, yOffset = CreateCheckbox(content, "AutoTranslate", "Auto-translate incoming messages", yOffset, leftPad, "autoTranslate")

    local detectInfoCB
    detectInfoCB, yOffset = CreateCheckbox(content, "DetectInfo", "Show detection method & confidence %", yOffset, leftPad, "showDetectionInfo")

    local origCB
    origCB, yOffset = CreateCheckbox(content, "ShowOrig", "Show original message with translation", yOffset, leftPad, "showOriginal")

    local autoToIMCB
    autoToIMCB, yOffset = CreateCheckbox(content, "AutoToIM", "Send auto-translations to IM window (not chat)", yOffset, leftPad, "autoTranslateToIM")

    -- Translated chat tab (custom OnClick: create/close the tab immediately)
    local transTabCB = CreateFrame("CheckButton", "RCT_TransTab", content, "UICheckButtonTemplate")
    transTabCB:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad, yOffset)
    transTabCB.text = transTabCB:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    transTabCB.text:SetPoint("LEFT", transTabCB, "RIGHT", 5, 0)
    transTabCB.text:SetText("Add a 'Translated' chat tab (whole feed, translated)")
    transTabCB:SetChecked(T.db.translatedTab)
    transTabCB:SetScript("OnClick", function(self)
        T.db.translatedTab = self:GetChecked()
        if T.db.translatedTab then T:EnsureTranslatedTab() else T:RemoveTranslatedTab() end
    end)
    yOffset = yOffset - 26

    -- Per-tab sub-options (indented under the tab toggle)
    local transOrigCB
    transOrigCB, yOffset = CreateCheckbox(content, "TransTabOrig",
        "show original line under each translation", yOffset, leftPad + 20, "translatedTabShowOriginal")
    local transOnlyCB
    transOnlyCB, yOffset = CreateCheckbox(content, "TransTabOnly",
        "only show messages that were translated", yOffset, leftPad + 20, "translatedTabTranslatedOnly")
    local transClassCB
    transClassCB, yOffset = CreateCheckbox(content, "TransTabClass",
        "class-color player names (respects your chat settings)", yOffset, leftPad + 20, "tabClassColors")

    -- Tab channel picker: a checkable menu of which chats feed the Translated tab.
    local chanLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chanLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 20, yOffset - 4)
    chanLabel:SetText("Channels sent to tab:")
    local tabChanDD = CreateFrame("Frame", "RCT_TabChanDD", content, "UIDropDownMenuTemplate")
    tabChanDD:SetPoint("LEFT", chanLabel, "RIGHT", -6, -2)
    UIDropDownMenu_SetWidth(tabChanDD, 150)
    UIDropDownMenu_SetText(tabChanDD, "Pick channels")
    UIDropDownMenu_Initialize(tabChanDD, function(_, level)
        for _, ch in ipairs(T.TAB_CHANNEL_LIST) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = ch.label
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.checked = T:IsTabChannelEnabled(ch.key)
            info.func = function(_, _, _, checked)
                if not T.db.tabChannels then T.db.tabChannels = {} end
                T.db.tabChannels[ch.key] = checked and true or false
            end
            UIDropDownMenu_AddButton(info, level)
        end
        -- User-added custom channels appear as their own toggles.
        if T.db.customChannels then
            for cname in pairs(T.db.customChannels) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = cname .. " (custom)"
                info.isNotRadio = true
                info.keepShownOnClick = true
                info.checked = T:IsTabChannelEnabled("CUSTOM:" .. cname)
                info.func = function(_, _, _, checked)
                    T.db.customChannels[cname] = checked and true or false
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)
    yOffset = yOffset - 30

    -- Message-type picker: make the Translated tab a full chat tab by feeding in
    -- loot, skill-ups, system lines, etc. (WoW's native message groups). Opt-in.
    local mgLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mgLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 20, yOffset - 4)
    mgLabel:SetText("Message types sent to tab:")
    local tabMsgDD = CreateFrame("Frame", "RCT_TabMsgDD", content, "UIDropDownMenuTemplate")
    tabMsgDD:SetPoint("LEFT", mgLabel, "RIGHT", -6, -2)
    UIDropDownMenu_SetWidth(tabMsgDD, 150)
    UIDropDownMenu_SetText(tabMsgDD, "Pick types")
    UIDropDownMenu_Initialize(tabMsgDD, function(_, level)
        for _, mg in ipairs(T.TAB_MSGGROUP_LIST) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = mg.label
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.checked = T:IsTabMessageGroupEnabled(mg.key)
            info.func = function(_, _, _, checked)
                if not T.db.tabMessageGroups then T.db.tabMessageGroups = {} end
                T.db.tabMessageGroups[mg.key] = checked and true or false
                T:ApplyTabMessageGroups()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    yOffset = yOffset - 30


    -- don't match General/Trade/LFG/World). Each becomes its own toggle above.
    local ccLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ccLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 20, yOffset - 2)
    ccLabel:SetText("Custom channel:")
    local ccEdit = CreateFrame("EditBox", "RCT_CustomChanEdit", content, "InputBoxTemplate")
    ccEdit:SetSize(120, 20)
    ccEdit:SetAutoFocus(false)
    ccEdit:SetPoint("LEFT", ccLabel, "RIGHT", 10, 0)
    local ccAdd = CreateFrame("Button", "RCT_CustomChanAdd", content, "UIPanelButtonTemplate")
    ccAdd:SetSize(44, 20)
    ccAdd:SetText("Add")
    ccAdd:SetPoint("LEFT", ccEdit, "RIGHT", 8, 0)
    local ccRemove = CreateFrame("Button", "RCT_CustomChanRemove", content, "UIPanelButtonTemplate")
    ccRemove:SetSize(60, 20)
    ccRemove:SetText("Remove")
    ccRemove:SetPoint("LEFT", ccAdd, "RIGHT", 4, 0)
    ccAdd:SetScript("OnClick", function()
        if T:AddCustomChannel(ccEdit:GetText()) then ccEdit:SetText(""); ccEdit:ClearFocus() end
    end)
    ccRemove:SetScript("OnClick", function()
        T:RemoveCustomChannel(ccEdit:GetText()); ccEdit:SetText(""); ccEdit:ClearFocus()
    end)
    ccEdit:SetScript("OnEnterPressed", function() ccAdd:Click() end)
    ccEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    yOffset = yOffset - 30

    -- Outgoing translation: translate what you type in the tab's chat box before it sends.
    local outCB
    outCB, yOffset = CreateCheckbox(content, "TransOut",
        "Translate messages I type in the tab before sending", yOffset, leftPad + 20, "translateOutgoing")

    local sendLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sendLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 20, yOffset - 2)
    sendLabel:SetText("Send my messages in:")
    local sendDD = CreateFrame("Frame", "RCT_SendLangDD", content, "UIDropDownMenuTemplate")
    sendDD:SetPoint("LEFT", sendLabel, "RIGHT", 4, -2)
    UIDropDownMenu_SetWidth(sendDD, 120)
    local function SendDD_Set()
        local code = T.db.sendLang or T:DefaultTargetFromLocale()
        local name = (T.Languages[code] and T.Languages[code].name) or code or "?"
        UIDropDownMenu_SetText(sendDD, name)
    end
    UIDropDownMenu_Initialize(sendDD, function(_, level)
        local sorted = {}
        for code, ld in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then table.insert(sorted, { code = code, name = ld.name }) end
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        local cur = T.db.sendLang or T:DefaultTargetFromLocale()
        for _, e in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = e.name .. "  |cFF888888(" .. e.code .. ")|r"
            info.value = e.code
            info.checked = (cur == e.code)
            info.func = function(btn)
                T:EnableLanguage(btn.value)
                T.db.sendLang = btn.value
                SendDD_Set()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    SendDD_Set()
    yOffset = yOffset - 30

    local detectDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detectDesc:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    detectDesc:SetWidth(370)
    detectDesc:SetJustifyH("LEFT")
    detectDesc:SetText("|cFF888888Detection: Script analysis (Cyrillic, CJK, Kana, Hangul) -> " ..
        "marker word matching -> full dictionary scan.|r")
    yOffset = yOffset - 32

    -- ===================== Chat Channels =====================
    local _, newY = CreateSectionHeader(content, "Chat Channels", yOffset, leftPad)
    yOffset = newY

    local channelNames = {
        { key = "SAY",           label = "Say" },
        { key = "YELL",          label = "Yell" },
        { key = "PARTY",         label = "Party" },
        { key = "PARTY_LEADER",  label = "Party Leader" },
        { key = "RAID",          label = "Raid" },
        { key = "RAID_LEADER",   label = "Raid Leader" },
        { key = "GUILD",         label = "Guild" },
        { key = "OFFICER",       label = "Officer" },
        { key = "WHISPER",       label = "Whisper" },
        { key = "CHANNEL",       label = "General/Trade/LFG" },
        { key = "EMOTE",         label = "Emotes" },
    }
    if RCT_Compat.hasInstanceChat then
        -- Insert before Emotes (second-to-last position)
        table.insert(channelNames, #channelNames, { key = "INSTANCE_CHAT",        label = "Instance (Dungeon/BG)" })
        table.insert(channelNames, #channelNames, { key = "INSTANCE_CHAT_LEADER", label = "Instance Leader" })
    end

    local chanCheckboxes = {}
    for i, chan in ipairs(channelNames) do
        local col = ((i - 1) % 2)
        local row = math.floor((i - 1) / 2)
        local xOff = leftPad + (col * 190)
        local yOff = yOffset - (row * 24)

        local cb = CreateFrame("CheckButton", "RCT_Chan_" .. chan.key, content, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", xOff, yOff)
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 3, 0)
        cb.text:SetText(chan.label)
        cb:SetChecked(T.db.channels[chan.key])

        local chanKey = chan.key
        cb:SetScript("OnClick", function(self)
            T.db.channels[chanKey] = self:GetChecked()
        end)
        cb._chanKey = chanKey
        table.insert(chanCheckboxes, cb)
    end
    yOffset = yOffset - (math.ceil(#channelNames / 2) * 24) - 10

    local selectAllBtn = CreateFrame("Button", "RCT_SelectAll", content, "UIPanelButtonTemplate")
    selectAllBtn:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    selectAllBtn:SetSize(110, 22)
    selectAllBtn:SetText("Select All")
    selectAllBtn:SetScript("OnClick", function()
        for _, cb in ipairs(chanCheckboxes) do
            cb:SetChecked(true)
            T.db.channels[cb._chanKey] = true
        end
    end)

    local deselectAllBtn = CreateFrame("Button", "RCT_DeselectAll", content, "UIPanelButtonTemplate")
    deselectAllBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 10, 0)
    deselectAllBtn:SetSize(110, 22)
    deselectAllBtn:SetText("Deselect All")
    deselectAllBtn:SetScript("OnClick", function()
        for _, cb in ipairs(chanCheckboxes) do
            cb:SetChecked(false)
            T.db.channels[cb._chanKey] = false
        end
    end)
    yOffset = yOffset - 32

    -- ===================== Quick Translate =====================
    local _, newY = CreateSectionHeader(content, "Quick Translate", yOffset, leftPad)
    yOffset = newY

    local qtDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qtDesc:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    qtDesc:SetText("|cFF888888Type text below. Uses source/target language settings.|r")
    yOffset = yOffset - 16

    local editBox = CreateFrame("EditBox", "RCT_QuickTranslate", content, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 10, yOffset)
    editBox:SetSize(270, 25)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(256)

    local translateBtn = CreateFrame("Button", "RCT_TranslateBtn", content, "UIPanelButtonTemplate")
    translateBtn:SetPoint("LEFT", editBox, "RIGHT", 8, 0)
    translateBtn:SetSize(90, 25)
    translateBtn:SetText("Translate")
    translateBtn:SetScript("OnClick", function()
        local text = editBox:GetText()
        if text and text ~= "" then
            local detected, confidence, method = T:ResolveSourceLang(text)
            local targetLang = T.db.targetLang
            local targetName = T.Languages[targetLang] and T.Languages[targetLang].name or targetLang
            if detected and detected ~= targetLang and confidence > 0.15 then
                local result, wt, tw = T:Translate(text, detected, targetLang)
                local langName = T.Languages[detected] and T.Languages[detected].name or detected
                local confPct = math.floor(confidence * 100)
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cFFFFAA00[RC-T %s -> %s]|r %s |cFF888888(%d/%d words, %d%% %s)|r",
                        langName, targetName, result, wt, tw, confPct, method or ""))
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00[RC-T]|r No foreign language detected.")
            end
        end
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        translateBtn:Click()
        self:ClearFocus()
    end)
    yOffset = yOffset - 35

    local lastBtn = CreateFrame("Button", "RCT_TranslateLast", content, "UIPanelButtonTemplate")
    lastBtn:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    lastBtn:SetSize(180, 24)
    lastBtn:SetText("Translate Last Message")
    lastBtn:SetScript("OnClick", function()
        if T.recentMessages[1] then
            T:TranslateToIM(T.recentMessages[1])
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00[RC-T]|r No messages in buffer.")
        end
    end)

    local last5Btn = CreateFrame("Button", "RCT_TranslateLast5", content, "UIPanelButtonTemplate")
    last5Btn:SetPoint("LEFT", lastBtn, "RIGHT", 10, 0)
    last5Btn:SetSize(180, 24)
    last5Btn:SetText("Translate Last 5")
    last5Btn:SetScript("OnClick", function()
        local count = math.min(5, #T.recentMessages)
        if count == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00[RC-T]|r No messages in buffer.")
            return
        end
        for i = count, 1, -1 do
            T:TranslateToIM(T.recentMessages[i])
        end
    end)
    yOffset = yOffset - 35

    -- ===================== Ignore List =====================
    local _, newY = CreateSectionHeader(content, "Ignore List (Skip in Detection)", yOffset, leftPad)
    yOffset = newY

    local ignoreDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ignoreDesc:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    ignoreDesc:SetWidth(370)
    ignoreDesc:SetJustifyH("LEFT")
    ignoreDesc:SetText("|cFF888888Words below are skipped during language detection and translation. " ..
        "Good for abbreviations like gg, lol, brb, afk, etc.|r")
    yOffset = yOffset - 28

    local ignoreInput = CreateFrame("EditBox", "RCT_IgnoreInput", content, "InputBoxTemplate")
    ignoreInput:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 10, yOffset)
    ignoreInput:SetSize(200, 25)
    ignoreInput:SetAutoFocus(false)
    ignoreInput:SetMaxLetters(50)

    local ignoreAddBtn = CreateFrame("Button", "RCT_IgnoreAdd", content, "UIPanelButtonTemplate")
    ignoreAddBtn:SetPoint("LEFT", ignoreInput, "RIGHT", 8, 0)
    ignoreAddBtn:SetSize(60, 25)
    ignoreAddBtn:SetText("Add")

    local ignoreRemBtn = CreateFrame("Button", "RCT_IgnoreRem", content, "UIPanelButtonTemplate")
    ignoreRemBtn:SetPoint("LEFT", ignoreAddBtn, "RIGHT", 5, 0)
    ignoreRemBtn:SetSize(70, 25)
    ignoreRemBtn:SetText("Remove")
    yOffset = yOffset - 30

    local ignoreListBg = CreateFrame("Frame", "RCT_IgnoreListBG", content, "InsetFrameTemplate")
    ignoreListBg:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    ignoreListBg:SetSize(375, 90)

    local ignoreScroll = CreateFrame("ScrollFrame", "RCT_IgnoreScroll", ignoreListBg, "UIPanelScrollFrameTemplate")
    ignoreScroll:SetPoint("TOPLEFT", ignoreListBg, "TOPLEFT", 5, -5)
    ignoreScroll:SetPoint("BOTTOMRIGHT", ignoreListBg, "BOTTOMRIGHT", -25, 5)

    local ignoreText = CreateFrame("EditBox", "RCT_IgnoreText", ignoreScroll)
    ignoreText:SetMultiLine(true)
    ignoreText:SetAutoFocus(false)
    ignoreText:SetFontObject(GameFontHighlightSmall)
    ignoreText:SetWidth(340)
    ignoreText:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ignoreText:SetScript("OnChar", function(self) T:RefreshIgnoreDisplay(self) end)
    ignoreText:EnableMouse(true)
    ignoreScroll:SetScrollChild(ignoreText)

    f.ignoreText = ignoreText

    function T:RefreshIgnoreDisplay(textWidget)
        local tw = textWidget or f.ignoreText
        if not tw then return end
        if not T.db or not T.db.ignoreWords then return end

        local sorted = {}
        for _, w in ipairs(T.db.ignoreWords) do
            table.insert(sorted, w)
        end
        table.sort(sorted)

        local display = table.concat(sorted, ", ")
        tw:SetText("|cFFCCCCCC" .. display .. "|r")
        tw:SetCursorPosition(0)
    end

    local ignoreCountLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ignoreCountLabel:SetPoint("TOPLEFT", ignoreListBg, "BOTTOMLEFT", 0, -3)
    f.ignoreCountLabel = ignoreCountLabel

    local function UpdateIgnoreCount()
        local count = T.db and T.db.ignoreWords and #T.db.ignoreWords or 0
        ignoreCountLabel:SetText("|cFF888888" .. count .. " words ignored|r")
    end

    ignoreAddBtn:SetScript("OnClick", function()
        local text = ignoreInput:GetText()
        if text and text ~= "" then
            local added = {}
            for word in text:gmatch("%S+") do
                if T:AddIgnoreWord(word) then
                    table.insert(added, word)
                end
            end
            if #added > 0 then
                print("|cFF00FF00[RC-Translator]|r Added to ignore list: |cFFFFFF00" .. table.concat(added, ", ") .. "|r")
            end
            ignoreInput:SetText("")
            ignoreInput:ClearFocus()
            T:RefreshIgnoreDisplay()
            UpdateIgnoreCount()
        end
    end)

    ignoreRemBtn:SetScript("OnClick", function()
        local text = ignoreInput:GetText()
        if text and text ~= "" then
            local removed = {}
            for word in text:gmatch("%S+") do
                if T:RemoveIgnoreWord(word) then
                    table.insert(removed, word)
                end
            end
            if #removed > 0 then
                print("|cFF00FF00[RC-Translator]|r Removed from ignore list: |cFFFFFF00" .. table.concat(removed, ", ") .. "|r")
            end
            ignoreInput:SetText("")
            ignoreInput:ClearFocus()
            T:RefreshIgnoreDisplay()
            UpdateIgnoreCount()
        end
    end)

    ignoreInput:SetScript("OnEnterPressed", function(self)
        ignoreAddBtn:Click()
    end)

    yOffset = yOffset - 110

    -- ===================== Custom Dictionary =====================
    local _, newY = CreateSectionHeader(content, "Custom Dictionary", yOffset, leftPad)
    yOffset = newY

    local customDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    customDesc:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    customDesc:SetWidth(370)
    customDesc:SetJustifyH("LEFT")
    customDesc:SetText("|cFF888888Add your own words and translations. These are saved and persist across sessions. " ..
        "Pick a language, type the English word, the translation, and click Add.|r")
    yOffset = yOffset - 36

    -- Language picker for custom entry
    local customLangLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    customLangLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    customLangLabel:SetText("Language:")

    local customLangDropdown = CreateFrame("Frame", "RCT_CustomLangDropdown", content, "UIDropDownMenuTemplate")
    customLangDropdown:SetPoint("LEFT", customLangLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(customLangDropdown, 160)

    local customLangCode = T.db.targetLang  -- default to current target

    local function CustomLangPicker_SetDisplay()
        local name = T.Languages[customLangCode] and T.Languages[customLangCode].name or customLangCode
        UIDropDownMenu_SetText(customLangDropdown, name .. " (" .. customLangCode .. ")")
    end

    UIDropDownMenu_Initialize(customLangDropdown, function(self, level)
        local sorted = {}
        for code, langData in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then
                table.insert(sorted, { code = code, name = langData.name })
            end
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        for _, entry in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.name .. " (" .. entry.code .. ")"
            info.value = entry.code
            info.checked = (customLangCode == entry.code)
            info.func = function(btn)
                customLangCode = btn.value
                CustomLangPicker_SetDisplay()
                T:RefreshCustomDisplay()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    CustomLangPicker_SetDisplay()
    yOffset = yOffset - 32

    -- English word input
    local customEngLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    customEngLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    customEngLabel:SetText("|cFFCCCCCCEnglish:|r")

    local customEngInput = CreateFrame("EditBox", "RCT_CustomEngInput", content, "InputBoxTemplate")
    customEngInput:SetPoint("LEFT", customEngLabel, "RIGHT", 8, 0)
    customEngInput:SetSize(130, 25)
    customEngInput:SetAutoFocus(false)
    customEngInput:SetMaxLetters(60)

    -- Translation input
    local customTransLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    customTransLabel:SetPoint("LEFT", customEngInput, "RIGHT", 10, 0)
    customTransLabel:SetText("|cFFCCCCCC=|r")

    local customTransInput = CreateFrame("EditBox", "RCT_CustomTransInput", content, "InputBoxTemplate")
    customTransInput:SetPoint("LEFT", customTransLabel, "RIGHT", 8, 0)
    customTransInput:SetSize(130, 25)
    customTransInput:SetAutoFocus(false)
    customTransInput:SetMaxLetters(80)
    yOffset = yOffset - 30

    -- Add / Remove buttons
    local customAddBtn = CreateFrame("Button", "RCT_CustomAdd", content, "UIPanelButtonTemplate")
    customAddBtn:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    customAddBtn:SetSize(60, 24)
    customAddBtn:SetText("Add")

    local customRemBtn = CreateFrame("Button", "RCT_CustomRem", content, "UIPanelButtonTemplate")
    customRemBtn:SetPoint("LEFT", customAddBtn, "RIGHT", 5, 0)
    customRemBtn:SetSize(70, 24)
    customRemBtn:SetText("Remove")

    local customClearBtn = CreateFrame("Button", "RCT_CustomClear", content, "UIPanelButtonTemplate")
    customClearBtn:SetPoint("LEFT", customRemBtn, "RIGHT", 5, 0)
    customClearBtn:SetSize(80, 24)
    customClearBtn:SetText("Clear All")
    yOffset = yOffset - 30

    -- Custom entries display (scrollable list)
    local customListBg = CreateFrame("Frame", "RCT_CustomListBG", content, "InsetFrameTemplate")
    customListBg:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    customListBg:SetSize(375, 100)

    local customScroll = CreateFrame("ScrollFrame", "RCT_CustomScroll", customListBg, "UIPanelScrollFrameTemplate")
    customScroll:SetPoint("TOPLEFT", customListBg, "TOPLEFT", 5, -5)
    customScroll:SetPoint("BOTTOMRIGHT", customListBg, "BOTTOMRIGHT", -25, 5)

    local customText = CreateFrame("EditBox", "RCT_CustomText", customScroll)
    customText:SetMultiLine(true)
    customText:SetAutoFocus(false)
    customText:SetFontObject(GameFontHighlightSmall)
    customText:SetWidth(340)
    customText:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    customText:SetScript("OnChar", function() end)  -- read-only display
    customText:EnableMouse(true)
    customScroll:SetScrollChild(customText)

    f.customText = customText

    local customCountLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    customCountLabel:SetPoint("TOPLEFT", customListBg, "BOTTOMLEFT", 0, -3)
    f.customCountLabel = customCountLabel

    function T:RefreshCustomDisplay()
        if not f.customText then return end
        if not T.db or not T.db.customDictionary then
            f.customText:SetText("|cFF666666(no custom entries)|r")
            f.customCountLabel:SetText("|cFF888888" .. "0 custom entries|r")
            return
        end

        local entries = T.db.customDictionary[customLangCode]
        if not entries then
            local langName = T.Languages[customLangCode] and T.Languages[customLangCode].name or customLangCode
            f.customText:SetText("|cFF666666(no custom entries for " .. langName .. ")|r")
            f.customCountLabel:SetText("|cFF888888" .. "0 entries for this language, " .. T:GetCustomEntryCount() .. " total|r")
            return
        end

        local sorted = {}
        for eng, trans in pairs(entries) do
            table.insert(sorted, { eng = eng, trans = trans })
        end
        table.sort(sorted, function(a, b) return a.eng < b.eng end)

        local lines = {}
        for _, e in ipairs(sorted) do
            table.insert(lines, "|cFFFFFF00" .. e.eng .. "|r = |cFFFFCC00" .. e.trans .. "|r")
        end

        f.customText:SetText(table.concat(lines, "\n"))
        f.customText:SetCursorPosition(0)

        local langCount = #sorted
        local totalCount = T:GetCustomEntryCount()
        f.customCountLabel:SetText("|cFF888888" .. langCount .. " entries for this language, " .. totalCount .. " total|r")
    end

    customAddBtn:SetScript("OnClick", function()
        local eng = customEngInput:GetText()
        local trans = customTransInput:GetText()
        if eng and eng ~= "" and trans and trans ~= "" then
            local ok, err = T:AddCustomEntry(customLangCode, eng, trans)
            if ok then
                local langName = T.Languages[customLangCode] and T.Languages[customLangCode].name or customLangCode
                print("|cFF00FF00[RC-Translator]|r Added to " .. langName .. ": |cFFFFFF00" .. eng:lower() .. "|r = |cFFFFCC00" .. trans .. "|r")
                customEngInput:SetText("")
                customTransInput:SetText("")
                customEngInput:ClearFocus()
                customTransInput:ClearFocus()
                T:RefreshCustomDisplay()
            else
                print("|cFFFF0000[RC-Translator]|r " .. (err or "Failed to add"))
            end
        else
            print("|cFFFF0000[RC-Translator]|r Enter both an English word and its translation.")
        end
    end)

    customRemBtn:SetScript("OnClick", function()
        local eng = customEngInput:GetText()
        if eng and eng ~= "" then
            local ok, err = T:RemoveCustomEntry(customLangCode, eng)
            if ok then
                print("|cFF00FF00[RC-Translator]|r Removed: |cFFFFFF00" .. eng .. "|r")
                customEngInput:SetText("")
                customEngInput:ClearFocus()
                T:RefreshCustomDisplay()
            else
                print("|cFFFF0000[RC-Translator]|r " .. (err or "Not a custom entry"))
            end
        end
    end)

    customClearBtn:SetScript("OnClick", function()
        if T.db.customDictionary and T.db.customDictionary[customLangCode] then
            -- Remove all custom entries for this language from the live dictionary
            for eng, trans in pairs(T.db.customDictionary[customLangCode]) do
                if T:IsLanguageLoaded(customLangCode) then
                    T.Languages[customLangCode].dictionary[eng] = nil
                    T.Languages[customLangCode].reverse[trans:lower()] = nil
                end
            end
            T.db.customDictionary[customLangCode] = nil
            -- Recount
            if T:IsLanguageLoaded(customLangCode) then
                local count = 0
                for _ in pairs(T.Languages[customLangCode].dictionary) do count = count + 1 end
                T.Languages[customLangCode].wordCount = count
            end
            local langName = T.Languages[customLangCode] and T.Languages[customLangCode].name or customLangCode
            print("|cFF00FF00[RC-Translator]|r Cleared all custom entries for " .. langName)
            T:RefreshCustomDisplay()
        end
    end)

    customEngInput:SetScript("OnTabPressed", function(self)
        customTransInput:SetFocus()
    end)

    customTransInput:SetScript("OnEnterPressed", function(self)
        customAddBtn:Click()
    end)

    customEngInput:SetScript("OnEnterPressed", function(self)
        customTransInput:SetFocus()
    end)

    yOffset = yOffset - 120

    -- ===================== Profiles =====================
    local _, newY = CreateSectionHeader(content, "Profiles", yOffset, leftPad)
    yOffset = newY

    local profileDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profileDesc:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    profileDesc:SetWidth(370)
    profileDesc:SetJustifyH("LEFT")
    profileDesc:SetText("|cFF888888Save different settings and custom dictionaries per character or purpose. " ..
        "Each profile stores its own target language, channels, ignore list, and custom entries.|r")
    yOffset = yOffset - 36

    -- Active profile label
    local profileActiveLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profileActiveLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    profileActiveLabel:SetText("Active: |cFF00FF00" .. (T.profileName or "Default") .. "|r")
    f.profileActiveLabel = profileActiveLabel

    -- Profile dropdown
    local profileDropdown = CreateFrame("Frame", "RCT_ProfileDropdown", content, "UIDropDownMenuTemplate")
    profileDropdown:SetPoint("LEFT", profileActiveLabel, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(profileDropdown, 130)

    local function ProfileDropdown_Refresh()
        UIDropDownMenu_SetText(profileDropdown, T.profileName or "Default")
        profileActiveLabel:SetText("Active: |cFF00FF00" .. (T.profileName or "Default") .. "|r")
    end

    UIDropDownMenu_Initialize(profileDropdown, function(self, level)
        local profiles = T:GetProfileList()
        for _, name in ipairs(profiles) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.value = name
            info.checked = (name == T.profileName)
            info.func = function(btn)
                local ok, err = T:SwitchProfile(btn.value)
                if ok then
                    print("|cFF00FF00[RC-Translator]|r Switched to profile: |cFFFFFF00" .. btn.value .. "|r")
                    ProfileDropdown_Refresh()
                    -- Refresh all UI elements
                    if f:IsShown() then f:Hide(); f:Show() end
                else
                    print("|cFFFF0000[RC-Translator]|r " .. (err or "Failed"))
                end
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    ProfileDropdown_Refresh()
    yOffset = yOffset - 32

    -- New profile name input
    local newProfileLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    newProfileLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    newProfileLabel:SetText("|cFFCCCCCCNew name:|r")

    local newProfileInput = CreateFrame("EditBox", "RCT_NewProfileInput", content, "InputBoxTemplate")
    newProfileInput:SetPoint("LEFT", newProfileLabel, "RIGHT", 8, 0)
    newProfileInput:SetSize(120, 25)
    newProfileInput:SetAutoFocus(false)
    newProfileInput:SetMaxLetters(30)

    local profileCreateBtn = CreateFrame("Button", "RCT_ProfileCreate", content, "UIPanelButtonTemplate")
    profileCreateBtn:SetPoint("LEFT", newProfileInput, "RIGHT", 5, 0)
    profileCreateBtn:SetSize(60, 24)
    profileCreateBtn:SetText("Create")

    local profileDeleteBtn = CreateFrame("Button", "RCT_ProfileDelete", content, "UIPanelButtonTemplate")
    profileDeleteBtn:SetPoint("LEFT", profileCreateBtn, "RIGHT", 5, 0)
    profileDeleteBtn:SetSize(60, 24)
    profileDeleteBtn:SetText("Delete")

    profileCreateBtn:SetScript("OnClick", function()
        local name = newProfileInput:GetText()
        if name and name ~= "" then
            local ok, err = T:CreateProfile(name)
            if ok then
                print("|cFF00FF00[RC-Translator]|r Created profile: |cFFFFFF00" .. name .. "|r")
                newProfileInput:SetText("")
                newProfileInput:ClearFocus()
            else
                print("|cFFFF0000[RC-Translator]|r " .. (err or "Failed"))
            end
        end
    end)

    profileDeleteBtn:SetScript("OnClick", function()
        local name = newProfileInput:GetText()
        if name and name ~= "" then
            StaticPopupDialogs["RCT_DELETE_PROFILE"] = {
                text = "Delete profile |cFFFFFF00" .. name .. "|r? This cannot be undone.",
                button1 = "Delete",
                button2 = "Cancel",
                OnAccept = function()
                    local ok, err = T:DeleteProfile(name)
                    if ok then
                        print("|cFF00FF00[RC-Translator]|r Deleted profile: |cFFFFFF00" .. name .. "|r")
                        newProfileInput:SetText("")
                    else
                        print("|cFFFF0000[RC-Translator]|r " .. (err or "Failed"))
                    end
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("RCT_DELETE_PROFILE")
        end
    end)

    newProfileInput:SetScript("OnEnterPressed", function(self)
        profileCreateBtn:Click()
    end)

    yOffset = yOffset - 32

    -- Copy profile button
    local profileCopyBtn = CreateFrame("Button", "RCT_ProfileCopy", content, "UIPanelButtonTemplate")
    profileCopyBtn:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    profileCopyBtn:SetSize(150, 24)
    profileCopyBtn:SetText("Copy Active → New")

    profileCopyBtn:SetScript("OnClick", function()
        local name = newProfileInput:GetText()
        if name and name ~= "" then
            local ok, err = T:CopyProfile(T.profileName, name)
            if ok then
                print("|cFF00FF00[RC-Translator]|r Copied |cFFFFFF00" .. T.profileName .. "|r → |cFFFFFF00" .. name .. "|r")
                newProfileInput:SetText("")
            else
                print("|cFFFF0000[RC-Translator]|r " .. (err or "Failed"))
            end
        else
            print("|cFFFF0000[RC-Translator]|r Enter a name for the copy first.")
        end
    end)

    yOffset = yOffset - 35

    -- ===================== Share Dictionary =====================
    local _, newY = CreateSectionHeader(content, "Share Custom Dictionary", yOffset, leftPad)
    yOffset = newY

    local shareDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shareDesc:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    shareDesc:SetWidth(370)
    shareDesc:SetJustifyH("LEFT")
    shareDesc:SetText("|cFF888888Send your custom dictionary entries to other players who have RC-Translator. " ..
        "They'll get a popup to accept or decline. Pick a language and a channel/player.|r")
    yOffset = yOffset - 36

    -- Language picker for sharing
    local shareLangLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    shareLangLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    shareLangLabel:SetText("Language:")

    local shareLangDropdown = CreateFrame("Frame", "RCT_ShareLangDropdown", content, "UIDropDownMenuTemplate")
    shareLangDropdown:SetPoint("LEFT", shareLangLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(shareLangDropdown, 160)

    local shareLangCode = T.db.targetLang

    local function ShareLang_SetDisplay()
        local name = T.Languages[shareLangCode] and T.Languages[shareLangCode].name or shareLangCode
        local count = T:GetCustomEntryCount(shareLangCode)
        UIDropDownMenu_SetText(shareLangDropdown, name .. " (" .. count .. " custom)")
    end

    UIDropDownMenu_Initialize(shareLangDropdown, function(self, level)
        local sorted = {}
        for code, langData in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then
                table.insert(sorted, { code = code, name = langData.name })
            end
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        for _, entry in ipairs(sorted) do
            local count = T:GetCustomEntryCount(entry.code)
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.name .. " (" .. entry.code .. ") - " .. count .. " custom"
            info.value = entry.code
            info.checked = (shareLangCode == entry.code)
            info.func = function(btn)
                shareLangCode = btn.value
                ShareLang_SetDisplay()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    ShareLang_SetDisplay()
    yOffset = yOffset - 32

    -- Channel / target row
    local shareChannelLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    shareChannelLabel:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    shareChannelLabel:SetText("Send to:")

    local shareChannelDropdown = CreateFrame("Frame", "RCT_ShareChannelDropdown", content, "UIDropDownMenuTemplate")
    shareChannelDropdown:SetPoint("LEFT", shareChannelLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(shareChannelDropdown, 90)

    local shareChannel = "WHISPER"
    UIDropDownMenu_SetText(shareChannelDropdown, "Whisper")

    UIDropDownMenu_Initialize(shareChannelDropdown, function(self, level)
        local channels = {
            { value = "WHISPER", text = "Whisper" },
            { value = "PARTY", text = "Party" },
            { value = "RAID", text = "Raid" },
            { value = "GUILD", text = "Guild" },
        }
        for _, ch in ipairs(channels) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = ch.text
            info.value = ch.value
            info.checked = (shareChannel == ch.value)
            info.func = function(btn)
                shareChannel = btn.value
                UIDropDownMenu_SetText(shareChannelDropdown, ch.text)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Player name input (for whisper)
    local sharePlayerInput = CreateFrame("EditBox", "RCT_SharePlayerInput", content, "InputBoxTemplate")
    sharePlayerInput:SetPoint("LEFT", shareChannelDropdown, "RIGHT", 0, 2)
    sharePlayerInput:SetSize(100, 25)
    sharePlayerInput:SetAutoFocus(false)
    sharePlayerInput:SetMaxLetters(30)

    local sharePlayerHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sharePlayerHint:SetPoint("LEFT", sharePlayerInput, "RIGHT", 4, 0)
    sharePlayerHint:SetText("|cFF666666← player name|r")
    yOffset = yOffset - 32

    -- Share button
    local shareBtn = CreateFrame("Button", "RCT_ShareBtn", content, "UIPanelButtonTemplate")
    shareBtn:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    shareBtn:SetSize(120, 26)
    shareBtn:SetText("Share Dictionary")

    shareBtn:SetScript("OnClick", function()
        local target = nil
        if shareChannel == "WHISPER" then
            target = sharePlayerInput:GetText()
            if not target or target == "" then
                print("|cFFFF0000[RC-Translator]|r Enter a player name for whisper sharing.")
                return
            end
        end
        local ok, err = T:ShareDictionary(shareLangCode, shareChannel, target)
        if not ok then
            print("|cFFFF0000[RC-Translator]|r " .. (err or "Failed to share"))
        end
    end)

    -- Share count info
    local shareInfoLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shareInfoLabel:SetPoint("LEFT", shareBtn, "RIGHT", 10, 0)
    f.shareInfoLabel = shareInfoLabel

    local function UpdateShareInfo()
        local count = T:GetCustomEntryCount(shareLangCode)
        local langName = T.Languages[shareLangCode] and T.Languages[shareLangCode].name or shareLangCode
        if count > 0 then
            shareInfoLabel:SetText("|cFF00FF00" .. count .. " entries ready to share|r")
        else
            shareInfoLabel:SetText("|cFFFF8800No custom entries for " .. langName .. "|r")
        end
    end
    UpdateShareInfo()

    sharePlayerInput:SetScript("OnEnterPressed", function(self)
        shareBtn:Click()
    end)

    yOffset = yOffset - 35

    -- ===================== Loaded Dictionaries =====================
    local _, newY = CreateSectionHeader(content, "Loaded Dictionaries", yOffset, leftPad)
    yOffset = newY

    f.statsText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.statsText:SetPoint("TOPLEFT", content, "TOPLEFT", leftPad + 5, yOffset)
    f.statsText:SetWidth(370)
    f.statsText:SetJustifyH("LEFT")
    f.statsText:SetSpacing(2)
    f.statsText:SetText("|cFF888888Loading dictionary stats...|r")

    -- ===================== OnShow Refresh =====================
    f:SetScript("OnShow", function()
        enableCB:SetChecked(T.db.enabled)
        minimapCB:SetChecked(not T.db.minimap.hide)
        autoCB:SetChecked(T.db.autoTranslate)
        detectInfoCB:SetChecked(T.db.showDetectionInfo)
        origCB:SetChecked(T.db.showOriginal)
        autoToIMCB:SetChecked(T.db.autoTranslateToIM)

        for _, cb in ipairs(chanCheckboxes) do
            cb:SetChecked(T.db.channels[cb._chanKey])
        end

        if T.Languages[T.db.targetLang] then
            UIDropDownMenu_SetText(langDropdown, T.Languages[T.db.targetLang].name .. " (" .. T.db.targetLang .. ")")
        end

        T:RefreshIgnoreDisplay()
        UpdateIgnoreCount()
        T:RefreshCustomDisplay()

        -- Refresh profile display
        ProfileDropdown_Refresh()

        -- Refresh share info
        ShareLang_SetDisplay()
        UpdateShareInfo()

        local sorted = {}
        for code, langData in pairs(T.Languages) do
            if T:IsLanguageVisible(code) then
                local n = (T.CountPackedEntries and T:CountPackedEntries(code)) or langData.wordCount or 0
                table.insert(sorted, { code = code, data = langData, count = n })
            end
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)

        local lines = {}
        local totalWords = 0
        local kt = T.GetKeyTable and T:GetKeyTable()
        local keyCount = (kt and #kt) or 26388   -- true number of translatable phrases
        for _, entry in ipairs(sorted) do
            totalWords = totalWords + entry.count
            local active = (entry.code == T.db.targetLang) and "  |cFF00FF00<< ACTIVE|r" or ""
            local customCount = T:GetCustomEntryCount(entry.code)
            local customTag = customCount > 0 and (" |cFFFF8800(+" .. customCount .. " custom)|r") or ""
            if entry.code == "en" then
                table.insert(lines, string.format("|cFFFFFF00%s|r (en): |cFFAAAAAA base language (translate to English)|r%s",
                    entry.data.name, active))
            else
                local pct = keyCount > 0 and math.floor(100 * entry.count / keyCount + 0.5) or 0
                table.insert(lines, string.format("|cFFFFFF00%s|r (%s): |cFFAAFFAA%d / %d phrases (%d%%)|r%s%s",
                    entry.data.name, entry.code, entry.count, keyCount, pct, customTag, active))
            end
        end
        table.insert(lines, "")
        local totalCustom = T:GetCustomEntryCount()
        local customLine = totalCustom > 0 and (" (incl. " .. totalCustom .. " custom)") or ""
        table.insert(lines, string.format("|cFF00FF00Total: %d languages, %d phrases translated%s|r", #sorted, totalWords, customLine))
        f.statsText:SetText(table.concat(lines, "\n"))
    end)

    -- Secret Languages button (bottom of options, always visible)
    do
        local secretBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        secretBtn:SetSize(160, 22)
        secretBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 12, 10)

        local function UpdateSecretBtn()
            if T.db.secretUnlocked then
                secretBtn:SetText("|cFFFFD700★ Secret Languages ✓|r")
                secretBtn:Disable()
            else
                secretBtn:SetText("🔒 Secret Languages")
                secretBtn:Enable()
            end
        end
        UpdateSecretBtn()

        secretBtn:SetScript("OnClick", function()
            T:OpenSecretPanel()
        end)

        f.secretBtn = secretBtn
        f.UpdateSecretBtn = UpdateSecretBtn
    end

    self.OptionsFrame = f
    tinsert(UISpecialFrames, "RC_TranslatorOptions")
end

-- ============================================================
-- SECRET LANGUAGE UNLOCK PANEL
-- ============================================================

function T:OpenSecretPanel()
    if self.SecretPanel then
        self.SecretPanel:Show()
        if self.SecretPanel.inputBox then
            self.SecretPanel.inputBox:SetText("")
            self.SecretPanel.inputBox:SetFocus()
        end
        return
    end

    local panel = RCT_Compat.CreateFrameWithBackdrop("RCT_SecretPanel", UIParent)
    panel:SetSize(320, 220)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    RCT_Compat.ApplyDialogBackdrop(panel)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
    panel:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then self:Hide() end
    end)
    panel:EnableKeyboard(true)
    tinsert(UISpecialFrames, "RCT_SecretPanel")

    -- Title bar
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", panel, "TOP", 0, -18)
    title:SetText("|cFFFF00FF🔮 Secret Languages|r")

    -- Flavour text
    local lore = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lore:SetPoint("TOP", title, "BOTTOM", 0, -14)
    lore:SetWidth(270)
    lore:SetJustifyH("CENTER")
    lore:SetText("|cFFAAAAAAAAA forgotten tongue stirs in the shadows.\nSpeak the ancient sequence to unlock it.|r")

    -- Hint line
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", lore, "BOTTOM", 0, -10)
    hint:SetText("|cFF666666Hint: Konami code (↑↑↓↓←→←→BA)|r")

    -- Input label
    local inputLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inputLabel:SetPoint("TOP", hint, "BOTTOM", 0, -14)
    inputLabel:SetText("Enter the code:")

    -- Input box
    local inputBox = CreateFrame("EditBox", "RCT_SecretPanelInput", panel, "InputBoxTemplate")
    inputBox:SetSize(180, 24)
    inputBox:SetPoint("TOP", inputLabel, "BOTTOM", 0, -6)
    inputBox:SetAutoFocus(false)
    inputBox:SetMaxLetters(20)
    inputBox:SetFontObject(GameFontHighlightSmall)
    inputBox:SetJustifyH("CENTER")

    -- Feedback text (hidden initially)
    local feedback = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    feedback:SetPoint("TOP", inputBox, "BOTTOM", 0, -8)
    feedback:SetText("")

    -- Attempt counter
    local attempts = 0

    local function TryCode()
        local input = inputBox:GetText()
        if T:CheckSecretCode(input) then
            -- Success!
            feedback:SetText("|cFF00FF00✓ UNLOCKED! Cross-faction languages available.|r")
            inputBox:SetText("")
            inputBox:ClearFocus()
            -- Update the button in options panel
            if T.OptionsFrame and T.OptionsFrame.UpdateSecretBtn then
                T.OptionsFrame.UpdateSecretBtn()
            end
            -- Flash the panel border gold
            local flash = panel:CreateTexture(nil, "OVERLAY")
            flash:SetAllPoints(panel)
            flash:SetTexture(1,1,1,1) flash:SetVertexColor(1, 0.84, 0, 0.3)
            C_Timer.After(0.8, function() flash:Hide() end)
            -- Auto-close after 2.5s
            C_Timer.After(2.5, function()
                if panel:IsShown() then panel:Hide() end
            end)
        else
            attempts = attempts + 1
            inputBox:SetText("")
            if attempts >= 3 then
                feedback:SetText("|cFFFF4444✗ Wrong. (Hint: type the Konami code in letters)|r")
            else
                feedback:SetText("|cFFFF4444✗ Incorrect code. Try again.|r")
            end
            -- Shake the input box
            local origX, origY = inputBox:GetLeft(), inputBox:GetTop()
            local shakeCount = 0
            local shakeTimer
            shakeTimer = C_Timer.NewTicker(0.05, function()
                shakeCount = shakeCount + 1
                local offset = (shakeCount % 2 == 0) and 4 or -4
                inputBox:ClearAllPoints()
                inputBox:SetPoint("TOP", inputLabel, "BOTTOM", offset, -6)
                if shakeCount >= 6 then
                    shakeTimer:Cancel()
                    inputBox:ClearAllPoints()
                    inputBox:SetPoint("TOP", inputLabel, "BOTTOM", 0, -6)
                end
            end)
        end
    end

    inputBox:SetScript("OnEnterPressed", function(self)
        TryCode()
    end)

    -- Submit button
    local submitBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    submitBtn:SetSize(80, 22)
    submitBtn:SetPoint("TOP", inputBox, "BOTTOM", -45, -8)
    submitBtn:SetText("Unlock")
    submitBtn:SetScript("OnClick", TryCode)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    closeBtn:SetSize(60, 22)
    closeBtn:SetPoint("LEFT", submitBtn, "RIGHT", 6, 0)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    -- Top-right X
    local xBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    xBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -5, -5)
    xBtn:SetScript("OnClick", function() panel:Hide() end)

    panel.inputBox  = inputBox
    panel.feedback  = feedback
    self.SecretPanel = panel

    -- If already unlocked, show unlocked state
    if T.db.secretUnlocked then
        title:SetText("|cFFFFD700★ Secret Languages — UNLOCKED|r")
        lore:SetText("|cFF00FF00Cross-faction languages (Orcish, Common) are\navailable in your language picker!|r")
        hint:SetText("")
        inputLabel:SetText("")
        inputBox:Hide()
        submitBtn:Hide()
        feedback:SetText("|cFFFFD700Both factions can now hear each other.|r")
    else
        inputBox:SetFocus()
    end
end

-- ============================================================
-- TOGGLE OPTIONS
-- ============================================================

function T:ToggleOptionsUI()
    if not self.OptionsFrame then
        self:CreateOptionsUI()
    end
    if self.OptionsFrame:IsShown() then
        self.OptionsFrame:Hide()
    else
        self.OptionsFrame:Show()
    end
end

-- ============================================================
-- INIT
-- ============================================================

local uiInit = CreateFrame("Frame")
uiInit:RegisterEvent("PLAYER_LOGIN")
uiInit:SetScript("OnEvent", function()
    C_Timer.After(1, function()
        T:CreateOptionsUI()
        T:CreateMinimapButton()
        T:CreateIMWindow()
    end)
end)
