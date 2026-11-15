# Hard asset reset: keep / cut list (for Brian's OK; nothing deleted yet)

Repo today: 54,060 files (52,952 of them art). After the reset: about 10,000 with
recolours as data (recommended), or about 26,000 with every recolour baked as PNGs.

## Characters (assets/units: 41,534 files today)

KEEP
- The 14 outfits in your pictures, with their full kits: walk, hit, death,
  pistol, rifle raise / rest / aim, throw, use item (the item over the head), jump.
  armor_009, armor_6142, dragoon, dragoon_helm, dragoon_wings, heavy40,
  hood_0101, longcoat, medic_buns, neon_coat, samurai, slicked20, tinkerer, undercut.
- Their colour variants from your sheets: 4 per outfit (hood_0101 has none) = 52.
- pool_003 (the hooded one with the orange visor and sword) + its 4 variants.
- The three new enemies: enemy_daemon, enemy_digimage_digisummoner, enemy_factory_security.

base_male_hi (10,800 files): the 14 outfits read their animation frames from it.
Only the chosen frames are kept (3,706, the folders the outfits actually play),
moved into each outfit's own folder. The other 7,094 go: body parts, raw
uncleaned takes, unused takes.
The takes are not lost: they're still in PixelLab and in git history.

CUT: every other pool_* character and its variants (pool_004 … pool_132), base_male,
base_body_a, test_character_001, test_enemy_001/002, test_vendorNPC_001, and
"full cast of characters so far south facing for reference". Where data points
at a cut unit (a few NPCs and test fights), it switches to one of the kept outfits.

## Colour variants: recommend recolouring in the game instead of storing PNGs
Each variant is just a colour rule (shift hue band X to Y), already written in
tools/pixellab/recolors.json. Today each one is baked into 302 copied PNGs:
56 variants = 16,256 files. Instead, a variant becomes one line of data and a
shader applies the same rule as it draws. The pixels match the baked ones (I'll
verify pixel-for-pixel before cutting), and new variants cost zero files.

## Weapons and throwables (assets/gear)
KEEP: the 49 pistols (neon_pistol_01–49), the rifles / heavy guns
(cyberpunk_assault_rifle_001, auto_rifle, auto_shotty, energy_blaster_rifle,
heavy_machine_gun, sub_machine_gun 001/002, super_handgun, super_laser_rifle,
super_shotgun, spell_blaster, flame_thrower, handgun_002/003,
pulse_plasma_rifle_001): the rifles you couldn't find are these. Also the 14
grenades and 14 mines. Their anchor points stay with them.
CUT: gear/source (307 raw sheets and rotations), armor/pilot_vest, heads/slicked20,
the old pilot_blade / launcher / pistol / rifle.

## Tiles, props, buildings
KEEP: last night's drop: 865 tiles in its sets, 2,162 props (items, facades, rooms,
digimancer, signs, junk, bar, boss structures), the painter / auto-wall kits
(tools/handoff/kits), the stacking building tiles.
CUT: the 976 older tiles (battle_map_textures, hub_floor_textures and the older
generated sets), all of assets/structures (4,270 old buildings, including the old
static vehicle pictures), assets/backgrounds (219), the archived assets/incoming
(603), and assets/kit pool_005 / pool_021.
Test fights and the hub get rebuilt on the new tiles (terrain names map to new sets).

## Icons (assets/ui: 994)
KEEP: the 371 icons the game can actually look up (class, ability, item, status,
stat and command icons by name).
CUT: the 185 icons nothing asks for, plus hud/, hud_doctrine/, doctrine/,
frames_doctrine/, glyphs_doctrine/, class-upgrade-promotion-icons/, and the loose
icons_0xx sheets. None of these are referenced anywhere. The new drop had no icons.

## Kept as is
All code, the engine, menus, Forge and Lattice tools, data, all SFX and music,
fonts, signage, voice, cutscenes.

## Not found
Grok's animated vehicles and hover vehicles aren't in the repo (only the mount
slots in data/mounts.json, with empty art). If they're on your PC, they can come in
with the next drop.

## Afterwards
History still holds the old files (5.3 GB). A fresh GitHub repo with just the
cleaned game fixes that; this repo stays as the backup.
