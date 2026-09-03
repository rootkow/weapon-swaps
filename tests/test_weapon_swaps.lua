local scheduled = {}
local messages = {}
local inCombat = false
local ignoredForSave = {}
local sets = {}
local nextSetID = 0
local saveCounts = {}
local overwriteOnceID
local macros = {}
local equippedMainHandID = 100
local equippedOffHandID = 101
local equippedSetID

local function Noop()
end

local Widget = {}
Widget.__index = function(self, key)
    if key == "GetText" then
        return function(widget) return widget.text or "" end
    elseif key == "SetText" then
        return function(widget, value) widget.text = value end
    elseif key == "SetScript" then
        return function(widget, event, callback) widget.scripts[event] = callback end
    elseif key == "SetAttribute" then
        return function(widget, name, value) widget.attributes[name] = value end
    elseif key == "GetName" then
        return function(widget) return widget.name end
    elseif key == "GetPoint" then
        return function() return "CENTER", nil, "CENTER", 0, 0 end
    elseif key == "IsShown" then
        return function(widget) return widget.shown end
    elseif key == "Show" then
        return function(widget) widget.shown = true end
    elseif key == "Hide" then
        return function(widget) widget.shown = false end
    elseif key == "CreateFontString" or key == "CreateTexture" then
        return function() return setmetatable({ scripts = {}, attributes = {} }, Widget) end
    end
    return Noop
end

local function NewWidget(name)
    return setmetatable({ name = name, scripts = {}, attributes = {}, shown = true }, Widget)
end

function CreateFrame(_, name)
    local widget = NewWidget(name)
    if name then
        _G[name] = widget
    end
    return widget
end

