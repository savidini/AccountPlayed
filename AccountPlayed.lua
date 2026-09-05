--------------------------------------------------
-- Account Played - Main Module
--------------------------------------------------
local _, addonTable = ...
local L = addonTable.L

AccountPlayed = AccountPlayed or {}
local AP = AccountPlayed

-- SavedVariables (must NOT be local)
AccountPlayedDB = AccountPlayedDB or {}
AccountPlayedPopupDB = AccountPlayedPopupDB or {}
if type(AccountPlayedPopupDB) ~= "table" then
    AccountPlayedPopupDB = {}
end

local POPUP_DEFAULTS = {
    width = 640,
    height = 380,
    point = "CENTER",
    x = 0,
    y = 0,
    useYears = false,
    activeTab = "class",
    chartMode = "bar",
    valueMode = "both",
}

local function EnsurePopupDefaults()
    for key, value in pairs(POPUP_DEFAULTS) do
        if AccountPlayedPopupDB[key] == nil then
            AccountPlayedPopupDB[key] = value
        end
    end
end

EnsurePopupDefaults()

-- Throttle tracking
local lastPlayedRequest = 0

-- Frame references
AP.mainFrame = CreateFrame("Frame")
AP.popupFrame = nil
AP.popupRows = {}
AP.characterRows = {}
AP.pieSlices = {}

--------------------------------------------------
-- Validation & Migration
--------------------------------------------------

if type(AccountPlayedDB) ~= "table" then
    print("|cffff0000" .. L["DB_CORRUPTED"] .. "|r")
    AccountPlayedDB = {}
end

local function MigrateOldData()
    for charKey, data in pairs(AccountPlayedDB) do
        if type(data) == "number" then
            AccountPlayedDB[charKey] = {
                time = data,
                class = "UNKNOWN",
                race = "UNKNOWN",
                faction = "UNKNOWN",
            }
        elseif type(data) == "table" then
            if data.class == nil then data.class = "UNKNOWN" end
            if data.race == nil then data.race = "UNKNOWN" end
            if data.faction == nil then data.faction = "UNKNOWN" end
        end
    end
end

--------------------------------------------------
-- Core Helpers
--------------------------------------------------

local function GetCharInfo()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
    return realm, name
end

local function GetCharKey(realm, name)
    return realm .. "-" .. name
end

local function ParseCharKey(key)
    local realm = key:match("^(.+)%-[^%-]+$")
    local name  = key:match("%-([^%-]+)$")
    return realm or key, name or key
end

local function GetUnknownLabel()
    return L["UNKNOWN"] or "Unknown"
end

local function GetLocalizedClass(classFile)
    if not classFile or classFile == "UNKNOWN" then
        return GetUnknownLabel()
    end
    return LOCALIZED_CLASS_NAMES_MALE[classFile] or classFile
end

local function GetLocalizedRace(raceFile, raceName)
    if not raceFile or raceFile == "UNKNOWN" then
        return GetUnknownLabel()
    end
    return raceName or raceFile
end

local function GetLocalizedFaction(factionFile, factionName)
    if not factionFile or factionFile == "UNKNOWN" then
        return GetUnknownLabel()
    end
    return factionName or factionFile
end

local function GetCurrentCharacterMetadata()
    local _, classFile = UnitClass("player")
    local raceName, raceFile = UnitRace("player")
    local factionFile, factionName = UnitFactionGroup("player")

    return {
        class = classFile or "UNKNOWN",
        race = raceFile or "UNKNOWN",
        raceName = raceName,
        faction = factionFile or "UNKNOWN",
        factionName = factionName or factionFile,
    }
end

local function SafeRequestTimePlayed()
    local now = GetTime()
    if now - lastPlayedRequest >= 10 then
        RequestTimePlayed()
        lastPlayedRequest = now
        return true
    end
    return false
end

--------------------------------------------------
-- Time Formatting
--------------------------------------------------

local function FormatTime(seconds)
    seconds = tonumber(seconds) or 0
    local hours = math.floor(seconds / 3600)
    local days = math.floor(hours / 24)
    local remHours = hours % 24
    return string.format("%d%s %d%s", days, L["TIME_UNIT_DAY"], remHours, L["TIME_UNIT_HOUR"])
end

local function FormatTimeSmart(seconds, useYears)
    seconds = tonumber(seconds) or 0
    local hours = seconds / 3600

    if useYears then
        local totalHours = math.floor(hours)
        local days = math.floor(totalHours / 24)
        return days > 0 and string.format("%d%s", days, L["TIME_UNIT_DAY"]) or string.format("%d%s", totalHours, L["TIME_UNIT_HOUR"])
    else
        return string.format("%d%s", math.floor(hours), L["TIME_UNIT_HOUR"])
    end
end

local function FormatTimeDetailed(seconds, useYears)
    seconds = tonumber(seconds) or 0
    local hours = seconds / 3600

    if useYears then
        local totalHours = math.floor(hours)
        local days = math.floor(totalHours / 24)
        local remHours = totalHours % 24
        return days > 0 and string.format("%d%s %d%s", days, L["TIME_UNIT_DAY"], remHours, L["TIME_UNIT_HOUR"]) or string.format("%d%s", totalHours, L["TIME_UNIT_HOUR"])
    else
        local h = math.floor(hours)
        local m = math.floor((seconds % 3600) / 60)
        return string.format("%d%s %d%s", h, L["TIME_UNIT_HOUR"], m, L["TIME_UNIT_MINUTE"])
    end
end

local function FormatTimeTotal(seconds, useYears)
    seconds = tonumber(seconds) or 0
    local hours = seconds / 3600

    if useYears and hours >= 9000 then
        local days = math.floor(hours / 24)
        local years = math.floor(days / 365)
        local remDays = days % 365
        return years > 0 and string.format("%d%s %d%s", years, L["TIME_UNIT_YEAR"], remDays, L["TIME_UNIT_DAY"]) or string.format("%d%s", days, L["TIME_UNIT_DAY"])
    end
    return FormatTimeSmart(seconds, useYears)
end

--------------------------------------------------
-- Data Aggregation
--------------------------------------------------

local function GetAccountTotal()
    local total = 0
    for _, data in pairs(AccountPlayedDB) do
        if type(data) == "table" and type(data.time) == "number" then
            total = total + data.time
        end
    end
    return total
end

local function GetTrackedCharacterCount()
    local count = 0
    for _, data in pairs(AccountPlayedDB) do
        if type(data) == "table" and type(data.time) == "number" then
            count = count + 1
        end
    end
    return count
end

local function GetClassTotals()
    local totals, accountTotal = {}, 0
    for _, data in pairs(AccountPlayedDB) do
        if type(data) == "table" and type(data.time) == "number" then
            local class = data.class or "UNKNOWN"
            totals[class] = (totals[class] or 0) + data.time
            accountTotal = accountTotal + data.time
        end
    end
    return totals, accountTotal
end

local function GetTotalsByField(field)
    local totals, accountTotal = {}, 0
    for _, data in pairs(AccountPlayedDB) do
        if type(data) == "table" and type(data.time) == "number" then
            local key = data[field] or "UNKNOWN"
            if key == "" then key = "UNKNOWN" end
            totals[key] = (totals[key] or 0) + data.time
            accountTotal = accountTotal + data.time
        end
    end
    return totals, accountTotal
end

