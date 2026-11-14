"""Add the cut gear art sets to data/items.json as items (Brian, 2026-11-14:
"helmets as separate head pieces and pistols as items"). Free; safe to rerun
(items it made before are replaced, everything else is left alone).

    python3 -I tools/gear/add_gear_items.py

- Pistols: every assets/gear/weapons/neon_pistol_NN -> wpn_neon_pistol_NN,
  WEAPON / pistol, wear_path = the art set. Stats copy Scrap Revolver
  (wpn_pistol_1) for now: placeholders until Brian sets tiers.
Helmets are not items yet: they are head modules (tools/gear/heads.py) that
replace the head in a head slot, not pieces drawn over it.
They carry the tag "gear_art_set" so this script knows which items are its own.
"""
import glob
import json
import os

ITEMS = os.path.join("data", "items.json")
TAG = "gear_art_set"


def main() -> None:
	items = json.load(open(ITEMS))
	keep = [i for i in items if TAG not in i.get("tags", [])]
	base = next(i for i in items if i["id"] == "wpn_pistol_1")
	new = []
	for d in sorted(glob.glob(os.path.join("assets", "gear", "weapons", "neon_pistol_*"))):
		n = d.rsplit("_", 1)[1]
		new.append({"id": "wpn_neon_pistol_%s" % n, "display_name": "Neon Pistol %s" % n, "category": "WEAPON",
			"value": base["value"], "description": "", "equip_type": "pistol",
			"stat_modifiers": dict(base["stat_modifiers"]), "stat_growth": dict(base["stat_growth"]),
			"weapon_range": base["weapon_range"], "rarity": "COMMON",
			"wear_path": "res://" + d.replace(os.sep, "/"), "tags": [TAG, "placeholder_stats"]})
	with open(ITEMS, "w") as f:
		json.dump(keep + new, f, indent="\t", ensure_ascii=False)
		f.write("\n")
	print("items: %d kept + %d gear (%d pistols, %d helmets)" % (len(keep), len(new),
		sum(1 for i in new if i["category"] == "WEAPON"), sum(1 for i in new if i["category"] == "ACCESSORY")))


if __name__ == "__main__":
	main()
