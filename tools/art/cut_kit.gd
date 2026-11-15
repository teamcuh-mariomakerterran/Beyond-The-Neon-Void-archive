extends SceneTree
## Cuts building-kit sheets and auto-tile sheets into pieces and pre-fills
## their maps (data/kits.json, data/autotiles.json). Same keying and halo
## clean as cut_art.gd --halo, but cut on the sheet's grid, so every piece
## keeps its place in its tile (the anchor the auto-wall brush needs).
##
##   godot --headless -s tools/art/cut_kit.gd -- [kits dir] [autotiles dir]
##
## Kit sheets: 6 columns of 134 px cells, 1 px gutters, 12 rows, 70 pieces;
## row height is 32*h + 67 for wall height h (the _hN in the file name).
## Auto-tile sheets: 4 x 4 cells, 1 px gutters; piece index = S + 2*W + 4*E + 8*N
## (which corners of the diamond carry the raised material).
## Slots already edited in the Kit map tab are kept; originals are never touched.

const KITS_OUT := "res://assets/tiles/kits"
const AUTO_OUT := "res://assets/tiles/autotiles"
const CELL_W := 134
const COLS := 6
const ROWS := 12

## Sheet piece (1-based, reading order) -> slot. Same layout in every kit.
const SLOTS: Array[String] = [
	"floor", "roof",
	"wall_se", "wall_ne", "wall_sw", "wall_nw",
	"corner_out_e", "corner_out_n", "corner_out_s", "corner_out_w",
	"corner_in_e", "corner_in_n", "corner_in_s", "corner_in_w",
	"t_se", "t_sw", "cross_a", "cross_b", "t_ne", "t_nw", "cross",
	"thin_a", "thin_b", "thin_c", "thin_d", "thin_e", "thin_f", "thin_g", "thin_h", "thin_i",
	"thin_j", "thin_k", "thin_l", "thin_m", "thin_n", "thin_o", "thin_p", "thin_q", "thin_r",
	"post",
	"door_se", "door_ne", "door_sw", "door_nw", "door_thin_a", "door_thin_b",
	"stairs_a", "stairs_b", "ramp_a", "ramp_b",
	"roof_slope_a", "roof_slope_b", "roof_slope_c", "roof_slope_d", "roof_slope_e",
	"roof_slope_f", "roof_slope_g", "roof_slope_h", "roof_slope_i", "roof_slope_j",
	"roof_slope_k", "roof_slope_l", "roof_slope_m", "roof_slope_n", "roof_slope_o",
	"roof_slope_p", "roof_slope_q", "roof_slope_r", "roof_slope_s", "roof_block",
]
const UNSURE := [
	"t_se / t_sw / t_ne / t_nw / cross_a / cross_b: thick junction pieces 15-20 were told apart by eye",
	"thin_a..thin_r (22-39): partition walls and their junctions are cut but not sorted into directions yet",
	"roof_slope_a..s and roof_block (51-70) are drawn about 1.6x the size of a tile: anchor and slot are a guess, the brush uses the flat roof (piece 2) until Brian confirms",
	"the zip piece lists name 80 pieces, the sheets hold 70 (6 doors not 12, 4 stairs/ramps not 8)",
]
const MASK_NAMES: Array[String] = ["o", "s", "w", "ws", "e", "es", "ew", "esw", "n", "ns", "nw", "nsw", "ne", "nes", "new", "nesw"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var kits_dir: String = args[0] if args.size() > 0 else "res://tools/handoff/kits"
	var auto_dir: String = args[1] if args.size() > 1 else "res://tools/handoff/autotiles"
	var kits := _read("res://data/kits.json")
	var n := 0
	for f in _pngs(kits_dir):
		n += _cut_kit(kits_dir.path_join(f), kits)
	_write("res://data/kits.json", kits)
	var autos := _read("res://data/autotiles.json")
	for f in _pngs(auto_dir):
		n += _cut_auto(auto_dir.path_join(f), autos)
	_write("res://data/autotiles.json", autos)
	print("cut %d pieces: %d kits, %d auto-tile sets" % [n, kits.size(), autos.size()])
	quit(0)


func _pngs(dir: String) -> Array:
	var out: Array = Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.get_extension().to_lower() == "png")
	out.sort()
	return out


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null or not f.store_string(JSON.stringify(d, "\t", true) + "\n"):
		push_error("can't write " + path)