local function GetAllCharacters()
    local chars = {}
    for charKey, data in pairs(AccountPlayedDB) do
        if type(data) == "table" and type(data.time) == "number" then
            local realm, name = ParseCharKey(charKey)
            table.insert(chars, {
                key = charKey,
                name = name,
                realm = realm,
                time = data.time,
                class = data.class or "UNKNOWN",
                race = data.race or "UNKNOWN",
                raceName = data.raceName,
                faction = data.faction or "UNKNOWN",
                factionName = data.factionName,
            })
        end
    end
    table.sort(chars, function(a, b)
        if a.time == b.time then
            return a.key < b.key
        end
        return a.time > b.time
    end)
    return chars
end

local function GetCharactersByClass(className)
    local chars = {}
    for _, char in ipairs(GetAllCharacters()) do
        if char.class == className then
            table.insert(chars, char)
        end
    end
    return chars
end

local function GetCharactersByGroup(groupKind, groupKey)
    if groupKind == "class" then
        return GetCharactersByClass(groupKey)
    end

    local chars = {}
    local field = groupKind == "race" and "race" or groupKind == "faction" and "faction" or nil
    if not field then return chars end

    for _, char in ipairs(GetAllCharacters()) do
        if (char[field] or "UNKNOWN") == groupKey then
            table.insert(chars, char)
        end
    end
    return chars
end

--------------------------------------------------
-- Debug
--------------------------------------------------

local function DebugListCharacters()
    print("|cffff0000" .. L["DEBUG_HEADER"] .. "|r")
    for charKey, data in pairs(AccountPlayedDB) do
        local time, class, race, faction
        if type(data) == "table" then
            time = data.time or 0
            class = data.class or "UNKNOWN"
            race = data.race or "UNKNOWN"
            faction = data.faction or "UNKNOWN"
        else
            time, class, race, faction = data, "UNKNOWN", "UNKNOWN", "UNKNOWN"
        end
        print(string.format(" |cffffff00 - %s : %s (%s / %s / %s)|r", charKey, FormatTime(time), class, race, faction))
    end
end

SLASH_ACCOUNTPLAYEDDEBUG1 = "/apdebug"
SlashCmdList.ACCOUNTPLAYEDDEBUG = DebugListCharacters

--------------------------------------------------
-- Delete Character Command
--------------------------------------------------

StaticPopupDialogs["ACCOUNTPLAYED_CONFIRM_DELETE"] = {
    text          = "",
    button1       = DELETE,
    button2       = CANCEL,
    OnAccept      = function(self, data)
        if not data or not data.foundKey then return end
        AccountPlayedDB[data.foundKey] = nil
        print("|cff00ff00" .. string.format(L["CMD_DELETE_SUCCESS"], data.foundKey) .. "|r")
        if AP.popupFrame and AP.popupFrame:IsShown() then
            AP.popupFrame:UpdateDisplay()
        end
    end,
    timeout       = 0,
    whileDead     = true,
    hideOnEscape  = true,
    preferredIndex = 3,
}

local function ConfirmDeleteKey(foundKey)
    StaticPopupDialogs["ACCOUNTPLAYED_CONFIRM_DELETE"].text =
        string.format(L["CMD_DELETE_CONFIRM"], foundKey)
    StaticPopup_Show("ACCOUNTPLAYED_CONFIRM_DELETE", nil, nil, { foundKey = foundKey })
end

local function DeleteCharacter(input)
    input = input and input:match("^%s*(.-)%s*$") or ""

    if input == "" then
        print("|cffff9900" .. L["CMD_DELETE_USAGE"] .. "|r")
        return
    end

    local charName, realmName = input:match("^([^%-]+)%-(.+)$")
    if not charName or not realmName then
        print("|cffff9900" .. L["CMD_DELETE_USAGE"] .. "|r")
        return
    end

    local targetKey = realmName .. "-" .. charName

    local foundKey = nil
    local lowerTarget = targetKey:lower()
    for dbKey in pairs(AccountPlayedDB) do
        if dbKey:lower() == lowerTarget then
            foundKey = dbKey
            break
        end
    end

    if not foundKey then
        print("|cffff0000" .. string.format(L["CMD_DELETE_NOT_FOUND"], input) .. "|r")
        return
    end

    ConfirmDeleteKey(foundKey)
end

SLASH_ACCOUNTPLAYEDDELETE1 = "/apdelete"
SlashCmdList.ACCOUNTPLAYEDDELETE = DeleteCharacter

--------------------------------------------------
-- Character Management Panel
--------------------------------------------------

AP.charPanelClass = nil
AP.charPanelGroup = nil
AP.charPanelState = nil

local CPANEL_W        = 280
local CPANEL_ROW_H    = 22
local CPANEL_HEADER_H = 28
local CPANEL_PAD      = 6

local function CreateCharPanel()
    if AP.charPanel then return AP.charPanel end

    local p = CreateFrame("Frame", "AccountPlayedCharPanel", UIParent, "BackdropTemplate")
    p:SetWidth(CPANEL_W)
    p:SetHeight(CPANEL_HEADER_H + CPANEL_PAD)
    p:SetFrameStrata("DIALOG")
    p:SetFrameLevel(110)
    p:SetClampedToScreen(true)

    p:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    p:SetBackdropColor(0.05, 0.05, 0.05, 0.92)

    p.titleText = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.titleText:SetPoint("TOPLEFT",  p, "TOPLEFT",  12, -10)
    p.titleText:SetPoint("TOPRIGHT", p, "TOPRIGHT", -26, -10)
    p.titleText:SetJustifyH("LEFT")

    local closeBtn = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        p:Hide()
        AP.charPanelClass = nil
        AP.charPanelGroup = nil
        AP.charPanelState = nil
    end)

    local div = p:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  p, "TOPLEFT",  10, -(CPANEL_HEADER_H - 2))
    div:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -(CPANEL_HEADER_H - 2))
    div:SetColorTexture(0.4, 0.4, 0.4, 0.8)

    p.charRows = {}
    for i = 1, 20 do
        local yOff = -(CPANEL_HEADER_H + CPANEL_PAD + (i - 1) * CPANEL_ROW_H)
        local row  = CreateFrame("Frame", nil, p)
        row:SetHeight(CPANEL_ROW_H)
        row:SetPoint("TOPLEFT",  p, "TOPLEFT",  10, yOff)
        row:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, yOff)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0)

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -126, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)

        row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.timeText:SetPoint("RIGHT", row, "RIGHT", -56, 0)
        row.timeText:SetWidth(72)
        row.timeText:SetJustifyH("RIGHT")
        row.timeText:SetTextColor(0.75, 0.75, 0.75)

        local trashBtn = CreateFrame("Button", nil, row)
        trashBtn:SetSize(44, 18)
        trashBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

        local trashLabel = trashBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        trashLabel:SetAllPoints()
        trashLabel:SetText("|cffff4040" .. DELETE .. "|r")
        trashLabel:SetJustifyH("CENTER")

        trashBtn:SetWidth(trashLabel:GetStringWidth() + 8)

        trashBtn:SetScript("OnEnter", function()
            row.bg:SetColorTexture(1, 0.25, 0.25, 0.15)
            GameTooltip:SetOwner(trashBtn, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["CHAR_PANEL_REMOVE_TIP"], 1, 0.35, 0.35)
            GameTooltip:Show()
        end)
        trashBtn:SetScript("OnLeave", function()
            row.bg:SetColorTexture(1, 1, 1, 0)
            GameTooltip:Hide()
        end)
        trashBtn:SetScript("OnClick", function()
            if row.charKey then
                ConfirmDeleteKey(row.charKey)
            end
        end)

        row.trashBtn = trashBtn
        row:Hide()
        p.charRows[i] = row
    end

    p:Hide()
    AP.charPanel = p

    table.insert(UISpecialFrames, "AccountPlayedCharPanel")

    return p
