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

local function GetItemEquipLocation(item)
    if not item then
        return nil
    end

    if GetItemInfoInstant then
        return select(4, GetItemInfoInstant(item))
    elseif C_Item and C_Item.GetItemInfoInstant then
        return select(4, C_Item.GetItemInfoInstant(item))
    elseif GetItemInfo then
        return select(9, GetItemInfo(item))
    end
end

local function GetItemSubtype(item)
    if not item then
        return nil
    end

    if GetItemInfoInstant then
        return select(3, GetItemInfoInstant(item))
    elseif C_Item and C_Item.GetItemInfoInstant then
        return select(3, C_Item.GetItemInfoInstant(item))
    elseif GetItemInfo then
        return select(7, GetItemInfo(item))
    end
end

local function ItemUsesTwoHands(item)
    local equipLocation = GetItemEquipLocation(item)
    if not equipLocation or equipLocation == "" then
        return nil
    end
    return equipLocation == "INVTYPE_2HWEAPON"
end

local function ItemIsShield(item)
    local equipLocation = GetItemEquipLocation(item)
    if not equipLocation or equipLocation == "" then
        return nil
    end
    return equipLocation == "INVTYPE_SHIELD"
end

local function GetCharacterStorageKey()
    if UnitGUID then
        local guid = UnitGUID("player")
        if guid then
            return guid
        end
    end

    local name = UnitName and UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Unknown"
    return realm .. "-" .. name
end

function addon:StoreSetWeaponType(setID, isTwoHanded, hasShield, itemTypes)
    if isTwoHanded == nil and hasShield == nil and not itemTypes then
        return
    end

    WeaponSwapsDB = WeaponSwapsDB or {}
    WeaponSwapsDB.setTypes = WeaponSwapsDB.setTypes or {}
    local characterKey = GetCharacterStorageKey()
    WeaponSwapsDB.setTypes[characterKey] = WeaponSwapsDB.setTypes[characterKey] or {}
    local set = GetSetInfo(setID)
    WeaponSwapsDB.setTypes[characterKey][setID] = {
        name = set and set.name,
        isTwoHanded = isTwoHanded,
        hasShield = hasShield,
        itemTypes = itemTypes,
    }
end

local function GetSetItemIDs(setID)
    local api = GetAPI()
    if not api or not api.GetItemIDs then
        return nil
    end

    local ok, itemIDs = pcall(api.GetItemIDs, setID)
    return ok and itemIDs or nil
end

local function GetSetItemFromLocation(setID, slot)
    local api = GetAPI()
    if not api or not api.GetItemLocations or not EquipmentManager_GetItemInfoByLocation then
        return nil, false
    end

    local ok, locations = pcall(api.GetItemLocations, setID)
    local location = ok and locations and locations[slot]
    if location == 0 then
        return nil, true
    end
    if not location or location <= 1 then
        return nil, false
    end

    local itemOK, item = pcall(EquipmentManager_GetItemInfoByLocation, location)
    return itemOK and item or nil, itemOK and item ~= nil
end

local function GetSetSlotItem(setID, slot)
    local itemIDs = GetSetItemIDs(setID)
    if itemIDs then
        local itemID = itemIDs[slot]
        if itemID == 0 then
            return nil, true
        elseif itemID and itemID > 1 then
            return itemID, true
        end
    end

    return GetSetItemFromLocation(setID, slot)
end

function addon:ClearStoredSetWeaponType(setID)
    local setTypes = WeaponSwapsDB
        and WeaponSwapsDB.setTypes
        and WeaponSwapsDB.setTypes[GetCharacterStorageKey()]
    if setTypes then
        setTypes[setID] = nil
    end
end

