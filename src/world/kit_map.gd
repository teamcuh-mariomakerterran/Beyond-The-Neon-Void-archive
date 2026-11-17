class_name KitMap
extends RefCounted
## Building kits: which cut piece fills which wall slot (data/kits.json, edited
## in the Neon Forge KIT MAP tab, pre-filled by tools/cut_kits.bat).
##
## A kit is one sheet at one wall height (1-3 tiles; the _hN in its name).
## Kits that share a `family` are the same set at other heights. A slot that
## is empty borrows its mirror image, then the same slot from the family's
## nearest height.
##
## Piece images keep their whole sheet cell, so one anchor per kit (the centre
## of the ground diamond the walls stand on, in piece pixels) places every piece.

## Every slot the map offers, in the order the tab lists them.
const SLOTS: Array[String] = [
	"floor", "roof",
	"wall_ne", "wall_se", "wall_sw", "wall_nw",
	"corner_out_n", "corner_out_e", "corner_out_s", "corner_out_w",
	"corner_in_n", "corner_in_e", "corner_in_s", "corner_in_w",
	"t_ne", "t_se", "t_sw", "t_nw", "cross", "post",
	"door_ne", "door_se", "door_sw", "door_nw", "door_thin_a", "door_thin_b",
	"join_ne", "join_se", "join_sw", "join_nw",
	"thin_ne", "thin_se", "thin_sw", "thin_nw", "thin_post",
	"thin_ne_se", "thin_se_sw", "thin_sw_nw", "thin_ne_nw",
	"thin_ne_se_sw", "thin_se_sw_nw", "thin_ne_sw_nw", "thin_ne_se_nw", "thin_cross",
	"stairs_a", "stairs_b", "ramp_a", "ramp_b",
	"slope_ne", "slope_se", "slope_sw", "slope_nw",
	"hip_n", "hip_e", "hip_s", "hip_w", "roof_block",
	"valley_e", "valley_n", "valley_s", "valley_w", "ridge_x", "ridge_y",
	"roof_end_se", "roof_end_ne", "roof_end_sw", "roof_end_nw", "roof_pyramid",
]
const DIRS: Array[String] = ["ne", "se", "sw", "nw"]
const _FLIP := {"ne": "nw", "nw": "ne", "se": "sw", "sw": "se", "e": "w", "w": "e"}


## Left-right mirror of a directional slot (east <-> west on screen), "" if it has none.
static func mirror(slot: String) -> String:
	var parts := slot.split("_")
	var head: Array[String] = []
	var dirs: Array[String] = []
	for p in parts:
		if _FLIP.has(p):
			dirs.append(str(_FLIP[p]))
		elif dirs.is_empty():
			head.append(p)
		else:
			return ""
	if dirs.is_empty():
		return ""
	dirs.sort_custom(func(a: String, b: String) -> bool: return DIRS.find(a) < DIRS.find(b))
	var out := "_".join(head + dirs)
	return out if out != slot else ""


static var _anchors: Dictionary = {}


static func kits() -> Dictionary:
	return ContentDB.kits


static func kit(kit_id: String) -> Dictionary:
	return ContentDB.kits.get(kit_id, {})


## Tile id of a kit piece ("" when the slot is empty in that kit itself).
static func tile(kit_id: String, slot: String) -> String:
	var file := str(kit(kit_id).get("slots", {}).get(slot, ""))
	return "kits/%s/%s" % [kit_id, file] if file != "" else ""


## Kits of the same family, nearest wall height to `height` first.
static func family(kit_id: String, height: int) -> Array[String]:
	var fam := str(kit(kit_id).get("family", kit_id))
	var out: Array[String] = []
	for id: String in ContentDB.kits:
		if str(ContentDB.kits[id].get("family", id)) == fam:
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var da := absi(int(kit(a).get("height", 1)) - height)
		var db := absi(int(kit(b).get("height", 1)) - height)
		return da < db or (da == db and a < b))
	return out


## The piece for a slot at a wall height: {tile, flip, height, kit, borrowed}
## ({} when nothing in the family can fill it). `height` in the result is the
## height the piece was drawn at; `borrowed` is "" | "mirror" | "height".
static func resolve(kit_id: String, slot: String, height: int = 0) -> Dictionary:
	if height <= 0:
		height = int(kit(kit_id).get("height", 1))
	var fam := family(kit_id, height)
	for pass_mirror: bool in [false, true]:
		for id in fam:
			var h := int(kit(id).get("height", 1))
			if not pass_mirror and h != height:
				continue
			for flip: bool in [false, true]:
				var s := mirror(slot) if flip else slot
				var t := tile(id, s) if s != "" else ""
				if t != "":
					return {"tile": t, "flip": flip, "height": h, "kit": id,
						"borrowed": "height" if h != height else ("mirror" if flip else "")}
	return {}


## Slots a kit can't fill on its own at its height (the tab lists them).
static func missing(kit_id: String) -> Array[String]:
	var out: Array[String] = []
	for s in SLOTS:
		if tile(kit_id, s) == "":
			out.append(s)
	return out


## Placement of an anchored tile id ("kits/<kit>/<piece>" or
## "autotiles/<set>/<piece>"): {ax, ay, px} in piece pixels, {} for plain tiles.
static func anchor(tile_id: String) -> Dictionary:
	var cut := tile_id.rfind("/")
	var dir := tile_id.left(cut) if cut > 0 else ""
	if _anchors.has(dir):
		return _anchors[dir]
	var def: Dictionary = {}
	if dir.begins_with("kits/"):
		def = ContentDB.kits.get(dir.substr(5), {})
	elif dir.begins_with("autotiles/"):
		def = ContentDB.autotiles.get(dir.substr(10), {})
	var out := {}
	var a: Variant = def.get("anchor")
	if a is Array and (a as Array).size() == 2:
		out = {"ax": float(a[0]), "ay": float(a[1]), "px": maxf(float(def.get("px", 64)), 1.0), "slab": float(def.get("slab", 0))}
	_anchors[dir] = out
	return out


## Layers a kit's floor top sits above the ground its walls stand on
## (thin slabs 0, thick ones 1, block floors 2).
static func floor_layers(kit_id: String) -> int:
	return int((float(kit(kit_id).get("slab", 0)) + 4.0) / 16.0)


static func clear_cache() -> void:
	_anchors.clear()


static func save() -> bool:
	var f := FileAccess.open("res://data/kits.json", FileAccess.WRITE)
	return f != null and f.store_string(JSON.stringify(ContentDB.kits, "\t", true) + "\n")
