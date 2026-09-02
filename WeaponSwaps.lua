local addonName, addon = ...

local ADDON_PREFIX = "|cff33ccffWeapon Swaps:|r "
local MAIN_HAND_SLOT = 16
local OFF_HAND_SLOT = 17
local FIRST_EQUIPMENT_SLOT = 1
local LAST_EQUIPMENT_SLOT = 19
local DEFAULT_ICON = 134400

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. message)
end

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function GetAPI()
    if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
        return C_EquipmentSet
    end
end

local function GetSetInfo(setID)
    local api = GetAPI()
    if not api then
        return nil
    end

    local name, icon, _, isEquipped = api.GetEquipmentSetInfo(setID)
    if not name then
        return nil
    end

    return {
        id = setID,
        name = name,
        icon = icon or DEFAULT_ICON,
        isEquipped = isEquipped,
    }
end

local function IsWeaponOnlySet(setID)
    local api = GetAPI()
    if not api or not api.GetIgnoredSlots then
        return false
    end

    local ignoredSlots = api.GetIgnoredSlots(setID)
    if not ignoredSlots then
        return false
    end

    for slot = FIRST_EQUIPMENT_SLOT, LAST_EQUIPMENT_SLOT do
        if slot == MAIN_HAND_SLOT or slot == OFF_HAND_SLOT then
            if ignoredSlots[slot] then
                return false
            end
        elseif not ignoredSlots[slot] then
            return false
        end
    end

    return true
end

