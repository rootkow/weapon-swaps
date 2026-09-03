# Weapon Swaps

Weapon Swaps is a small addon for World of Warcraft: The Burning Crusade Classic Anniversary. It creates and manages **weapon-only native equipment sets**, including sets that contain two copies of an identically named weapon.

Because it uses Blizzard's native `C_EquipmentSet` system, the resulting sets also work with the standard `/equipset` macro command. The addon's set buttons are secure macro buttons, so an already open manager can equip saved weapon sets during combat.

## Features

- Creates weapon-only sets from your currently equipped main-hand and off-hand items.
- Uses the TBC Anniversary-specific two-step create/save flow needed to persist ignored armor slots reliably.
- Updates or deletes weapon-only sets without touching full-gear equipment sets.
- Provides clearly labeled secure **Equip** buttons that work in combat when the manager is already open.
- Creates character-specific macros that toggle between two selected weapon sets.
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
4. Wait for the `Created and verified weapon set` chat message. Native creation takes about two seconds because the addon verifies that the weapon-only mask persists.
5. Use the set's **Equip** button to equip it. Use **Save** after changing weapons to overwrite that set.

Creating, saving, deleting, opening, and closing the manager is disabled during combat. If the manager was already open, its set buttons remain usable. A normal `/equipset` action-bar macro remains the most convenient way to swap at any time.

Weapon Swaps deliberately hides normal full-gear equipment sets. It never converts or overwrites them.

### Slash commands

- `/ws` or `/weaponswaps` — toggle the manager.
- `/ws create NAME` — create a weapon-only set from the equipped weapons.
- `/ws list` — print weapon-only set names.
- `/ws help` — print command help.

### Toggle macro builder

The bottom of the manager has selectors for the first and second set. Select two different sets and click **Create macro**. Weapon Swaps compares their saved weapon item types and puts the sets on the correct sides of the condition automatically.

The builder prefers broad, dependable conditions: `[worn:two-hand]` when only one set is two-handed, then `[worn:shield]` when only one set has a shield. Otherwise, it can use a localized weapon subtype such as `One-Handed Axes`, `One-Handed Maces`, `Daggers`, or `Staves` when that subtype occurs in only one set. If both sets share all their weapon types, a macro cannot distinguish them; use their individual **Equip** buttons instead.

If a manually created set's item types cannot be detected, equip it and click **Save** once to record its current weapon layout.

Weapon Swaps creates a character-specific macro without overwriting an unrelated macro with the same name. Creating the same toggle again does not create a duplicate.

For example, selecting `DW` first and `2H` second produces:

```text
/equipset [worn:two-hand] DW; 2H
```

Open the game's macro window with `/macro` to drag the generated macro to an action bar.

## Why creation happens in two steps

On the tested TBC Anniversary client, ignored slots were not persisted when configured immediately before `C_EquipmentSet.CreateEquipmentSet`. Weapon Swaps first creates the native set, waits until it exists, marks every equipment slot except 16 (main hand) and 17 (off hand) as ignored, then saves the set again and clears the temporary ignore state.

See [tbc_anniversary_equipment_sets_addon_findings.md](tbc_anniversary_equipment_sets_addon_findings.md) for the in-game API findings behind the implementation.
