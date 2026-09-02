# Weapon Swaps

Weapon Swaps is a small addon for World of Warcraft: The Burning Crusade Classic Anniversary. It creates and manages **weapon-only native equipment sets**, including sets that contain two copies of an identically named weapon.

Because it uses Blizzard's native `C_EquipmentSet` system, the resulting sets also work with the standard `/equipset` macro command. The addon's set buttons are secure macro buttons, so an already open manager can equip saved weapon sets during combat.

## Features

- Creates weapon-only sets from your currently equipped main-hand and off-hand items.
- Uses the TBC Anniversary-specific two-step create/save flow needed to persist ignored armor slots reliably.
- Updates or deletes weapon-only sets without touching full-gear equipment sets.
- Provides secure set buttons that work in combat.
- Recognizes weapon-only sets created manually or by another addon.
- Handles duplicate-name weapons through native equipment-set item tracking.

## Installation

1. Put this project in `World of Warcraft/_anniversary_/Interface/AddOns/WeaponSwaps`.
2. Make sure `WeaponSwaps.toc` is directly inside that folder.
3. Restart the game or run `/reload` after installing or updating it.

The addon targets TBC Anniversary interface version `20505`.

## Usage

1. Equip the desired main-hand and off-hand weapons.
2. Open the manager with `/ws`.
3. Enter a set name and click **Create set**.
4. Use the set's large button to equip it. Use **Save** after changing weapons to overwrite that set.

Creating, saving, deleting, opening, and closing the manager is disabled during combat. If the manager was already open, its set buttons remain usable. A normal `/equipset` action-bar macro remains the most convenient way to swap at any time.

Weapon Swaps deliberately hides normal full-gear equipment sets. It never converts or overwrites them.

### Slash commands

- `/ws` or `/weaponswaps` — toggle the manager.
- `/ws create NAME` — create a weapon-only set from the equipped weapons.
- `/ws list` — print weapon-only set names.
- `/ws help` — print command help.

### Toggle macro

Native set names can be used directly in macros. For example, with sets named `DW` and `2H`:

```text
#showtooltip
/equipset [worn:two-hand] DW; 2H
```

## Why creation happens in two steps

On the tested TBC Anniversary client, ignored slots were not persisted when configured immediately before `C_EquipmentSet.CreateEquipmentSet`. Weapon Swaps first creates the native set, waits until it exists, marks every equipment slot except 16 (main hand) and 17 (off hand) as ignored, then saves the set again and clears the temporary ignore state.

See [tbc_anniversary_equipment_sets_addon_findings.md](tbc_anniversary_equipment_sets_addon_findings.md) for the in-game API findings behind the implementation.
