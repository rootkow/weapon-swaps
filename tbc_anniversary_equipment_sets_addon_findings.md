# WoW TBC Anniversary Native Equipment Sets — Findings & Addon Notes

## Goal

Build an addon/UI around the native `C_EquipmentSet` API in WoW TBC Anniversary to make reliable weapon swapping easier.

The original motivation was a macro problem involving two copies of the exact same one-handed weapon. Name-based `/equipslot` macros become ambiguous when both weapons have the same item name.

Native equipment sets solved that problem cleanly because the saved set can remember the actual equipped items rather than relying on item-name resolution.

---

## What We Verified In-Game

### 1. Native equipment sets are available in TBC Anniversary

The `C_EquipmentSet` API exists and is usable.

Verified with:

```lua
/run print("CanUse:", tostring(C_EquipmentSet.CanUseEquipmentSets and C_EquipmentSet.CanUseEquipmentSets()))
```

Observed output:

```text
CanUse: true
```

Also verified:

```lua
/run print("Sets:", #C_EquipmentSet.GetEquipmentSetIDs())
```

returns the number of saved native equipment sets.

---

### 2. `/equipset` works

After creating native sets:

```text
/equipset DW
```

and:

```text
/equipset 2H
```

both worked.

This conditional toggle also worked:

```text
#showtooltip
/equipset [worn:two-hand] DW; 2H
```

Behavior:

- If currently wearing a 2H weapon -> equip `DW`
- Otherwise -> equip `2H`

---

### 3. `/equipset` works in combat

This was tested successfully in combat.

That makes native equipment sets practical for Arena/PvP weapon swapping.

---

### 4. Equipment sets solve duplicate-name weapon problems

Test setup:

- Netherbane
- Netherbane
- Tabar

A native `DW` equipment set containing two Netherbanes successfully equipped both copies correctly.

This avoids ambiguity in name-based macros such as:

```text
/equipslot 16 Netherbane
/equipslot 17 Netherbane
```

The same principle should apply to two copies of another identical weapon, such as two `Syphon of the Nathrezim`.

---

## Important Discovery: Weapon-Only Sets Require a Two-Step Save

This was the main API quirk discovered during testing.

### What did not work reliably

Setting ignored slots and then immediately creating the set:

```lua
C_EquipmentSet.IgnoreSlotForSave(...)
C_EquipmentSet.CreateEquipmentSet("DW")
```

did not persist the ignored-slot configuration correctly on the tested TBC Anniversary client.

### What did work

The reliable sequence was:

1. Create the equipment set normally.
2. Configure ignored slots.
3. Save the existing set using `SaveEquipmentSet(setID)`.
4. Clear the temporary ignore state.

This produced a true weapon-only equipment set.

---

## Weapon Slot IDs

```text
16 = Main Hand
17 = Off Hand
```

For a weapon-only set:

- Slots 16 and 17 should **not** be ignored.
- Every other equipment slot should be ignored.

---

## Verified Manual Workflow

### Step 1: Equip the desired weapons

Example for `DW`:

```text
Main Hand: Netherbane
Off Hand: Netherbane
```

### Step 2: Create the set normally

```lua
/run C_EquipmentSet.ClearIgnoredSlotsForSave();C_EquipmentSet.CreateEquipmentSet("DW")
```

### Step 3: List sets and find the numeric set ID

```lua
/run for _,i in ipairs(C_EquipmentSet.GetEquipmentSetIDs())do print(i,C_EquipmentSet.GetEquipmentSetInfo(i))end
```

Example:

```text
0 DW ...
1 2H ...
```

### Step 4: Convert the existing set to weapon-only

If `DW` is set ID `0`:

```lua
/run C=C_EquipmentSet;C.ClearIgnoredSlotsForSave();for i=1,19 do if i~=16 and i~=17 then C.IgnoreSlotForSave(i)end end;C.SaveEquipmentSet(0)
```

### Step 5: Verify ignored slots

```lua
/run local t=C_EquipmentSet.GetIgnoredSlots(0);for i=1,19 do print(i,t[i])end
```

Expected:

```text
1  true
2  true
3  true
...
15 true
16 false
17 false
18 true
19 true
```

This means:

- armor/trinket/etc. slots are ignored
- main hand and off hand are managed by the set

### Step 6: Clear temporary save state

```lua
/run C_EquipmentSet.ClearIgnoredSlotsForSave()
```