function addon:GetSetUsesTwoHands(setID)
    local api = GetAPI()
    if not api then
        return nil
    end

    local item, locationKnown = GetSetSlotItem(setID, MAIN_HAND_SLOT)
    if locationKnown then
        if not item then
            return false
        end
        local result = ItemUsesTwoHands(item)
        if result ~= nil then
            return result
        end
    end

    local set = GetSetInfo(setID)
    local setTypes = WeaponSwapsDB
        and WeaponSwapsDB.setTypes
        and WeaponSwapsDB.setTypes[GetCharacterStorageKey()]
    local stored = setTypes and setTypes[setID]
    if stored and set and stored.name == set.name then
        return stored.isTwoHanded
    end

    return nil
end

function addon:GetSetUsesShield(setID)
    local item, locationKnown = GetSetSlotItem(setID, OFF_HAND_SLOT)
    if locationKnown then
        if not item then
            return false
        end
        local result = ItemIsShield(item)
        if result ~= nil then
            return result
        end
    end

    local set = GetSetInfo(setID)
    local setTypes = WeaponSwapsDB
        and WeaponSwapsDB.setTypes
        and WeaponSwapsDB.setTypes[GetCharacterStorageKey()]
    local stored = setTypes and setTypes[setID]
    if stored and set and stored.name == set.name then
        return stored.hasShield
    end

    return nil
end

function addon:GetSetWeaponTypes(setID)
    local types = {}
    local allLocationsKnown = true

    for _, slot in ipairs({ MAIN_HAND_SLOT, OFF_HAND_SLOT }) do
        local item, locationKnown = GetSetSlotItem(setID, slot)
        if not locationKnown then
            allLocationsKnown = false
        elseif item then
            local itemSubtype = GetItemSubtype(item)
            if not itemSubtype or itemSubtype == "" then
                allLocationsKnown = false
            else
                types[itemSubtype] = true
            end
        end
    end

    if allLocationsKnown then
        return types
    end

    local set = GetSetInfo(setID)
    local setTypes = WeaponSwapsDB
        and WeaponSwapsDB.setTypes
        and WeaponSwapsDB.setTypes[GetCharacterStorageKey()]
    local stored = setTypes and setTypes[setID]
    if stored and set and stored.name == set.name then
        return stored.itemTypes
    end

    return nil
end

local function CurrentMainHandUsesTwoHands()
    if not GetInventoryItemID then
        return nil
    end
    return ItemUsesTwoHands(GetInventoryItemID("player", MAIN_HAND_SLOT))
end

local function CurrentOffHandIsShield()
    if not GetInventoryItemID then
        return nil
    end

    local itemID = GetInventoryItemID("player", OFF_HAND_SLOT)
    if not itemID then
        return false
    end
    return ItemIsShield(itemID)
end

local function CurrentWeaponTypes()
    if not GetInventoryItemID then
        return nil
    end

    local types = {}
    for _, slot in ipairs({ MAIN_HAND_SLOT, OFF_HAND_SLOT }) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            local itemSubtype = GetItemSubtype(itemID)
            if not itemSubtype or itemSubtype == "" then
                return nil
            end
            types[itemSubtype] = true
        end
    end
    return types
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

function addon:WriteWeaponOnlySet(setID)
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

    return true
end

function addon:ApplyWeaponOnlySave(setID)
    if not self:WriteWeaponOnlySet(setID) then
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
        self:StoreSetWeaponType(
            setID,
            CurrentMainHandUsesTwoHands(),
            CurrentOffHandIsShield(),
            CurrentWeaponTypes()
        )
        Print(string.format("Saved the currently equipped weapons to |cffffffff%s|r.", set.name))
        self:RefreshUI()
    end
end

function addon:EquipWeaponSet(setID)
    if IsInCombat() then
        return false
    end

    local api = GetAPI()
    local set = GetSetInfo(setID)
    if not api or not api.UseEquipmentSet or not set or not IsWeaponOnlySet(setID) then
        Print("Unable to find that weapon-only equipment set.")
        return false
    end

    local ok, result = pcall(api.UseEquipmentSet, setID)
    if not ok or result == false then
        Print("Unable to equip the set: " .. tostring(ok and "the game rejected the request" or result))
        return false
    end

    Print(string.format("Equipping weapon set |cffffffff%s|r.", set.name))
    return true
end