func _clean(path: String) -> Image:
	var img := ArtCutter.key(Image.load_from_file(ProjectSettings.globalize_path(path)))
	ArtCutter.remove_halo(img, 2)
	return img


func _save(img: Image, dir: String, file: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if img.save_png(ProjectSettings.globalize_path(dir.path_join(file))) != OK:
		push_error("can't save " + dir.path_join(file))


func _cut_kit(path: String, kits: Dictionary) -> int:
	var id := path.get_file().get_basename()
	var h := int(id.right(1)) if id.left(-1).ends_with("_h") else 0
	var img := _clean(path)
	var pitch := 32 * h + 68
	var flags: Array = UNSURE.duplicate()
	if h < 1 or h > 3 or img.get_width() != COLS * (CELL_W + 1) - 1 or img.get_height() != ROWS * pitch - 1:
		print("%s: not the 6 x 12 kit layout (%d x %d), skipped" % [id, img.get_width(), img.get_height()])
		return 0
	var slots := {}
	var made := 0
	for i in SLOTS.size():
		var piece := img.get_region(Rect2i((i % COLS) * (CELL_W + 1), (i / COLS) * pitch, CELL_W, pitch - 1))
		if piece.get_used_rect().size.x == 0:
			flags.append("piece %d (%s) is empty in the sheet" % [i + 1, SLOTS[i]])
			continue
		var file := "%02d_%s" % [i + 1, SLOTS[i]]
		_save(piece, KITS_OUT.path_join(id), file + ".png")
		slots[SLOTS[i]] = file
		made += 1
	# Floor slab: how far its top face sits above the level the walls stand on.
	var floor_top := img.get_region(Rect2i(0, 0, CELL_W, pitch - 1)).get_used_rect().position.y
	var old: Dictionary = kits.get(id, {})
	var kept: Dictionary = old.get("slots", {})
	for s: String in kept:
		if FileAccess.file_exists(KITS_OUT.path_join(id).path_join(str(kept[s]) + ".png")):
			slots[s] = kept[s]
	kits[id] = {
		"name": id.left(-3).replace("_", " "), "family": id.left(-3), "height": h,
		"sheet": path.trim_prefix("res://"), "px": 64,
		"anchor": [50.5, 32.0 * h + 24.5],
		"slab": (32 * h + 8) - floor_top,
		"slots": slots, "flags": old.get("flags", flags),
	}
	print("%s: %d pieces, height %d" % [id, made, h])
	return made


func _cut_auto(path: String, autos: Dictionary) -> int:
	var id := path.get_file().get_basename()
	var img := _clean(path)
	var tw := (img.get_width() - 3) / 4
	var th := (img.get_height() - 3) / 4
	if (img.get_width() - 3) % 4 != 0 or (img.get_height() - 3) % 4 != 0:
		print("%s: not a 4 x 4 sheet with 1 px gutters, skipped" % id)
		return 0
	var pieces := {}
	for i in 16:
		var piece := img.get_region(Rect2i((i % 4) * (tw + 1), (i / 4) * (th + 1), tw, th))
		var file := "at_" + MASK_NAMES[i]
		_save(piece, AUTO_OUT.path_join(id), file + ".png")
		pieces[str(i)] = file
	# The raised material starts at the top of the cell; the flat one sits `lift` px lower.
	var lift := img.get_region(Rect2i(0, 0, tw, th)).get_used_rect().position.y
	var parts := id.split("_to_")
	var old: Dictionary = autos.get(id, {})
	autos[id] = {
		"name": id.replace("_", " "), "low": parts[1] if parts.size() > 1 else id, "high": parts[0] if parts.size() > 1 else id,
		"sheet": path.trim_prefix("res://"), "px": tw, "anchor": [tw * 0.5, tw * 0.25], "lift": lift,
		"pieces": old.get("pieces", pieces),
		"flags": old.get("flags", ["layout read from the sheet: piece = S + 2*W + 4*E + 8*N (corners carrying the raised material)"]),
	}
	print("%s: 16 tiles of %d x %d" % [id, tw, th])
	return 16
