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
	"door_ne", "door_se", "door_sw", "door_nw",
	"stairs_a", "stairs_b", "ramp_a", "ramp_b",
	"roof_slope_a", "roof_slope_b", "roof_slope_c", "roof_slope_d", "roof_block",
]
## Left-right mirror of each directional slot (east <-> west on screen).
const MIRROR := {
	"wall_ne": "wall_nw", "wall_nw": "wall_ne", "wall_se": "wall_sw", "wall_sw": "wall_se",
	"corner_out_e": "corner_out_w", "corner_out_w": "corner_out_e",
	"corner_in_e": "corner_in_w", "corner_in_w": "corner_in_e",
	"t_ne": "t_nw", "t_nw": "t_ne", "t_se": "t_sw", "t_sw": "t_se",
	"door_ne": "door_nw", "door_nw": "door_ne", "door_se": "door_sw", "door_sw": "door_se",
	"stairs_a": "stairs_b", "stairs_b": "stairs_a", "ramp_a": "ramp_b", "ramp_b": "ramp_a",
}

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
				var s := str(MIRROR.get(slot, "")) if flip else slot
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
		out = {"ax": float(a[0]), "ay": float(a[1]), "px": maxf(float(def.get("px", 64)), 1.0)}
	_anchors[dir] = out
	return out


static func clear_cache() -> void:
	_anchors.clear()


static func save() -> bool:
	var f := FileAccess.open("res://data/kits.json", FileAccess.WRITE)
	return f != null and f.store_string(JSON.stringify(ContentDB.kits, "\t", true) + "\n")