function addon:SchedulePendingCreate(delay)
    local pending = self.pendingCreate
    if not pending or pending.timerScheduled then
        return
    end

    pending.timerScheduled = true
    C_Timer.After(delay, function()
        if addon.pendingCreate ~= pending then
            return
        end
        pending.timerScheduled = nil
        addon:FinishPendingCreate()
    end)
end

function addon:FailPendingCreate(message)
    local pending = self.pendingCreate
    if not pending then
        return
    end

    self.pendingCreate = nil
    Print(message)

    if pending.setID then
        local api = GetAPI()
        if api and api.DeleteEquipmentSet then
            pcall(api.DeleteEquipmentSet, pending.setID)
            Print("Removed the incomplete set so it cannot overwrite armor by mistake.")
        end
    end

    self:RefreshUI()
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

    pending.waitingForCombat = nil

    if pending.stage == "find" then
        local set = self:FindSetByName(pending.name)
        if set then
            pending.setID = set.id
            pending.stage = "settle"
            -- Seeing the ID does not mean the asynchronous native create has
            -- finished. Let it settle before applying the first weapon mask.
            self:SchedulePendingCreate(0.50)
            return
        end

        pending.findAttempts = pending.findAttempts + 1
        if pending.findAttempts >= 20 then
            self:FailPendingCreate("The game did not finish creating the set. Check the native set limit and try again.")
            return
        end

        self:SchedulePendingCreate(0.20)
        return
    end

    if pending.stage == "settle" then
        pending.saveAttempts = pending.saveAttempts + 1
        pending.stableChecks = 0
        if not self:WriteWeaponOnlySet(pending.setID) then
            self:FailPendingCreate("The weapon-only save failed.")
            return
        end

        pending.stage = "verify"
        self:SchedulePendingCreate(0.50)
        return
    end

    if pending.stage == "verify" then
        if IsWeaponOnlySet(pending.setID) then
            pending.stableChecks = pending.stableChecks + 1
            if pending.stableChecks >= 2 then
                local set = GetSetInfo(pending.setID)
                self:StoreSetWeaponType(
                    pending.setID,
                    pending.isTwoHanded,
                    pending.hasShield,
                    pending.itemTypes
                )
                self.pendingCreate = nil
                Print(string.format("Created and verified weapon set |cffffffff%s|r.", set and set.name or pending.name))
                self:RefreshUI()
            else
                -- Require the saved mask to survive two delayed reads. This
                -- catches the native create finishing late and overwriting it.
                self:SchedulePendingCreate(0.50)
            end
            return
        end

        if pending.saveAttempts >= 3 then
            self:FailPendingCreate("The game did not retain the weapon-only slot mask after three save attempts.")
            return
        end

        pending.stage = "settle"
        self:SchedulePendingCreate(0.50)
    end
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
    self.pendingCreate = {
        name = name,
        stage = "find",
        findAttempts = 0,
        saveAttempts = 0,
        stableChecks = 0,
        isTwoHanded = CurrentMainHandUsesTwoHands(),
        hasShield = CurrentOffHandIsShield(),
        itemTypes = CurrentWeaponTypes(),
    }

    local ok, errorMessage = pcall(api.CreateEquipmentSet, name, icon)
    if not ok then
        self.pendingCreate = nil
        Print("Unable to create the set: " .. tostring(errorMessage))
        return false
    end

    -- TBC Anniversary does not reliably persist ignored slots when they are set
    -- before CreateEquipmentSet. Wait for creation to settle, then save and
    -- verify the mask on two later ticks.
    self:SchedulePendingCreate(0.20)
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
    self:ClearStoredSetWeaponType(setID)
    Print(string.format("Deleted weapon set |cffffffff%s|r.", set.name))
    self:RefreshUI()
end

local function IsMacroSafeSetName(name)
    return name
        and name ~= ""
        and not string.find(name, "[;\r\n]")
        and string.sub(name, 1, 1) ~= "["
end

