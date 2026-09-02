local scheduled = {}
local messages = {}
local inCombat = false
local ignoredForSave = {}
local sets = {}
local nextSetID = 0

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
DELETE = "Delete"
CANCEL = "Cancel"
WeaponSwapsDB = {}
tinsert = table.insert
strtrim = function(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end
GetInventoryItemTexture = function() return 987654 end
InCombatLockdown = function() return inCombat end

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
    ClearIgnoredSlotsForSave = function()
        ignoredForSave = {}
    end,
    IgnoreSlotForSave = function(slot)
        ignoredForSave[slot] = true
    end,
    CreateEquipmentSet = function(name, icon)
        sets[nextSetID] = { name = name, icon = icon, ignored = {} }
        nextSetID = nextSetID + 1
    end,
    SaveEquipmentSet = function(id)
        local snapshot = {}
        for slot = 1, 19 do
            snapshot[slot] = ignoredForSave[slot] or false
        end
        sets[id].ignored = snapshot
    end,
    DeleteEquipmentSet = function(id)
        sets[id] = nil
    end,
}

local addon = {}
assert(loadfile("WeaponSwaps.lua"))("WeaponSwaps", addon)

local function RunNextTimer()
    local callback = table.remove(scheduled, 1)
    assert(callback, "expected a scheduled callback")
    callback()
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
RunNextTimer()
AssertWeaponOnly(sets[0])
assert(next(ignoredForSave) == nil, "temporary ignored-slot state should be cleared")

local weaponSets, hiddenCount = addon:GetWeaponSets()
assert(#weaponSets == 1 and weaponSets[1].name == "DW")
assert(hiddenCount == 0)
assert(addon:CreateWeaponSet("DW") == false, "duplicate set names should be rejected")
assert(addon:CreateWeaponSet("dw") == false, "duplicate names should be case-insensitive")

sets[1] = { name = "Raid Gear", icon = 1, ignored = {} }
nextSetID = 2
weaponSets, hiddenCount = addon:GetWeaponSets()
assert(#weaponSets == 1, "full-gear sets should be hidden")
assert(hiddenCount == 1, "full-gear sets should be counted")

assert(addon:CreateWeaponSet("2H") == true)
inCombat = true
RunNextTimer()
assert(addon.pendingCreate, "creation should remain pending if combat starts")
assert(sets[2].ignored[1] == nil, "set should not be modified during combat")
inCombat = false
addon:FinishPendingCreate()
AssertWeaponOnly(sets[2])

addon:DeleteWeaponSet(0)
assert(sets[0] == nil, "weapon set should be deleted")
addon:DeleteWeaponSet(1)
assert(sets[1] ~= nil, "full-gear set should never be deleted")

print("WeaponSwaps tests passed")