UIParent = NewWidget("UIParent")
GameTooltip = NewWidget("GameTooltip")
GameTooltip_Hide = Noop
DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, message) messages[#messages + 1] = message end,
}
StaticPopupDialogs = {}
StaticPopup_Show = Noop
SlashCmdList = {}
UISpecialFrames = {}
UIDropDownMenu_SetWidth = Noop
UIDropDownMenu_SetText = function(dropdown, text) dropdown.dropdownText = text end
UIDropDownMenu_Initialize = function(dropdown, initializer) dropdown.initializer = initializer end
UIDropDownMenu_CreateInfo = function() return {} end
UIDropDownMenu_AddButton = Noop
DELETE = "Delete"
CANCEL = "Cancel"
WeaponSwapsDB = {}
tinsert = table.insert
strtrim = function(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end
GetInventoryItemTexture = function() return 987654 end
GetInventoryItemID = function(_, slot)
    if slot == 16 then
        return equippedMainHandID
    end
    return equippedOffHandID
end
GetItemInfoInstant = function(itemID)
    if itemID == 200 or itemID == 201 then
        return itemID, "Weapon", "Two-Handed Axes", "INVTYPE_2HWEAPON"
    elseif itemID == 300 then
        return itemID, "Armor", "Shields", "INVTYPE_SHIELD"
    elseif itemID == 110 or itemID == 111 then
        return itemID, "Weapon", "One-Handed Maces", "INVTYPE_WEAPON"
    end
    return itemID, "Weapon", "One-Handed Axes", "INVTYPE_WEAPON"
end
InCombatLockdown = function() return inCombat end
GetMacroIndexByName = function(name)
    for index, macro in ipairs(macros) do
        if macro.name == name then
            return index
        end
    end
    return 0
end
GetMacroInfo = function(index)
    local macro = macros[index]
    if macro then
        return macro.name, macro.icon, macro.body
    end
end
CreateMacro = function(name, icon, body, perCharacter)
    macros[#macros + 1] = {
        name = name,
        icon = icon,
        body = body,
        perCharacter = perCharacter,
    }
    return #macros
end

C_Timer = {
    After = function(_, callback)
        scheduled[#scheduled + 1] = callback
    end,
}

C_EquipmentSet = {
    CanUseEquipmentSets = function() return true end,
    GetEquipmentSetIDs = function()
        local ids = {}
        for id in pairs(sets) do
            ids[#ids + 1] = id
        end
        table.sort(ids)
        return ids
    end,
    GetEquipmentSetInfo = function(id)
        local set = sets[id]
        if set then
            return set.name, set.icon, id, false
        end
    end,
    GetIgnoredSlots = function(id)
        return sets[id] and sets[id].ignored
    end,
    GetItemIDs = function(id)
        return sets[id] and sets[id].itemIDs
    end,
    ClearIgnoredSlotsForSave = function()
        ignoredForSave = {}
    end,
    IgnoreSlotForSave = function(slot)
        ignoredForSave[slot] = true
    end,
    CreateEquipmentSet = function(name, icon)
        sets[nextSetID] = {
            name = name,
            icon = icon,
            ignored = {},
            itemIDs = {
                [16] = equippedMainHandID,
                [17] = equippedOffHandID or 0,
            },
        }
        nextSetID = nextSetID + 1
    end,
    SaveEquipmentSet = function(id)
        local snapshot = {}
        for slot = 1, 19 do
            snapshot[slot] = ignoredForSave[slot] or false
        end
        sets[id].ignored = snapshot
        sets[id].itemIDs = {
            [16] = equippedMainHandID,
            [17] = equippedOffHandID or 0,
        }
        saveCounts[id] = (saveCounts[id] or 0) + 1
        if overwriteOnceID == id and saveCounts[id] == 1 then
            scheduled[#scheduled + 1] = function()
                sets[id].ignored = {}
            end
        end
    end,
    DeleteEquipmentSet = function(id)
        sets[id] = nil
    end,
    UseEquipmentSet = function(id)
        equippedSetID = id
        return true
    end,
}

local addon = {}
assert(loadfile("WeaponSwaps.lua"))("WeaponSwaps", addon)

local function RunNextTimer()
    local callback = table.remove(scheduled, 1)
    assert(callback, "expected a scheduled callback")
    callback()
end

local function RunUntilCreateFinishes()
    local attempts = 0
    while addon.pendingCreate do
        RunNextTimer()
        attempts = attempts + 1
        assert(attempts < 30, "pending creation did not finish")
    end
end

local function AssertWeaponOnly(set)
    for slot = 1, 19 do
        if slot == 16 or slot == 17 then
            assert(set.ignored[slot] == false, "weapon slot was ignored: " .. slot)
        else
            assert(set.ignored[slot] == true, "non-weapon slot was saved: " .. slot)
        end
    end
end

assert(addon:CreateWeaponSet("DW") == true)
assert(sets[0].ignored[1] == nil, "create should happen before ignored slots are configured")
RunUntilCreateFinishes()
AssertWeaponOnly(sets[0])
assert(saveCounts[0] == 1, "settled creation should need one save")
assert(next(ignoredForSave) == nil, "temporary ignored-slot state should be cleared")

local weaponSets, hiddenCount = addon:GetWeaponSets()
assert(#weaponSets == 1 and weaponSets[1].name == "DW")
assert(hiddenCount == 0)
assert(addon:CreateWeaponSet("DW") == false, "duplicate set names should be rejected")
assert(addon:CreateWeaponSet("dw") == false, "duplicate names should be case-insensitive")

sets[1] = { name = "Raid Gear", icon = 1, ignored = {}, itemIDs = { [16] = 100, [17] = 101 } }
nextSetID = 2
weaponSets, hiddenCount = addon:GetWeaponSets()
assert(#weaponSets == 1, "full-gear sets should be hidden")
assert(hiddenCount == 1, "full-gear sets should be counted")

equippedMainHandID = 200
equippedOffHandID = nil
assert(addon:CreateWeaponSet("2H") == true)
overwriteOnceID = 2
inCombat = true
RunNextTimer()
assert(addon.pendingCreate, "creation should remain pending if combat starts")
assert(sets[2].ignored[1] == nil, "set should not be modified during combat")
inCombat = false
addon:FinishPendingCreate()
RunUntilCreateFinishes()
AssertWeaponOnly(sets[2])
assert(saveCounts[2] == 2, "a late native overwrite should trigger a verified retry")
assert(WeaponSwapsEquipButton1.text == "Equip")
local equipMacros = {
    [WeaponSwapsEquipButton1.attributes.macrotext1] = true,
    [WeaponSwapsEquipButton2.attributes.macrotext1] = true,
}
assert(equipMacros["/equipset [combat] DW"] and equipMacros["/equipset [combat] 2H"])
local dwButton = WeaponSwapsEquipButton1.setID == 0 and WeaponSwapsEquipButton1 or WeaponSwapsEquipButton2
dwButton.scripts.PostClick(dwButton)
assert(equippedSetID == 0, "out-of-combat Equip should use the selected native set ID")
equippedSetID = nil
inCombat = true
dwButton.scripts.PostClick(dwButton)
assert(equippedSetID == nil, "combat clicks should be left to the secure macro path")
inCombat = false
assert(WeaponSwapsFirstSetDropdown.dropdownText == "DW")
assert(WeaponSwapsSecondSetDropdown.dropdownText == "2H")

assert(addon:CreateToggleMacro(0, 2) == true)
assert(#macros == 1)
assert(macros[1].name == "WS DW-2H")
assert(macros[1].body == "/equipset [worn:two-hand] DW; 2H")
assert(macros[1].perCharacter == true)
assert(addon:CreateToggleMacro(0, 2) == true, "creating the same toggle should be idempotent")
assert(#macros == 1, "an identical macro should not be duplicated")
assert(addon:CreateToggleMacro(2, 0) == true, "selector order should not affect the toggle")
assert(#macros == 1, "reversing the selectors should not duplicate the macro")
assert(addon:CreateToggleMacro(0, 0) == false, "a toggle needs two different sets")

local weaponMask = {}
for slot = 1, 19 do
    weaponMask[slot] = slot ~= 16 and slot ~= 17
end
sets[3] = { name = "DW Alt", icon = 1, ignored = weaponMask, itemIDs = { [16] = 100, [17] = 101 } }
sets[4] = { name = "2H Alt", icon = 1, ignored = weaponMask, itemIDs = { [16] = 201, [17] = 0 } }
assert(addon:CreateToggleMacro(0, 3) == false, "two one-handed sets cannot auto-toggle")
assert(addon:CreateToggleMacro(2, 4) == false, "two two-handed sets cannot auto-toggle")
assert(#macros == 1, "same-shape sets should not create misleading macros")

sets[5] = { name = "Shield", icon = 1, ignored = weaponMask, itemIDs = { [16] = 100, [17] = 300 } }
assert(addon:CreateToggleMacro(0, 5) == true, "dual wield and shield sets should toggle")
assert(#macros == 2)
assert(macros[2].name == "WS DW-Shield")
assert(macros[2].body == "/equipset [worn:shield] DW; Shield")

sets[6] = { name = "Maces", icon = 1, ignored = weaponMask, itemIDs = { [16] = 110, [17] = 111 } }
assert(addon:CreateToggleMacro(0, 6) == true, "distinct weapon subtypes should toggle")
assert(#macros == 3)
assert(macros[3].name == "WS Maces-DW")
assert(macros[3].body == "/equipset [worn:One-Handed Axes] Maces; DW")
assert(addon:CreateToggleMacro(6, 0) == true, "subtype selector order should not matter")
assert(#macros == 3, "reversing subtype selectors should not duplicate the macro")

addon:DeleteWeaponSet(0)
assert(sets[0] == nil, "weapon set should be deleted")
addon:DeleteWeaponSet(1)
assert(sets[1] ~= nil, "full-gear set should never be deleted")

print("WeaponSwaps tests passed")