local function IsMacroSafeItemType(itemType)
    return itemType
        and itemType ~= ""
        and not string.find(itemType, "[%[%];,\r\n]")
end

local function FindDistinctItemType(firstSet, firstTypes, secondSet, secondTypes)
    if not firstTypes or not secondTypes then
        return nil
    end

    local candidates = {}
    for itemType in pairs(firstTypes) do
        if not secondTypes[itemType] and IsMacroSafeItemType(itemType) then
            candidates[#candidates + 1] = {
                itemType = itemType,
                conditionSet = firstSet,
                otherSet = secondSet,
            }
        end
    end
    for itemType in pairs(secondTypes) do
        if not firstTypes[itemType] and IsMacroSafeItemType(itemType) then
            candidates[#candidates + 1] = {
                itemType = itemType,
                conditionSet = secondSet,
                otherSet = firstSet,
            }
        end
    end

    table.sort(candidates, function(left, right)
        local leftType = string.lower(left.itemType)
        local rightType = string.lower(right.itemType)
        if leftType == rightType then
            return string.lower(left.conditionSet.name) < string.lower(right.conditionSet.name)
        end
        return leftType < rightType
    end)

    return candidates[1]
end

local function MakeMacroName(firstName, secondName, suffix)
    local suffixText = suffix and tostring(suffix) or ""
    local available = 16 - #suffixText
    local base = "WS " .. firstName .. "-" .. secondName
    return string.sub(base, 1, available) .. suffixText
end

function addon:CreateToggleMacro(firstSetID, secondSetID)
    if IsInCombat() then
        Print("Macros cannot be created during combat.")
        return false
    end

    if not CreateMacro or not GetMacroIndexByName or not GetMacroInfo then
        Print("The macro API is not available on this client.")
        return false
    end

    local firstSet = GetSetInfo(firstSetID)
    local secondSet = GetSetInfo(secondSetID)
    if not firstSet or not secondSet or not IsWeaponOnlySet(firstSetID) or not IsWeaponOnlySet(secondSetID) then
        Print("Choose two existing weapon-only equipment sets.")
        return false
    end

    if firstSetID == secondSetID then
        Print("Choose two different equipment sets for the toggle.")
        return false
    end

    if not IsMacroSafeSetName(firstSet.name) or not IsMacroSafeSetName(secondSet.name) then
        Print("Set names used in a toggle cannot start with '[' or contain semicolons or line breaks.")
        return false
    end

    local firstUsesTwoHands = self:GetSetUsesTwoHands(firstSetID)
    local secondUsesTwoHands = self:GetSetUsesTwoHands(secondSetID)
    local condition
    local conditionSet
    local otherSet

    if firstUsesTwoHands ~= nil
        and secondUsesTwoHands ~= nil
        and firstUsesTwoHands ~= secondUsesTwoHands then
        condition = "two-hand"
        conditionSet = firstUsesTwoHands and firstSet or secondSet
        otherSet = firstUsesTwoHands and secondSet or firstSet
    else
        local firstUsesShield = self:GetSetUsesShield(firstSetID)
        local secondUsesShield = self:GetSetUsesShield(secondSetID)
        if firstUsesShield ~= nil
            and secondUsesShield ~= nil
            and firstUsesShield ~= secondUsesShield then
            condition = "shield"
            conditionSet = firstUsesShield and firstSet or secondSet
            otherSet = firstUsesShield and secondSet or firstSet
        else
            local distinctType = FindDistinctItemType(
                firstSet,
                self:GetSetWeaponTypes(firstSetID),
                secondSet,
                self:GetSetWeaponTypes(secondSetID)
            )
            if distinctType then
                condition = distinctType.itemType
                conditionSet = distinctType.conditionSet
                otherSet = distinctType.otherSet
            elseif firstUsesTwoHands == nil
                or secondUsesTwoHands == nil
                or firstUsesShield == nil
                or secondUsesShield == nil then
                Print("Unable to determine one set's weapon layout. Equip that set and click Save, then try again.")
                return false
            else
                Print("The selected sets share the same weapon item types, so an automatic toggle cannot distinguish them. Use their Equip buttons instead.")
                return false
            end
        end
    end

    local body = string.format("/equipset [worn:%s] %s; %s", condition, otherSet.name, conditionSet.name)
    local macroName = MakeMacroName(otherSet.name, conditionSet.name)
    local existingIndex = GetMacroIndexByName(macroName)

    if existingIndex and existingIndex > 0 then
        local _, _, existingBody = GetMacroInfo(existingIndex)
        if existingBody == body then
            Print(string.format("The character macro |cffffffff%s|r already exists.", macroName))
            return true
        end

        local foundAvailableName = false
        for suffix = 2, 99 do
            local candidate = MakeMacroName(otherSet.name, conditionSet.name, suffix)
            if GetMacroIndexByName(candidate) == 0 then
                macroName = candidate
                foundAvailableName = true
                break
            end
        end
        if not foundAvailableName then
            Print("Unable to find an available macro name for this toggle.")
            return false
        end
    end

    local ok, macroIndex = pcall(CreateMacro, macroName, DEFAULT_ICON, body, true)
    if not ok or not macroIndex then
        Print("Unable to create the character macro. Check whether the character macro list is full.")
        return false
    end

    Print(string.format("Created character macro |cffffffff%s|r: %s", macroName, body))
    return true