end

function AP.ShowGroupCharPanel(groupKind, groupKey, label, color, forceShow, anchorRow)
    local p = CreateCharPanel()
    local panelKey = groupKind .. ":" .. tostring(groupKey or "")

    if not forceShow and AP.charPanelGroup == panelKey and p:IsShown() then
        p:Hide()
        AP.charPanelClass = nil
        AP.charPanelGroup = nil
        AP.charPanelState = nil
        return
    end

    local chars = GetCharactersByGroup(groupKind, groupKey)
    if #chars == 0 then
        p:Hide()
        AP.charPanelClass = nil
        AP.charPanelGroup = nil
        AP.charPanelState = nil
        return
    end

    AP.charPanelClass = groupKind == "class" and groupKey or nil
    AP.charPanelGroup = panelKey
    AP.charPanelState = {
        kind = groupKind,
        key = groupKey,
        label = label,
        color = color,
    }

    if anchorRow then
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", 6, 0)
    elseif not p:IsShown() then
        p:ClearAllPoints()
        if AP.popupFrame and AP.popupFrame:IsShown() then
            p:SetPoint("TOPLEFT", AP.popupFrame, "TOPRIGHT", 4, 0)
        else
            p:SetPoint("CENTER")
        end
    end

    color = color or { r = 1, g = 1, b = 1 }
    p.titleText:SetText(label or groupKey or GetUnknownLabel())
    p.titleText:SetTextColor(color.r, color.g, color.b)

    for i, row in ipairs(p.charRows) do
        local char = chars[i]
        if char then
            local timeStr = FormatTimeDetailed(char.time, AccountPlayedPopupDB.useYears)
            local classColor = RAID_CLASS_COLORS[char.class] or { r = 1, g = 1, b = 1 }
            row.nameText:SetText(char.name)
            row.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
            row.timeText:SetText(timeStr)
            row.charKey = char.key
            row:Show()
        else
            row.charKey = nil
            row:Hide()
        end
    end

    p:SetHeight(CPANEL_HEADER_H + CPANEL_PAD + #chars * CPANEL_ROW_H + CPANEL_PAD)
    p:Show()
end

function AP.ShowCharPanel(className, forceShow, anchorRow)
    local color = RAID_CLASS_COLORS[className] or { r = 1, g = 1, b = 1 }
    AP.ShowGroupCharPanel("class", className, GetLocalizedClass(className), color, forceShow, anchorRow)
end

--------------------------------------------------
-- UI Components
--------------------------------------------------

local TAB_ORDER = {
    { key = "class",      labelKey = "TAB_CLASS" },
    { key = "characters", labelKey = "TAB_CHARACTERS" },
    { key = "race",       labelKey = "TAB_RACE" },
    { key = "faction",    labelKey = "TAB_FACTION" },
}

local VALID_TABS = {}
for _, tab in ipairs(TAB_ORDER) do
    VALID_TABS[tab.key] = true
end

local function GetActiveTab()
    local activeTab = AccountPlayedPopupDB.activeTab or "class"
    if not VALID_TABS[activeTab] then
        activeTab = "class"
        AccountPlayedPopupDB.activeTab = activeTab
    end
    return activeTab
end

local function GetChartMode()
    local mode = AccountPlayedPopupDB.chartMode or "bar"
    if mode ~= "bar" and mode ~= "pie" then
        mode = "bar"
        AccountPlayedPopupDB.chartMode = mode
    end
    return mode
end

local GROUP_FIELDS = {
    class = "class",
    race = "race",
    faction = "faction",
}

local ROW_H             = 24
local CHARACTER_ROW_H   = 25
local PIE_SLICE_COUNT   = 240
local PIE_FRAME_H       = 168
local PIE_RADIUS        = 58
local PIE_SEGMENT_W     = 4
local PIE_SEGMENT_H     = 14
local PIE_INNER_RADIUS  = PIE_RADIUS - PIE_SEGMENT_H / 2
local PIE_OUTER_RADIUS  = PIE_RADIUS + PIE_SEGMENT_H / 2
local LABEL_COL_W       = 150
local VALUE_COL_W       = 110
local RIGHT_MARGIN      = 4
local BAR_RIGHT_OFS     = -(VALUE_COL_W + 8 + RIGHT_MARGIN)

local RACE_PALETTE = {
    { r = 0.36, g = 0.67, b = 0.92 },
    { r = 0.55, g = 0.82, b = 0.48 },
    { r = 0.93, g = 0.66, b = 0.31 },
    { r = 0.82, g = 0.50, b = 0.86 },
    { r = 0.90, g = 0.46, b = 0.46 },
    { r = 0.45, g = 0.84, b = 0.74 },
    { r = 0.78, g = 0.76, b = 0.42 },
    { r = 0.66, g = 0.58, b = 0.95 },
}

local function CopyColor(color)
    if not color then return { r = 1, g = 1, b = 1 } end
    return { r = color.r or 1, g = color.g or 1, b = color.b or 1 }
end

local function GetFactionColor(faction)
    if faction == "Alliance" then
        return { r = 0.32, g = 0.55, b = 1.00 }
    elseif faction == "Horde" then
        return { r = 0.93, g = 0.20, b = 0.18 }
    end
    return { r = 0.55, g = 0.55, b = 0.55 }
end

local function GetGroupColor(groupKind, groupKey, index)
    if groupKind == "class" then
        return CopyColor(RAID_CLASS_COLORS[groupKey])
    elseif groupKind == "faction" then
        return GetFactionColor(groupKey)
    elseif groupKey == "UNKNOWN" then
        return { r = 0.55, g = 0.55, b = 0.55 }
    end
    -- Keep a race's color stable when playtime changes its rank.
    local hash = 0
    for i = 1, #groupKey do
        hash = (hash * 31 + string.byte(groupKey, i)) % 65521
    end
    return CopyColor(RACE_PALETTE[hash % #RACE_PALETTE + 1])
end

local function GetGroupLabel(groupKind, groupKey, data)
    if groupKind == "class" then
        return GetLocalizedClass(groupKey)
    elseif groupKind == "race" then
        return GetLocalizedRace(groupKey, data and data.raceName)
    elseif groupKind == "faction" then
        return GetLocalizedFaction(groupKey, data and data.factionName)
    end
    return groupKey or GetUnknownLabel()
end

local function BuildDistribution(groupKind)
    local field = GROUP_FIELDS[groupKind]
    local entriesByKey, accountTotal = {}, 0
    if not field then return {}, 0 end

    for _, data in pairs(AccountPlayedDB) do
        if type(data) == "table" and type(data.time) == "number" then
            local groupKey = data[field] or "UNKNOWN"
            if groupKey == "" then groupKey = "UNKNOWN" end

            local entry = entriesByKey[groupKey]
            if not entry then
                entry = {
                    kind = groupKind,
                    key = groupKey,
                    label = GetGroupLabel(groupKind, groupKey, data),
                    time = 0,
                    count = 0,
                }
                entriesByKey[groupKey] = entry
            elseif groupKind ~= "class" and (entry.label == groupKey or entry.label == GetUnknownLabel()) then
                entry.label = GetGroupLabel(groupKind, groupKey, data)
            end

            entry.time = entry.time + data.time
            entry.count = entry.count + 1
            accountTotal = accountTotal + data.time
        end
    end

    local entries = {}
    for _, entry in pairs(entriesByKey) do
        table.insert(entries, entry)
    end

    table.sort(entries, function(a, b)
        if a.time == b.time then
            return a.label < b.label
        end
        return a.time > b.time
    end)

    for i, entry in ipairs(entries) do
        entry.color = GetGroupColor(groupKind, entry.key, i)
    end

    return entries, accountTotal
end

local function FormatDistributionValue(seconds, accountTotal)
    local percent = accountTotal > 0 and (seconds / accountTotal) * 100 or 0
    local mode = AccountPlayedPopupDB.valueMode or "both"

    if mode == "days" then
        return FormatTimeSmart(seconds, AccountPlayedPopupDB.useYears)
    elseif mode == "percent" then
        return string.format("%4.1f%%", percent)
    end

    return string.format("%4.1f%% %s", percent, FormatTimeSmart(seconds, AccountPlayedPopupDB.useYears))
end

local function GetTrackedCountText()
    return string.format(L["TRACKED_COUNT"] or "%d characters tracked", GetTrackedCharacterCount())
end

local function FormatFooterText(accountTotal)
    return L["TOTAL"] .. FormatTimeTotal(accountTotal, AccountPlayedPopupDB.useYears) .. "  -  " .. GetTrackedCountText()
end

local function PrintCharactersForEntry(entry)
    if not entry then return end

    local chars = GetCharactersByGroup(entry.kind, entry.key)
    if #chars == 0 then return end

    print("|cff00ff00" .. entry.label .. ":|r")
    for _, char in ipairs(chars) do
        local timeStr = FormatTimeDetailed(char.time, AccountPlayedPopupDB.useYears)
        local color = RAID_CLASS_COLORS[char.class] or { r = 1, g = 1, b = 1 }
        print(string.format("  |cff%02x%02x%02x%s|r - %s",
            math.floor(color.r * 255), math.floor(color.g * 255), math.floor(color.b * 255),
            char.name, timeStr))
    end
end

local function AddEntryTooltipLines(entry)
    local chars = GetCharactersByGroup(entry.kind, entry.key)
    for _, char in ipairs(chars) do
        local timeStr = FormatTimeDetailed(char.time, AccountPlayedPopupDB.useYears)
        local color = RAID_CLASS_COLORS[char.class] or { r = 1, g = 1, b = 1 }
        GameTooltip:AddDoubleLine(char.name, timeStr, color.r, color.g, color.b, 1, 1, 1)
    end
end

local function ShowEntryTooltip(owner, entry)
    if not entry then return end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(entry.label, 1, 1, 1)
    GameTooltip:AddDoubleLine(
        string.format(L["GROUP_CHARACTER_COUNT"] or "%d characters", entry.count or 0),
        FormatTimeDetailed(entry.time, AccountPlayedPopupDB.useYears),
        0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddLine(" ")
    AddEntryTooltipLines(entry)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["CLICK_TO_PRINT"], 0.5, 0.5, 0.5)
    GameTooltip:AddLine(L["CHAR_PANEL_RIGHT_CLICK"], 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function HighlightPieEntry(frame, entry)
    if not frame or not frame.pieEntries then return end
    for _, slice in ipairs(AP.pieSlices) do
        slice:SetAlpha((not entry or slice.entry == entry) and 1 or 0.3)
    end
    for _, row in ipairs(AP.popupRows) do
        row.highlight:SetShown(entry ~= nil and row.entry == entry)
    end
    local text = frame.pieFrame.centerText
    if entry then
        text:SetText(string.format("%.1f%%\n%s", entry.pieShare * 100,
            FormatTimeSmart(entry.time, AccountPlayedPopupDB.useYears)))
        text:SetTextColor(entry.color.r, entry.color.g, entry.color.b)
    else
        text:SetText(FormatTimeTotal(frame.pieAccountTotal, AccountPlayedPopupDB.useYears))
        text:SetTextColor(1, 0.82, 0)
    end
end

local function CreateDistributionRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.07)
    row.highlight:Hide()

    row.swatch = row:CreateTexture(nil, "ARTWORK")
    row.swatch:SetSize(10, 10)
    row.swatch:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.swatch:Hide()

    row.classText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.classText:SetPoint("LEFT", 0, 0)
    row.classText:SetWidth(LABEL_COL_W)
    row.classText:SetJustifyH("LEFT")
    row.classText:SetWordWrap(false)
    row.labelText = row.classText

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("LEFT",  row.classText, "RIGHT", 8, 0)
    row.bar:SetPoint("RIGHT", row, "RIGHT", BAR_RIGHT_OFS, 0)
    row.bar:SetHeight(ROW_H - 6)
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetValue(0)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

    row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.bg:SetAllPoints()
    row.bar.bg:SetColorTexture(0, 0, 0, 0.35)

    row.valueText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.valueText:SetWidth(VALUE_COL_W)
    row.valueText:SetPoint("RIGHT", row, "RIGHT", -RIGHT_MARGIN, 0)
    row.valueText:SetJustifyH("RIGHT")
    row.valueText:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        if self.entry then
            HighlightPieEntry(AP.popupFrame, self.entry)
            ShowEntryTooltip(self, self.entry)
        end
    end)

    row:SetScript("OnLeave", function(self)
        HighlightPieEntry(AP.popupFrame, nil)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)

    row:SetScript("OnClick", function(self, button)
        if not self.entry then return end

        if button == "RightButton" then
            GameTooltip:Hide()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            AP.ShowGroupCharPanel(self.entry.kind, self.entry.key, self.entry.label, self.entry.color, false, self)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            PrintCharactersForEntry(self.entry)
        end
    end)

    return row
end

local function CreateCharacterRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(CHARACTER_ROW_H)
    row:EnableMouse(true)

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.07)
    row.highlight:Hide()

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.nameText:SetPoint("RIGHT", row, "RIGHT", -330, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.metaText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.metaText:SetPoint("LEFT", row, "RIGHT", -322, 0)
    row.metaText:SetWidth(170)
    row.metaText:SetJustifyH("LEFT")
    row.metaText:SetTextColor(0.75, 0.75, 0.75)
    row.metaText:SetWordWrap(false)

    row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.timeText:SetPoint("RIGHT", row, "RIGHT", -58, 0)
    row.timeText:SetWidth(88)
    row.timeText:SetJustifyH("RIGHT")
    row.timeText:SetTextColor(1, 1, 1)
    row.valueText = row.timeText

    local trashBtn = CreateFrame("Button", nil, row)
    trashBtn:SetSize(50, 20)
    trashBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    local trashLabel = trashBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trashLabel:SetAllPoints()
    trashLabel:SetText("|cffff5a5a" .. DELETE .. "|r")
    trashLabel:SetJustifyH("CENTER")
    trashBtn:SetWidth(trashLabel:GetStringWidth() + 8)

    trashBtn:SetScript("OnEnter", function()
        row.highlight:SetColorTexture(1, 0.25, 0.25, 0.12)
        row.highlight:Show()
        GameTooltip:SetOwner(trashBtn, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["CHAR_PANEL_REMOVE_TIP"], 1, 0.35, 0.35)
        GameTooltip:Show()
    end)
    trashBtn:SetScript("OnLeave", function()
        row.highlight:Hide()
        GameTooltip:Hide()
    end)
    trashBtn:SetScript("OnClick", function()
        if row.charKey then
            ConfirmDeleteKey(row.charKey)
        end
    end)

    row.trashBtn = trashBtn

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        if self.charData then
            local char = self.charData
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(char.name, 1, 1, 1)
            GameTooltip:AddDoubleLine(REALM or "Realm", char.realm, 0.75, 0.75, 0.75, 1, 1, 1)
            GameTooltip:AddDoubleLine(CLASS or "Class", GetLocalizedClass(char.class), 0.75, 0.75, 0.75, 1, 1, 1)
            GameTooltip:AddDoubleLine(RACE or "Race", GetLocalizedRace(char.race, char.raceName), 0.75, 0.75, 0.75, 1, 1, 1)
            GameTooltip:AddDoubleLine(FACTION or "Faction", GetLocalizedFaction(char.faction, char.factionName), 0.75, 0.75, 0.75, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["TOTAL"], FormatTimeDetailed(char.time, AccountPlayedPopupDB.useYears), 0.75, 0.75, 0.75, 1, 1, 1)
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)

    row:Hide()
    return row
end

local function UpdateScrollBarVisibility(frame)
    local sf = frame.scrollFrame
    local sb = sf and (sf.ScrollBar or sf.scrollBar)
    if not sb then return end

    if sf:GetVerticalScrollRange() > 0 then
        sb:Show()
    else
        sb:Hide()
        sf:SetVerticalScroll(0)
    end
end

local function EnsureDistributionRows(frame, count)
    for i = #AP.popupRows + 1, count do
        local row = CreateDistributionRow(frame.content)
        row:Hide()
        AP.popupRows[i] = row
    end
end

local function EnsureCharacterRows(frame, count)
    for i = #AP.characterRows + 1, count do
        local row = CreateCharacterRow(frame.content)
        row:Hide()
        AP.characterRows[i] = row
    end
end

local function HideDistributionRows()
    for _, row in ipairs(AP.popupRows) do
        row.entry = nil
        row.className = nil
        row:Hide()
    end
end

local function HideCharacterRows()
    for _, row in ipairs(AP.characterRows) do
        row.charKey = nil
        row.charData = nil
        row:Hide()
    end
end

local function EnsurePieSlices(frame)
    if frame.pieReady then return end

    for i = 1, PIE_SLICE_COUNT do
        local slice = frame.pieFrame:CreateTexture(nil, "ARTWORK")
        slice:SetTexture("Interface\\Buttons\\WHITE8X8")
        slice:SetSize(PIE_SEGMENT_W, PIE_SEGMENT_H)
        slice:SetVertexColor(0.2, 0.2, 0.2, 0.15)
        slice:Hide()
        AP.pieSlices[i] = slice
    end

    frame.pieReady = true
end

local function HidePie(frame)
    if frame.pieFrame then
        frame.pieFrame:Hide()
    end
    if frame.pieHitFrame then
        frame.pieHitFrame:SetScript("OnUpdate", nil)
        frame.pieHitFrame.entry = nil
        frame.pieHitFrame:Hide()
    end
    frame.pieEntries = nil
    frame.pieAccountTotal = nil
    for _, slice in ipairs(AP.pieSlices) do
        slice:Hide()
    end
end

local function GetPositiveAngle(dx, dy)
    local angle
    if dx == 0 then
        angle = dy >= 0 and math.pi / 2 or math.pi * 1.5
    else
        angle = math.atan(dy / dx)
        if dx < 0 then
            angle = angle + math.pi
        elseif dy < 0 then
            angle = angle + math.pi * 2
        end
    end
    return angle
end

local function GetEntryAtPieRatio(entries, ratio)
    if not entries or #entries == 0 then return nil end

    local cumulative = 0
    for _, entry in ipairs(entries) do
        cumulative = cumulative + (entry.pieShare or 0)
        if (entry.pieShare or 0) > 0 and ratio < cumulative then
            return entry
        end
    end

    return entries[#entries]
end

local function GetPieEntryAtCursor(frame)
    if not frame.pieAnchor or not frame.pieEntries then return nil end

    local scale = frame.pieAnchor:GetEffectiveScale() or UIParent:GetEffectiveScale() or 1
    local cursorX, cursorY = GetCursorPosition()
    local anchorX, anchorY = frame.pieAnchor:GetCenter()
    if not cursorX or not cursorY or not anchorX or not anchorY then return nil end

    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local dx = cursorX - anchorX
    local dy = cursorY - anchorY
    local dist = (dx * dx + dy * dy) ^ 0.5
    if dist < PIE_INNER_RADIUS or dist > PIE_OUTER_RADIUS then
        return nil
    end

    local angle = GetPositiveAngle(dx, dy)
    return GetEntryAtPieRatio(frame.pieEntries, angle / (math.pi * 2))
end

local function UpdatePieHover(hitFrame)
    local parent = hitFrame.ownerFrame or hitFrame:GetParent()
    local entry = GetPieEntryAtCursor(parent)

    if entry ~= hitFrame.entry then
        hitFrame.entry = entry
        HighlightPieEntry(parent, entry)
        if entry then
            ShowEntryTooltip(hitFrame, entry)
        else
            GameTooltip:Hide()
        end
    elseif entry and not GameTooltip:IsShown() then
        ShowEntryTooltip(hitFrame, entry)
    end
end

local function RenderPie(frame, entries, accountTotal)
    EnsurePieSlices(frame)

    if accountTotal <= 0 or #entries == 0 then
        HidePie(frame)
        return 0
    end

    frame.pieFrame:Show()
    frame.pieEntries = entries
    frame.pieAccountTotal = accountTotal

    frame.pieFrame.centerText:SetText(FormatTimeTotal(accountTotal, AccountPlayedPopupDB.useYears))
    frame.pieFrame.centerText:SetTextColor(1, 0.82, 0)

    local currentIndex = 1
    local currentEnd = entries[1].time / accountTotal

    for _, entry in ipairs(entries) do
        entry.pieShare = entry.time / accountTotal
    end

    for i, slice in ipairs(AP.pieSlices) do
        local ratio = (i - 0.5) / PIE_SLICE_COUNT
        while currentIndex < #entries and ratio > currentEnd do
            currentIndex = currentIndex + 1
            currentEnd = currentEnd + entries[currentIndex].time / accountTotal
        end

        local entry = entries[currentIndex]
        slice.entry = entry
        slice:SetAlpha(1)
        local color = entry and entry.color or { r = 0.4, g = 0.4, b = 0.4 }
        local angle = ratio * math.pi * 2
        local x = math.cos(angle) * PIE_RADIUS
        local y = math.sin(angle) * PIE_RADIUS

        slice:ClearAllPoints()
        slice:SetPoint("CENTER", frame.pieAnchor, "CENTER", x, y)
        slice:SetSize(PIE_SEGMENT_W, PIE_SEGMENT_H)
        if slice.SetRotation then
            slice:SetRotation(angle + math.pi / 2)
        end
        slice:SetVertexColor(color.r, color.g, color.b, 0.95)
        slice:Show()
    end

    if frame.pieHitFrame then
        frame.pieHitFrame:SetSize(PIE_OUTER_RADIUS * 2, PIE_OUTER_RADIUS * 2)
        frame.pieHitFrame:Show()
    end

    return PIE_FRAME_H
end

local function UpdateTabButtons(frame)
    local activeTab = GetActiveTab()
    for key, button in pairs(frame.tabs) do
        button.active = key == activeTab
        if key == activeTab then
            button.bg:SetColorTexture(0.95, 0.72, 0.25, 0.95)
            button.text:SetTextColor(0.05, 0.05, 0.05)
        else
            button.bg:SetColorTexture(0.12, 0.12, 0.12, 0.92)
            button.text:SetTextColor(0.86, 0.86, 0.86)
        end
    end
end

local function UpdateChartButtons(frame)
    local isDistribution = GetActiveTab() ~= "characters"
    local mode = GetChartMode()

    for key, button in pairs(frame.chartButtons) do
        button.active = key == mode
        if isDistribution then
            button:Show()
        else
            button:Hide()
        end

        if key == mode then
            button.bg:SetColorTexture(0.28, 0.58, 0.90, 0.95)
            button.text:SetTextColor(1, 1, 1)
        else
            button.bg:SetColorTexture(0.10, 0.10, 0.10, 0.92)
            button.text:SetTextColor(0.80, 0.80, 0.80)
        end
    end
end

local function PositionContentRow(row, frame, index, yOffset, height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -(yOffset + (index - 1) * height))
    row:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)
    row:SetHeight(height)
end

local function UpdateDistributionRow(row, entry, accountTotal, topTime, usePie)
    row.entry = entry
    row.className = entry.kind == "class" and entry.key or nil
    row.classText:SetText(entry.label)
    row.classText:SetTextColor(entry.color.r, entry.color.g, entry.color.b)
    row.valueText:SetText(FormatDistributionValue(entry.time, accountTotal))
    row.valueText:SetWidth(math.max(VALUE_COL_W, row.valueText:GetStringWidth() + 8))
    row.bar:ClearAllPoints()
    row.bar:SetPoint("LEFT", row.classText, "RIGHT", 8, 0)
    row.bar:SetPoint("RIGHT", row.valueText, "LEFT", -8, 0)

    row.classText:ClearAllPoints()
    if usePie then
        row.swatch:SetColorTexture(entry.color.r, entry.color.g, entry.color.b, 1)
        row.swatch:Show()
        row.classText:SetPoint("LEFT", row.swatch, "RIGHT", 8, 0)
        row.classText:SetWidth(LABEL_COL_W - 18)
        row.bar:Hide()
    else
        row.swatch:Hide()
        row.classText:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.classText:SetWidth(LABEL_COL_W)
        row.bar:Show()
        row.bar:SetValue(accountTotal > 0 and entry.time / accountTotal or 0)
        row.bar:SetStatusBarColor(entry.color.r, entry.color.g, entry.color.b)
    end

    row:Show()
end

local function UpdateDistributionView(frame, activeTab)
    local entries, accountTotal = BuildDistribution(activeTab)
    local usePie = GetChartMode() == "pie"
    local chartHeight = 0

    HideCharacterRows()
    frame.emptyText:Hide()

    if accountTotal == 0 or #entries == 0 then
        HidePie(frame)
        EnsureDistributionRows(frame, 1)
        HideDistributionRows()
        local row = AP.popupRows[1]
        PositionContentRow(row, frame, 1, 0, ROW_H)
        row.entry = nil
        row.classText:SetText(L["NO_DATA"])
        row.classText:SetTextColor(0.8, 0.8, 0.8)
        row.valueText:SetText("")
        row.swatch:Hide()
        row.bar:Hide()
        row:Show()
        frame.content:SetHeight(ROW_H)
        frame.totalRow:SetText(FormatFooterText(0))
        return
    end

    if usePie then
        chartHeight = RenderPie(frame, entries, accountTotal)
    else
        HidePie(frame)
    end

    EnsureDistributionRows(frame, #entries)
    local topTime = entries[1].time
    for i, row in ipairs(AP.popupRows) do
        local entry = entries[i]
        if entry then
            PositionContentRow(row, frame, i, chartHeight, ROW_H)
            UpdateDistributionRow(row, entry, accountTotal, topTime, usePie)
        else
            row.entry = nil
            row:Hide()
        end
    end

    frame.content:SetHeight(chartHeight + #entries * ROW_H)
    frame.totalRow:SetText(FormatFooterText(accountTotal))
end

local function UpdateCharacterRow(row, char)
    local classColor = RAID_CLASS_COLORS[char.class] or { r = 1, g = 1, b = 1 }
    local meta = string.format("%s / %s / %s",
        GetLocalizedClass(char.class),
        GetLocalizedRace(char.race, char.raceName),
        GetLocalizedFaction(char.faction, char.factionName))

    row.charKey = char.key
    row.charData = char
    row.nameText:SetText(char.name .. " - " .. char.realm)
    row.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    row.metaText:SetText(meta)
    row.timeText:SetText(FormatTimeDetailed(char.time, AccountPlayedPopupDB.useYears))
    row:Show()
end

local function UpdateCharacterView(frame)
    local chars = GetAllCharacters()
    local accountTotal = GetAccountTotal()

    HideDistributionRows()
    HidePie(frame)
    frame.emptyText:Hide()

    if #chars == 0 then
        HideCharacterRows()
        frame.emptyText:SetText(L["NO_DATA"])
        frame.emptyText:Show()
        frame.content:SetHeight(ROW_H)
        frame.totalRow:SetText(FormatFooterText(0))
        return
    end

    EnsureCharacterRows(frame, #chars)
    for i, row in ipairs(AP.characterRows) do
        local char = chars[i]
        if char then
            PositionContentRow(row, frame, i, 0, CHARACTER_ROW_H)
            UpdateCharacterRow(row, char)
        else
            row.charKey = nil
            row.charData = nil
            row:Hide()
        end
    end

    frame.content:SetHeight(#chars * CHARACTER_ROW_H)
    frame.totalRow:SetText(FormatFooterText(accountTotal))
end

local function CreateFlatButton(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetColorTexture(0.12, 0.12, 0.12, 0.92)

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetAllPoints()
    button.text:SetJustifyH("CENTER")
    button.text:SetText(label)
    button.text:SetWordWrap(false)
    button.text:SetShadowColor(0, 0, 0, 0)
    button.text:SetShadowOffset(0, 0)
    local fontPath, _, fontFlags = GameFontNormal:GetFont()
    if fontPath then
        button.text:SetFont(fontPath, 12, fontFlags or "")
    end

    button:SetScript("OnEnter", function(self)
        if not self.active then
            self.bg:SetColorTexture(0.18, 0.18, 0.18, 0.96)
        end
    end)
    button:SetScript("OnLeave", function(self)
        if self:GetParent().UpdateDisplay then
            self:GetParent():UpdateDisplay()
        end
    end)

    return button
end

--------------------------------------------------
-- Main Popup Window
--------------------------------------------------

local function CreatePopup()
    if AP.popupFrame then return AP.popupFrame end
    EnsurePopupDefaults()

    local START_W = AccountPlayedPopupDB.width or 640
    local START_H = AccountPlayedPopupDB.height or 380
    local MIN_W, MIN_H = 500, 260
    local MAX_W, MAX_H = 1400, 900

    local f = CreateFrame("Frame", "AccountPlayedPopup", UIParent, "BackdropTemplate")
    f:SetSize(START_W, START_H)

    if AccountPlayedPopupDB.point then
        f:SetPoint(AccountPlayedPopupDB.point, UIParent, AccountPlayedPopupDB.point,
                   AccountPlayedPopupDB.x or 0, AccountPlayedPopupDB.y or 0)
    else
        f:SetPoint("CENTER")
    end

    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        AccountPlayedPopupDB.point = point
        AccountPlayedPopupDB.x = x
        AccountPlayedPopupDB.y = y
    end)

    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif f.SetMinResize then
        f:SetMinResize(MIN_W, MIN_H)
        f:SetMaxResize(MAX_W, MAX_H)
    end
    f:SetClampedToScreen(true)

    local br = CreateFrame("Button", nil, f)
    br:SetSize(16, 16)
    br:SetPoint("BOTTOMRIGHT", -6, 6)
    br:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    br:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    br:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    br:SetScript("OnMouseDown", function(self) self:GetParent():StartSizing("BOTTOMRIGHT") end)
    br:SetScript("OnMouseUp", function(self) self:GetParent():StopMovingOrSizing() end)

    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetBackdropColor(0.035, 0.035, 0.04, 0.94)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 38, -13)
    f.title:SetText(L["WINDOW_TITLE"])
    f.title:SetTextColor(1, 0.82, 0)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        f:Hide()
    end)

    table.insert(UISpecialFrames, "AccountPlayedPopup")

    f:SetScript("OnHide", function()
        if AP.charPanel then AP.charPanel:Hide() end
        AP.charPanelClass = nil
        AP.charPanelGroup = nil
        AP.charPanelState = nil
    end)

    local headerLine = f:CreateTexture(nil, "ARTWORK")
    headerLine:SetHeight(1)
    headerLine:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
    headerLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -34)
    headerLine:SetColorTexture(1, 1, 1, 0.12)

    f.tabs = {}
    for i, tab in ipairs(TAB_ORDER) do
        local label = L[tab.labelKey] or tab.key
        local button = CreateFlatButton(f, label, 84, 26)
        button:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + (i - 1) * 88, -42)
        button:SetScript("OnClick", function()
            AccountPlayedPopupDB.activeTab = tab.key
            f.scrollFrame:SetVerticalScroll(0)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            f:UpdateDisplay()
        end)
        f.tabs[tab.key] = button
    end

    f.chartButtons = {}
    local barButton = CreateFlatButton(f, L["CHART_BAR"] or "Bars", 58, 26)
    barButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -84, -42)
    barButton:SetScript("OnClick", function()
        AccountPlayedPopupDB.chartMode = "bar"
        f.scrollFrame:SetVerticalScroll(0)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        f:UpdateDisplay()
    end)
    f.chartButtons.bar = barButton

    local pieButton = CreateFlatButton(f, L["CHART_PIE"] or "Pie", 58, 26)
    pieButton:SetPoint("LEFT", barButton, "RIGHT", 4, 0)
    pieButton:SetScript("OnClick", function()
        AccountPlayedPopupDB.chartMode = "pie"
        f.scrollFrame:SetVerticalScroll(0)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        f:UpdateDisplay()
    end)
    f.chartButtons.pie = pieButton

    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -78)
    scrollFrame:SetPoint("BOTTOMRIGHT", -44, 78)
    f.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    f.content = content

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local step = 20
        local new = self:GetVerticalScroll() - delta * step
        new = math.max(0, math.min(new, self:GetVerticalScrollRange()))
        self:SetVerticalScroll(new)
    end)

    f.emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.emptyText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    f.emptyText:SetTextColor(0.8, 0.8, 0.8)
    f.emptyText:Hide()

    f.pieFrame = CreateFrame("Frame", nil, content)
    f.pieFrame:SetHeight(PIE_FRAME_H)
    f.pieFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    f.pieFrame:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    f.pieFrame:Hide()

    f.pieAnchor = CreateFrame("Frame", nil, f.pieFrame)
    f.pieAnchor:SetSize(1, 1)
    f.pieAnchor:SetPoint("TOP", f.pieFrame, "TOP", 0, -78)

    f.pieHitFrame = CreateFrame("Button", nil, f.pieFrame)
    f.pieHitFrame.ownerFrame = f
    f.pieHitFrame:SetSize(PIE_OUTER_RADIUS * 2, PIE_OUTER_RADIUS * 2)
    f.pieHitFrame:SetPoint("CENTER", f.pieAnchor, "CENTER", 0, 0)
    f.pieHitFrame:EnableMouse(true)
    f.pieHitFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.pieHitFrame:SetScript("OnEnter", function(self)
        self:SetScript("OnUpdate", UpdatePieHover)
        UpdatePieHover(self)
    end)
    f.pieHitFrame:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        self.entry = nil
        HighlightPieEntry(self.ownerFrame, nil)
        GameTooltip:Hide()
    end)
    f.pieHitFrame:SetScript("OnClick", function(self, button)
        local entry = self.entry or GetPieEntryAtCursor(self.ownerFrame)
        if not entry then return end

        if button == "RightButton" then
            GameTooltip:Hide()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            AP.ShowGroupCharPanel(entry.kind, entry.key, entry.label, entry.color, false)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            PrintCharactersForEntry(entry)
        end
    end)
    f.pieHitFrame:Hide()

    f.pieFrame.centerText = f.pieFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.pieFrame.centerText:SetPoint("CENTER", f.pieAnchor, "CENTER", 0, 0)
    f.pieFrame.centerText:SetSize(82, 42)
    f.pieFrame.centerText:SetJustifyH("CENTER")
    f.pieFrame.centerText:SetJustifyV("MIDDLE")
    f.pieFrame.centerText:SetWordWrap(true)

    f.totalRow = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.totalRow:SetPoint("BOTTOMLEFT", 15, 18)
    f.totalRow:SetPoint("BOTTOMRIGHT", -24, 18)
    f.totalRow:SetJustifyH("LEFT")
    f.totalRow:SetWordWrap(false)
    f.totalRow:SetTextColor(1, 0.82, 0)

    EnsureDistributionRows(f, 8)
    EnsureCharacterRows(f, 8)

    local function UpdateLayoutSizes(self)
        -- Keep chart controls on their own line at narrow window sizes.
        local compact = self:GetWidth() < 620
        self.chartButtons.bar:ClearAllPoints()
        self.chartButtons.bar:SetPoint("TOPRIGHT", self, "TOPRIGHT", -84, compact and -74 or -42)
        self.scrollFrame:SetPoint("TOPLEFT", 15, compact and -110 or -78)
        local cw = self.scrollFrame:GetWidth()
        if not cw or cw <= 1 then
            cw = math.max(1, self:GetWidth() - 59)
        end

        self.content:SetWidth(cw)
        if self.pieFrame then
            self.pieFrame:SetWidth(cw)
        end

        for _, row in ipairs(AP.popupRows) do
            row:SetWidth(cw)
        end
        for _, row in ipairs(AP.characterRows) do
            row:SetWidth(cw)
        end
    end

    f:SetScript("OnSizeChanged", function(self, w, h)
        if w < MIN_W then self:SetWidth(MIN_W) end
        if h < MIN_H then self:SetHeight(MIN_H) end
        if w > MAX_W then self:SetWidth(MAX_W) end
        if h > MAX_H then self:SetHeight(MAX_H) end

        AccountPlayedPopupDB.width = self:GetWidth()
        AccountPlayedPopupDB.height = self:GetHeight()

        UpdateLayoutSizes(self)
        if self.UpdateDisplay then self:UpdateDisplay() end
        UpdateScrollBarVisibility(self)
    end)

    -- Format toggle checkbox
    local checkBox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    checkBox:SetSize(24, 24)
    checkBox:SetPoint("BOTTOMRIGHT", -28, 44)
    checkBox:SetChecked(AccountPlayedPopupDB.useYears)

    checkBox.text = checkBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    checkBox.text:SetPoint("RIGHT", checkBox, "LEFT", -4, 0)
    checkBox.text:SetText(L["USE_YEARS_LABEL"])
    checkBox.text:SetTextColor(0.9, 0.9, 0.9)

    checkBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["TIME_FORMAT_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["TIME_FORMAT_YEARS"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["TIME_FORMAT_HOURS"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    checkBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    checkBox:SetScript("OnClick", function(self)
        AccountPlayedPopupDB.useYears = self:GetChecked()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if AP.popupFrame and AP.popupFrame.UpdateDisplay then
            AP.popupFrame:UpdateDisplay()
        end
    end)

    f.formatCheckbox = checkBox

    -- Display update method
    f.UpdateDisplay = function(self)
        EnsurePopupDefaults()
        UpdateLayoutSizes(self)

        local activeTab = GetActiveTab()
        UpdateTabButtons(self)
        UpdateChartButtons(self)

        if activeTab == "characters" then
            UpdateCharacterView(self)
        else
            UpdateDistributionView(self, activeTab)
        end

        UpdateScrollBarVisibility(self)

        if AP.charPanel and AP.charPanel:IsShown() and AP.charPanelState then
            local state = AP.charPanelState
            AP.ShowGroupCharPanel(state.kind, state.key, state.label, state.color, true)
        end
    end

    f:Hide()
    AP.popupFrame = f
    return f