function addon:GetAllSets()
    local api = GetAPI()
    local sets = {}
    if not api then
        return sets
    end

    for _, setID in ipairs(api.GetEquipmentSetIDs() or {}) do
        local set = GetSetInfo(setID)
        if set then
            set.weaponOnly = IsWeaponOnlySet(setID)
            sets[#sets + 1] = set
        end
    end

    table.sort(sets, function(left, right)
        return string.lower(left.name) < string.lower(right.name)
    end)
    return sets
end

function addon:GetWeaponSets()
    local weaponSets = {}
    local hiddenCount = 0

    for _, set in ipairs(self:GetAllSets()) do
        if set.weaponOnly then
            weaponSets[#weaponSets + 1] = set
        else
            hiddenCount = hiddenCount + 1
        end
    end

    return weaponSets, hiddenCount
end

function addon:FindSetByName(name)
    for _, set in ipairs(self:GetAllSets()) do
        if string.lower(set.name) == string.lower(name) then
            return set
        end
    end
end

function addon:CanManageSets()
    local api = GetAPI()
    if not api then
        Print("The native equipment-set API is not available on this client.")
        return false
    end

    if api.CanUseEquipmentSets and not api.CanUseEquipmentSets() then
        Print("Native equipment sets are not available for this character.")
        return false
    end

    if IsInCombat() then
        Print("Sets cannot be created, saved, or deleted during combat. Swap buttons still work.")
        return false
    end

    return true
end

function addon:ApplyWeaponOnlySave(setID)
    local api = GetAPI()
    if not api or not api.ClearIgnoredSlotsForSave or not api.IgnoreSlotForSave or not api.SaveEquipmentSet then
        Print("This client is missing part of the native equipment-set API.")
        return false
    end

    api.ClearIgnoredSlotsForSave()
    for slot = FIRST_EQUIPMENT_SLOT, LAST_EQUIPMENT_SLOT do
        if slot ~= MAIN_HAND_SLOT and slot ~= OFF_HAND_SLOT then
            api.IgnoreSlotForSave(slot)
        end
    end

    local ok, errorMessage = pcall(api.SaveEquipmentSet, setID)
    api.ClearIgnoredSlotsForSave()

    if not ok then
        Print("Unable to save the weapon set: " .. tostring(errorMessage))
        return false
    end

    if not IsWeaponOnlySet(setID) then
        Print("The game did not persist the weapon-only slot mask; the set was not accepted as a Weapon Swaps set.")
        return false
    end

    return true
end

function addon:SaveWeaponSet(setID)
    if not self:CanManageSets() then
        return
    end

    local set = GetSetInfo(setID)
    if not set or not IsWeaponOnlySet(setID) then
        Print("That is not a Weapon Swaps set; no changes were made.")
        return
    end

    if self:ApplyWeaponOnlySave(setID) then
        Print(string.format("Saved the currently equipped weapons to |cffffffff%s|r.", set.name))
        self:RefreshUI()
    end
end

function addon:FinishPendingCreate()
    local pending = self.pendingCreate
    if not pending then
        return
    end

    -- Entering combat in the short gap between create and save would leave a
    -- full-gear set behind. Keep the operation pending and finish it on regen.
    if IsInCombat() then
        pending.waitingForCombat = true
        self:RefreshUI()
        return
    end

    local set = self:FindSetByName(pending.name)
    if set then
        self.pendingCreate = nil
        if self:ApplyWeaponOnlySave(set.id) then
            Print(string.format("Created weapon set |cffffffff%s|r.", set.name))
        else
            local api = GetAPI()
            if api and api.DeleteEquipmentSet then
                pcall(api.DeleteEquipmentSet, set.id)
                Print("Removed the incomplete set so it cannot overwrite armor by mistake.")
            end
        end
        self:RefreshUI()
        return
    end

    pending.attempts = pending.attempts + 1
    if pending.attempts >= 20 then
        self.pendingCreate = nil
        Print("The game did not finish creating the set. Try again after checking the native set limit.")
        self:RefreshUI()
        return
    end

    C_Timer.After(0.15, function()
        addon:FinishPendingCreate()
    end)
end

function addon:CreateWeaponSet(rawName)
    if not self:CanManageSets() then
        return false
    end

    if self.pendingCreate then
        Print("Wait for the current set to finish saving.")
        return false
    end

    local name = strtrim(rawName or "")
    if name == "" then
        Print("Enter a name for the weapon set.")
        return false
    end

    if self:FindSetByName(name) then
        Print(string.format("An equipment set named |cffffffff%s|r already exists.", name))
        return false
    end

    local api = GetAPI()
    if not api.CreateEquipmentSet or not api.ClearIgnoredSlotsForSave then
        Print("This client cannot create native equipment sets.")
        return false
    end

    local icon = GetInventoryItemTexture("player", MAIN_HAND_SLOT) or DEFAULT_ICON
    api.ClearIgnoredSlotsForSave()
    self.pendingCreate = { name = name, attempts = 0 }

    local ok, errorMessage = pcall(api.CreateEquipmentSet, name, icon)
    if not ok then
        self.pendingCreate = nil
        Print("Unable to create the set: " .. tostring(errorMessage))
        return false
    end

    -- TBC Anniversary does not reliably persist ignored slots when they are set
    -- before CreateEquipmentSet. Wait for creation, then configure and save it.
    C_Timer.After(0.15, function()
        addon:FinishPendingCreate()
    end)
    self:RefreshUI()
    return true
end

function addon:DeleteWeaponSet(setID)
    if not self:CanManageSets() then
        return
    end

    local api = GetAPI()
    local set = GetSetInfo(setID)
    if not set or not IsWeaponOnlySet(setID) then
        Print("That is not a Weapon Swaps set; no changes were made.")
        return
    end

    api.DeleteEquipmentSet(setID)
    Print(string.format("Deleted weapon set |cffffffff%s|r.", set.name))
    self:RefreshUI()
end

local frame = CreateFrame("Frame", "WeaponSwapsFrame", UIParent, "BackdropTemplate")
frame:SetSize(390, 430)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
})
frame:SetScript("OnDragStart", function(self)
    if not IsInCombat() then
        self:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    WeaponSwapsDB.position = { point, relativePoint, x, y }
end)
frame:Hide()
addon.frame = frame

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("TOP", 0, -18)
title:SetText("Weapon Swaps")

local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", -5, -5)

local helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
helpText:SetPoint("TOPLEFT", 22, -48)
helpText:SetPoint("TOPRIGHT", -22, -48)
helpText:SetJustifyH("LEFT")
helpText:SetText("Equip the weapons you want, then create or save a set. Only weapon slots 16 and 17 are stored.")

local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
header:SetPoint("TOPLEFT", 22, -88)
header:SetText("Weapon-only equipment sets")

local status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
status:SetPoint("TOPRIGHT", -30, -89)
status:SetJustifyH("RIGHT")
addon.status = status

local scroll = CreateFrame("ScrollFrame", "WeaponSwapsScrollFrame", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 18, -108)
scroll:SetPoint("BOTTOMRIGHT", -36, 85)

local scrollChild = CreateFrame("Frame", nil, scroll)
scrollChild:SetSize(330, 1)
scroll:SetScrollChild(scrollChild)
addon.scrollChild = scrollChild

local rows = {}
local function CreateSetRow(index)
    local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    row:SetSize(328, 45)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * 48))
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    row:SetBackdropColor(0.08, 0.08, 0.08, 0.65)

    local equipButton = CreateFrame("Button", "WeaponSwapsEquipButton" .. index, row, "SecureActionButtonTemplate")
    equipButton:SetSize(202, 41)
    equipButton:SetPoint("LEFT", 2, 0)
    equipButton:RegisterForClicks("AnyUp")
    equipButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.equipButton = equipButton

    local icon = equipButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", 4, 0)
    equipButton.icon = icon

    local name = equipButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("LEFT", icon, "RIGHT", 9, 0)
    name:SetPoint("RIGHT", -4, 0)
    name:SetJustifyH("LEFT")
    equipButton.name = name

    equipButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.setName or "")
        GameTooltip:AddLine("Click to equip. This secure button works in combat.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    equipButton:SetScript("OnLeave", GameTooltip_Hide)

    local saveButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    saveButton:SetSize(78, 24)
    saveButton:SetPoint("RIGHT", -39, 0)
    saveButton:SetText("Save")
    saveButton:SetScript("OnClick", function(self)
        addon:SaveWeaponSet(self.setID)
    end)
    saveButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Save current weapons")
        GameTooltip:AddLine("Overwrites this set's main-hand and off-hand items only.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    saveButton:SetScript("OnLeave", GameTooltip_Hide)
    row.saveButton = saveButton

    local deleteButton = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    deleteButton:SetSize(30, 30)
    deleteButton:SetPoint("RIGHT", -5, 0)
    deleteButton:SetScript("OnClick", function(self)
        addon.deleteSetID = self.setID
        StaticPopup_Show("WEAPONSWAPS_CONFIRM_DELETE", self.setName)
    end)
    row.deleteButton = deleteButton

    rows[index] = row
    return row
end

StaticPopupDialogs.WEAPONSWAPS_CONFIRM_DELETE = {
    text = "Delete the weapon set '%s'?",
    button1 = DELETE,
    button2 = CANCEL,
    OnAccept = function()
        local setID = addon.deleteSetID
        addon.deleteSetID = nil
        if setID then
            addon:DeleteWeaponSet(setID)
        end
    end,
    OnCancel = function()
        addon.deleteSetID = nil
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local nameBox = CreateFrame("EditBox", "WeaponSwapsNameBox", frame, "InputBoxTemplate")
nameBox:SetSize(235, 24)
nameBox:SetPoint("BOTTOMLEFT", 25, 36)
nameBox:SetAutoFocus(false)
nameBox:SetMaxLetters(31)
nameBox:SetTextInsets(5, 5, 0, 0)

local createButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
createButton:SetSize(95, 24)
createButton:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
createButton:SetText("Create set")
createButton:SetScript("OnClick", function()
    local name = nameBox:GetText()
    if addon:CreateWeaponSet(name) then
        nameBox:SetText("")
        nameBox:ClearFocus()
    end
end)
nameBox:SetScript("OnEnterPressed", function()
    createButton:Click()
end)
nameBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)

local nameHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
nameHint:SetPoint("BOTTOMLEFT", nameBox, "TOPLEFT", 0, 2)
nameHint:SetText("New set name")

function addon:RefreshUI()
    if not self.frame then
        return
    end

    -- The set buttons are protected so their /equipset actions can execute in
    -- combat. Their parent layout must not be rebuilt during combat lockdown.
    if IsInCombat() then
        self.needsUIRefresh = true
        return
    end

    self.needsUIRefresh = nil

    local sets, hiddenCount = self:GetWeaponSets()
    for index, set in ipairs(sets) do
        local row = rows[index] or CreateSetRow(index)
        row.setID = set.id
        row:Show()

        row.equipButton.setName = set.name
        row.equipButton.icon:SetTexture(set.icon)
        row.equipButton.name:SetText(set.isEquipped and ("|cff33ff99" .. set.name .. "|r") or set.name)
        row.saveButton.setID = set.id
        row.deleteButton.setID = set.id
        row.deleteButton.setName = set.name

        row.equipButton:SetAttribute("type", "macro")
        row.equipButton:SetAttribute("macrotext", "/equipset " .. set.name)

        row.saveButton:SetEnabled(true)
        row.deleteButton:SetEnabled(true)
    end

    for index = #sets + 1, #rows do
        rows[index]:Hide()
    end

    scrollChild:SetHeight(math.max(1, #sets * 48))
    local summary = string.format("%d shown", #sets)
    if hiddenCount > 0 then
        summary = summary .. string.format(", %d full-gear hidden", hiddenCount)
    end
    if self.pendingCreate then
        summary = "Creating " .. self.pendingCreate.name .. "..."
    end
    status:SetText(summary)
    createButton:SetEnabled(not self.pendingCreate)
    nameBox:SetEnabled(not self.pendingCreate)
end

function addon:ToggleUI()
    if IsInCombat() then
        Print("Open or close the manager outside combat. An already open set button still works in combat.")
        return
    end

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        self:RefreshUI()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, argument)
    if event == "ADDON_LOADED" and argument == addonName then
        WeaponSwapsDB = WeaponSwapsDB or {}
        if WeaponSwapsDB.position then
            frame:ClearAllPoints()
            frame:SetPoint(WeaponSwapsDB.position[1], UIParent, WeaponSwapsDB.position[2], WeaponSwapsDB.position[3], WeaponSwapsDB.position[4])
        end
        tinsert(UISpecialFrames, frame:GetName())
    elseif event == "PLAYER_LOGIN" then
        if not GetAPI() then
            Print("The native equipment-set API is unavailable. This addon requires TBC Anniversary.")
        end
        addon:RefreshUI()
    elseif event == "EQUIPMENT_SETS_CHANGED" then
        if addon.pendingCreate then
            addon:FinishPendingCreate()
        end
        addon:RefreshUI()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        addon:RefreshUI()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if addon.pendingCreate then
            addon:FinishPendingCreate()
        else
            addon:RefreshUI()
        end
    end
end)

SLASH_WEAPONSWAPS1 = "/weaponswaps"
SLASH_WEAPONSWAPS2 = "/ws"
SlashCmdList.WEAPONSWAPS = function(message)
    local command, rest = string.match(message or "", "^(%S*)%s*(.-)$")
    command = string.lower(command or "")

    if command == "create" then
        addon:CreateWeaponSet(rest)
    elseif command == "list" then
        local sets = addon:GetWeaponSets()
        if #sets == 0 then
            Print("No weapon-only sets found.")
        else
            Print("Weapon-only sets:")
            for _, set in ipairs(sets) do
                Print("- " .. set.name)
            end
        end
    elseif command == "help" then
        Print("/ws - open or close the manager")
        Print("/ws create NAME - save the currently equipped weapons as a new set")
        Print("/ws list - list weapon-only sets")
    else
        addon:ToggleUI()
    end
end

_G.WeaponSwaps = addon
