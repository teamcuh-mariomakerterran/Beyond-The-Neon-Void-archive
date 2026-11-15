extends SceneTree
## Which wall height (1, 2 or 3 tiles) a building-kit sheet was built at.
## In Brian's 64 px kits one tile of height is always 32 px (the 2:1 view fixes
## it) plus a pixel or two of outline, so the tallest wall edge / 33 is the
## set's height. The stair piece is reported as a cross-check only: in the
## "towering" kits it rises as tall as the walls. Only reads.
##
##   godot --headless -s tools/art/kit_height.gd -- <sheet or folder of sheets>

const EXT := ["png", "webp"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: godot --headless -s tools/art/kit_height.gd -- <sheet or folder>")
		quit(1)
		return
	var src: String = args[0]
	var files: Array[String] = []
	if FileAccess.file_exists(src):
		files.append(src)
	else:
		for f in DirAccess.get_files_at(src):
			if f.get_extension().to_lower() in EXT:
				files.append(src.path_join(f))
	files.sort()
	for f in files:
		var r := measure(Image.load_from_file(f))
		if r.is_empty():
			print("%s: no wall pieces found (can't tell)" % f.get_file())
		else:
			print("%s: height %d  (tallest wall %d px, one tile = %d px; stair rises %d px)" % [f.get_file(), r["height"], r["wall"], int(TILE_PX), r["rise"]])
	quit(0)


## Screen px of one tile of height in 64 px kit art (32 + outline).
const TILE_PX := 33.0


## {height, rise, wall} for a sheet ({} if it has no wall pieces). rise is the
## stair's back edge (0 without one), a cross-check only.
static func measure(src: Image) -> Dictionary:
	if src == null:
		return {}
	var img := ArtCutter.key(src)
	var rises: Array[int] = []
	var wall := 0
	for r: Rect2i in ArtCutter.pieces(img):
		var l := _edge(img, r.position.x + 2, r)
		var rt := _edge(img, r.end.x - 3, r)
		var hi := maxi(l, rt)
		var lo := mini(l, rt)
		if hi >= 12 and lo * 10 <= hi * 3:
			rises.append(hi)  # a ramp shape: one side tall, the other at floor level
		elif lo * 10 >= hi * 7:
			wall = maxi(wall, lo)  # both sides tall: a wall or block
	if wall == 0:
		return {}
	rises.sort()
	var rise := rises[rises.size() / 2] if not rises.is_empty() else 0
	return {"height": clampi(roundi(float(wall) / TILE_PX), 1, 3), "rise": rise, "wall": wall}


## Opaque run (top to bottom) of one column inside a piece.
static func _edge(img: Image, x: int, r: Rect2i) -> int:
	var top := -1
	var bot := -1
	for y in range(r.position.y, r.end.y):
		if img.get_pixel(x, y).a > 0.5:
			if top < 0:
				top = y
			bot = y
	return bot - top + 1 if top >= 0 else 0