The saved set keeps its persisted ignored-slot configuration.

---

## Example: Creating DW and 2H Sets

### DW

Equip:

```text
Netherbane / Netherbane
```

Create:

```lua
/run C_EquipmentSet.ClearIgnoredSlotsForSave();C_EquipmentSet.CreateEquipmentSet("DW")
```

List sets:

```lua
/run for _,i in ipairs(C_EquipmentSet.GetEquipmentSetIDs())do print(i,C_EquipmentSet.GetEquipmentSetInfo(i))end
```

Assuming ID `0`:

```lua
/run C=C_EquipmentSet;C.ClearIgnoredSlotsForSave();for i=1,19 do if i~=16 and i~=17 then C.IgnoreSlotForSave(i)end end;C.SaveEquipmentSet(0)
```

Clear:

```lua
/run C_EquipmentSet.ClearIgnoredSlotsForSave()
```

### 2H

Equip:

```text
Tabar
```

Create:

```lua
/run C_EquipmentSet.ClearIgnoredSlotsForSave();C_EquipmentSet.CreateEquipmentSet("2H")
```

Assuming ID `1`:

```lua
/run C=C_EquipmentSet;C.ClearIgnoredSlotsForSave();for i=1,19 do if i~=16 and i~=17 then C.IgnoreSlotForSave(i)end end;C.SaveEquipmentSet(1)
```

Clear:

```lua
/run C_EquipmentSet.ClearIgnoredSlotsForSave()
```

---

## Final DW <-> 2H Toggle

```text
#showtooltip
/equipset [worn:two-hand] DW; 2H
```

This was tested successfully:

- out of combat
- in combat

## Listing Equipment Sets

### List all

```lua
/run for _,i in ipairs(C_EquipmentSet.GetEquipmentSetIDs())do print(i,C_EquipmentSet.GetEquipmentSetInfo(i))end
```

### Count

```lua
/run print("Sets:",#C_EquipmentSet.GetEquipmentSetIDs())
```

---

## Deleting Equipment Sets

### Delete by numeric ID

```lua
/run C_EquipmentSet.DeleteEquipmentSet(0)
```

### Delete all

```lua
/run for _,id in ipairs(C_EquipmentSet.GetEquipmentSetIDs())do C_EquipmentSet.DeleteEquipmentSet(id)end
```

---

## APIs Used During Testing

```lua
C_EquipmentSet.CanUseEquipmentSets()
C_EquipmentSet.GetEquipmentSetIDs()
C_EquipmentSet.GetEquipmentSetInfo(id)
C_EquipmentSet.GetEquipmentSetID(name)
C_EquipmentSet.CreateEquipmentSet(name)
C_EquipmentSet.SaveEquipmentSet(id)
C_EquipmentSet.DeleteEquipmentSet(id)

C_EquipmentSet.ClearIgnoredSlotsForSave()
C_EquipmentSet.IgnoreSlotForSave(slot)
C_EquipmentSet.IsSlotIgnoredForSave(slot)
C_EquipmentSet.GetIgnoredSlots(id)

C_EquipmentSet.GetItemLocations(id)
```

One `GetEquipmentSetID("DW")` test returned `nil` because no set existed at that time. That was expected and should not be treated as evidence that the API is broken.

---

## TBC Anniversary API Quirk Observed

After converting `DW` to weapon-only, `GetEquipmentSetInfo()` returned output such as:

```text
DW 134400 0 true 2 2 0 0 0
```

However:

```lua
C_EquipmentSet.GetIgnoredSlots(id)
```

correctly returned 17 ignored slots.

So on the tested client, the final count-like value returned by `GetEquipmentSetInfo()` did not reflect the persisted ignore mask as expected.

For addon validation, prefer:

```lua
C_EquipmentSet.GetIgnoredSlots(id)
```

rather than relying on that final value from `GetEquipmentSetInfo()`.

---

## `GetItemLocations()` Notes

During debugging:

```lua
C_EquipmentSet.GetItemLocations(id)
```

returned packed item-location values such as:

```text
1048577
1048578
...
3146755
```

These are packed item locations, not simple equipment-slot numbers.

They were useful during debugging but are probably unnecessary for the first addon version.

For weapon-only validation, `GetIgnoredSlots()` is much clearer.

---

## Suggested Addon actions

Useful actions the addon should be able to do:

- Save Current Weapons
- Equip
- Rename
- Delete
- Refresh
- Generate/copy recommended macro text