end

local frame = CreateFrame("Frame", "WeaponSwapsFrame", UIParent, "BackdropTemplate")
frame:SetSize(500, 500)
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
scroll:SetPoint("BOTTOMRIGHT", -36, 170)

local scrollChild = CreateFrame("Frame", nil, scroll)
scrollChild:SetSize(440, 1)
scroll:SetScrollChild(scrollChild)
addon.scrollChild = scrollChild

local rows = {}
local function CreateSetRow(index)
    local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    row:SetSize(438, 45)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * 48))
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    row:SetBackdropColor(0.08, 0.08, 0.08, 0.65)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", 6, 0)
    row.icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("LEFT", icon, "RIGHT", 9, 0)
    name:SetPoint("RIGHT", -186, 0)
    name:SetJustifyH("LEFT")
    row.name = name

    local equipButton = CreateFrame("Button", "WeaponSwapsEquipButton" .. index, row, "UIPanelButtonTemplate,SecureActionButtonTemplate")
    equipButton:SetSize(68, 24)
    equipButton:SetPoint("RIGHT", -111, 0)
    equipButton:RegisterForClicks("AnyUp")
    equipButton:SetText("Equip")
    row.equipButton = equipButton

    equipButton:SetScript("PostClick", function(self)
        -- Secure macro execution is reserved for combat. The native API is a
        -- more reliable and observable path for ordinary out-of-combat clicks.
        if not IsInCombat() then
            addon:EquipWeaponSet(self.setID)
        end
    end)

    equipButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.setName or "")
        GameTooltip:AddLine("Click to equip. This secure button works in combat.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    equipButton:SetScript("OnLeave", GameTooltip_Hide)

    local saveButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    saveButton:SetSize(68, 24)
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
nameBox:SetPoint("BOTTOMLEFT", 25, 121)
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

local macroHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
macroHeader:SetPoint("BOTTOMLEFT", 22, 85)
macroHeader:SetText("Create a two-set toggle macro")

local firstMacroLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
firstMacroLabel:SetPoint("BOTTOMLEFT", 28, 62)
firstMacroLabel:SetText("First set:")

local secondMacroLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
secondMacroLabel:SetPoint("BOTTOMLEFT", 190, 62)
secondMacroLabel:SetText("Second set:")

local firstDropdown = CreateFrame("Frame", "WeaponSwapsFirstSetDropdown", frame, "UIDropDownMenuTemplate")
firstDropdown:SetPoint("BOTTOMLEFT", 8, 22)
UIDropDownMenu_SetWidth(firstDropdown, 128)

local secondDropdown = CreateFrame("Frame", "WeaponSwapsSecondSetDropdown", frame, "UIDropDownMenuTemplate")
secondDropdown:SetPoint("BOTTOMLEFT", 170, 22)
UIDropDownMenu_SetWidth(secondDropdown, 128)

local createMacroButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
createMacroButton:SetSize(128, 24)
createMacroButton:SetPoint("BOTTOMRIGHT", -24, 32)
createMacroButton:SetText("Create macro")
createMacroButton:SetScript("OnClick", function()
    addon:CreateToggleMacro(addon.firstMacroSetID, addon.secondMacroSetID)
end)

local function SelectMacroSet(which, setID, setName)
    if which == "first" then
        addon.firstMacroSetID = setID
        UIDropDownMenu_SetText(firstDropdown, setName)
    else
        addon.secondMacroSetID = setID
        UIDropDownMenu_SetText(secondDropdown, setName)
    end
    local canCreate = addon.firstMacroSetID ~= nil
        and addon.secondMacroSetID ~= nil
        and addon.firstMacroSetID ~= addon.secondMacroSetID
        and not addon.pendingCreate
    createMacroButton:SetEnabled(canCreate)
end

local function InitializeSetDropdown(_, level, which)
    for _, set in ipairs(addon:GetWeaponSets()) do
        local setID = set.id
        local setName = set.name
        local info = UIDropDownMenu_CreateInfo()
        info.text = setName
        info.checked = (which == "first" and addon.firstMacroSetID == setID)
            or (which == "second" and addon.secondMacroSetID == setID)
        info.func = function()
            SelectMacroSet(which, setID, setName)
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

UIDropDownMenu_Initialize(firstDropdown, function(self, level)
    InitializeSetDropdown(self, level, "first")
end)
UIDropDownMenu_Initialize(secondDropdown, function(self, level)
    InitializeSetDropdown(self, level, "second")
end)

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
        row.equipButton.setID = set.id
        row.icon:SetTexture(set.icon)
        row.name:SetText(set.isEquipped and ("|cff33ff99" .. set.name .. "|r") or set.name)
        row.saveButton.setID = set.id
        row.deleteButton.setID = set.id
        row.deleteButton.setName = set.name

        row.equipButton:SetAttribute("type1", "macro")
        row.equipButton:SetAttribute("macrotext1", "/equipset [combat] " .. set.name)

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

    local function FindSelectedSet(selectedID)
        for _, set in ipairs(sets) do
            if set.id == selectedID then
                return set
            end
        end
    end

    local firstSet = FindSelectedSet(self.firstMacroSetID)
    local secondSet = FindSelectedSet(self.secondMacroSetID)
    if not firstSet then
        for _, set in ipairs(sets) do
            if string.lower(set.name) == "dw" and (not secondSet or set.id ~= secondSet.id) then
                firstSet = set
                break
            end
        end
        for _, set in ipairs(sets) do
            if not firstSet and (not secondSet or set.id ~= secondSet.id) then
                firstSet = set
                break
            end
        end
        self.firstMacroSetID = firstSet and firstSet.id
    end
    if not secondSet then
        for _, set in ipairs(sets) do
            if string.lower(set.name) == "2h" and (not firstSet or set.id ~= firstSet.id) then
                secondSet = set
                break
            end
        end
        for _, set in ipairs(sets) do
            if not secondSet and (not firstSet or set.id ~= firstSet.id) then
                secondSet = set
                break
            end
        end
        self.secondMacroSetID = secondSet and secondSet.id
    end

    UIDropDownMenu_SetText(firstDropdown, firstSet and firstSet.name or "Choose a set")
    UIDropDownMenu_SetText(secondDropdown, secondSet and secondSet.name or "Choose a set")
    local canCreateMacro = firstSet ~= nil
        and secondSet ~= nil
        and firstSet.id ~= secondSet.id
        and not self.pendingCreate
    createMacroButton:SetEnabled(canCreateMacro)
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
            -- The event can fire before the native create operation is fully
            -- committed, so let the pending timer advance the state machine.
            addon:SchedulePendingCreate(0.20)
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