end

local function UpdatePopup()
    local f = CreatePopup()
    if f.formatCheckbox then
        f.formatCheckbox:SetChecked(AccountPlayedPopupDB.useYears)
    end
    f:Show()
    f:UpdateDisplay()
    C_Timer.After(0, function()
        if f:IsShown() then
            f:UpdateDisplay()
        end
    end)
end

--------------------------------------------------
-- Slash Commands
--------------------------------------------------

AP.ToggleClassWindow = function()
    if AP.popupFrame and AP.popupFrame:IsShown() then
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        AP.popupFrame:Hide()
    else
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        UpdatePopup()
    end
end

SLASH_ACCOUNTPLAYEDPOPUP1 = "/apclasswin"
SlashCmdList.ACCOUNTPLAYEDPOPUP = function()
    print("|cff00ff00Account Played:|r " .. L["MSG_CLASSWIN_DEPRECATED"])
    AP.ToggleClassWindow()
end

--------------------------------------------------
-- Events
--------------------------------------------------

AP.mainFrame:RegisterEvent("PLAYER_LOGIN")
AP.mainFrame:RegisterEvent("TIME_PLAYED_MSG")

AP.mainFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        MigrateOldData()
        SafeRequestTimePlayed()
    elseif event == "TIME_PLAYED_MSG" then
        local totalTimePlayed = ...
        local realm, name = GetCharInfo()
        local charKey = GetCharKey(realm, name)
        local metadata = GetCurrentCharacterMetadata()

        local existing = AccountPlayedDB[charKey]
        if type(existing) ~= "table" then
            existing = { time = 0 }
            AccountPlayedDB[charKey] = existing
        end

        if type(totalTimePlayed) == "number" and (type(existing.time) ~= "number" or totalTimePlayed > existing.time) then
            existing.time = totalTimePlayed
        end

        existing.class = metadata.class
        existing.race = metadata.race
        existing.raceName = metadata.raceName
        existing.faction = metadata.faction
        existing.factionName = metadata.factionName
    end