---

## Suggested "Create Weapon Set" Behavior

The addon should automate the tested manual workflow:

```text
1. ClearIgnoredSlotsForSave()
2. CreateEquipmentSet(name)
3. Obtain the newly-created set ID
4. Ignore every slot except 16 and 17
5. SaveEquipmentSet(id)
6. ClearIgnoredSlotsForSave()
```

The macro-character-limit problem disappears inside an addon.

Do not assume that creation and the follow-up save should necessarily happen in the same synchronous call stack. A robust implementation should verify when the newly-created set is visible before updating it.

Possible implementation approach:

- snapshot existing set IDs
- call `CreateEquipmentSet(name)`
- wait for an appropriate equipment-set update event or next-frame callback
- inspect `GetEquipmentSetIDs()` again
- identify the new set
- apply the ignore mask
- call `SaveEquipmentSet(id)`
- clear the temporary ignore state
- verify with `GetIgnoredSlots(id)`

The exact event/timing mechanism should be verified against the live TBC Anniversary client before finalizing the implementation.

---

## Suggested Helper Functions

```lua
local WEAPON_SLOTS = {
    [16] = true,
    [17] = true,
}
```

```lua
local function ConfigureWeaponOnlySave()
    C_EquipmentSet.ClearIgnoredSlotsForSave()

    for slot = 1, 19 do
        if not WEAPON_SLOTS[slot] then
            C_EquipmentSet.IgnoreSlotForSave(slot)
        end
    end
end
```

```lua
local function ClearSaveMask()
    C_EquipmentSet.ClearIgnoredSlotsForSave()
end
```

```lua
local function SaveWeaponOnlySet(setID)
    ConfigureWeaponOnlySave()
    C_EquipmentSet.SaveEquipmentSet(setID)
    ClearSaveMask()
end
```

For creation, keep `CreateEquipmentSet()` and the later weapon-only `SaveEquipmentSet()` as logically separate stages.

---

## Suggested Validation

Before modifying a set:

- Confirm `C_EquipmentSet.CanUseEquipmentSets()` is true.
- Confirm the set ID exists.
- Reject blank names.
- Detect duplicate names.
- Always clear the temporary ignored-slot mask after the operation.
- Verify the saved set using `GetIgnoredSlots(id)`.
- Verify slots 16 and 17 are `false`.
- Verify all other relevant slots are `true`.

Example:

```lua
local ignored = C_EquipmentSet.GetIgnoredSlots(setID)

for slot = 1, 19 do
    local shouldIgnore = slot ~= 16 and slot ~= 17

    if ignored[slot] ~= shouldIgnore then
        -- set was not saved as expected
    end
end
```

---

## Original Macro Problem

The Enhancement Shaman PvP/Arena guide used different weapon names:

```text
/equipslot 16 Dragonmaw
/equipslot 17 The Harvester of Souls
/equipslot [noworn:two-hand,nomod] 16 Deep Thunder
```

and:

```text
#showtooltip Crystal Pulse Shield
/equipslot 16 Dragonmaw
/equipslot [noequipped:Shield] 17 Crystal Pulse Shield
/equipslot [equipped:Shield] 17 The Harvester of Souls
```

The problem appeared when adapting the same strategy to:

```text
Syphon of the Nathrezim
Syphon of the Nathrezim
```

Native equipment sets avoid having to distinguish the two copies by item name.

---

## Key Takeaways

1. Native `C_EquipmentSet` functionality is usable in TBC Anniversary.
2. Native `/equipset` works in combat.
3. Equipment sets correctly handle two identical-name weapons.
4. Conditional `/equipset` macros can provide clean one-button weapon toggles.
5. Weapon-only sets work, but the reliable tested workflow is:
   - create normally
   - configure ignored slots
   - save the existing set
6. `GetIgnoredSlots()` was the best validation method found.
7. The addon should automate the awkward two-stage creation/save process.
8. A useful first version can stay small: create/list/equip/delete weapon sets plus simple macro guidance.

---

## Tested Environment Notes

These findings came from direct in-game testing on WoW TBC Anniversary.

Test weapons:

```text
Netherbane
Netherbane
Tabar
```

Confirmed:

```text
DW <-> 2H toggle works
duplicate-name DW works
weapon-only sets work
/equipset works in combat
```

Treat these findings as TBC Anniversary-specific rather than assuming identical behavior on Retail, Wrath, or other Classic clients.