end)

--------------------------------------------------
-- Minimap Slash Commands
--------------------------------------------------

SLASH_ACCOUNTPLAYED1 = "/aplayed"
SlashCmdList.ACCOUNTPLAYED = function(input)
    input = (input or ""):match("^%s*(.-)%s*$"):lower()
    if input == "minimap" then
        local btn = _G["AccountPlayed_MinimapButton"]
        if btn then
            if not AccountPlayedMinimapDB.hidden then
                AccountPlayedMinimapDB.hidden = true
                UIFrameFadeRemoveFrame(btn)
                btn:SetAlpha(0)
                btn:EnableMouse(false)
                btn:Hide()
                print("|cff00ff00Account Played:|r " .. L["MSG_MINIMAP_HIDDEN"])
            else
                AccountPlayedMinimapDB.hidden = false
                btn:EnableMouse(true)
                btn:Show()
                if btn.snapped then
                    btn:SetAlpha(0.01)
                else
                    btn:SetAlpha(1)
                end
                print("|cff00ff00Account Played:|r " .. L["MSG_MINIMAP_SHOWN"])
            end
        elseif AccountPlayedMinimapDB.hidden then
            AccountPlayedMinimapDB.hidden = false
            if AP.CreateMinimapButton then
                AP.CreateMinimapButton()
            end
            print("|cff00ff00Account Played:|r " .. L["MSG_MINIMAP_SHOWN"])
        end
    elseif input == "show" then
        AP.ToggleClassWindow()
    elseif input == "reset" then
        if AP.ResetMinimapButton then
            AP.ResetMinimapButton()
        else
            print("|cff00ff00Account Played:|r " .. L["MSG_MINIMAP_NOT_INIT"])
        end
    else
        print("|cff00ff00Account Played:|r " .. L["CMD_HELP_HEADER"])
        print("  |cffffff00/aplayed show|r     - " .. L["CMD_HELP_SHOW_DESC"])
        print("  |cffffff00/aplayed minimap|r  - " .. L["CMD_HELP_MINIMAP_DESC"])
        print("  |cffffff00/aplayed reset|r    - " .. L["CMD_HELP_RESET_DESC"])
    end
end

--------------------------------------------------
-- Persist minimap hidden state across sessions
--------------------------------------------------

local persistFrame = CreateFrame("Frame")
persistFrame:RegisterEvent("PLAYER_LOGIN")
persistFrame:SetScript("OnEvent", function(self)
    C_Timer.After(0, function()
        if AccountPlayedMinimapDB and AccountPlayedMinimapDB.hidden then
            local btn = _G["AccountPlayed_MinimapButton"]
            if btn then
                btn:EnableMouse(false)
                btn:Hide()
            end
        end
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)

--------------------------------------------------
-- LibDataBroker plugin
--------------------------------------------------

local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("AccountPlayed", {
    type = "data source",
    text = "AccountPlayed",
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("|cffffffffAccount Played|r")
        tooltip:AddLine("Click to toggle the played time window")
    end,
    OnClick = function(_, button)
        if button == "LeftButton" then
            AP.ToggleClassWindow()
        end
    end,
})
