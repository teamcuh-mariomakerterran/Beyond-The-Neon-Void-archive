class_name AutoWall
extends RefCounted
## Auto-wall brush: paint a building's floor cells and its walls build round
## the outline from a kit's pieces (KitMap). Buildings live in
## WorldMap.buildings; everything generated is baked into the map (wall tiles
## in `tiles`, roofs / upper storeys / door frames in `roofs`, movement and
## line-of-sight rules in `gameplay`), so battles and exploration need no
## special case. Generated entries carry {"b": building id} and are rebuilt
## from the building record whenever it changes.
##
## Walls stand on the ring of cells just outside the floor, hugging it (they
## are half a cell thick). 64 px kit art: one tile of wall height is 32 art px,
## which is 2 height layers at the renderer's 2x scale.
##
##   building = {id, kit, height (1-3), z, cells [[x, y]..], storeys, roof,
##               roof_style ("flat" | "pitched"), doors [[x, y]..],
##               inner [[x, y]..] (partition walls), stairs [{cell: [x, y], dir: "ne"}..]}
##
## Levels: `z` is the ground the walls stand on. The kit's floor piece is a slab,
## so the floor people walk on is KitMap.floor_layers(kit) above it. A storey is
## 2 layers per tile of wall height. Stairs are two cells long and climb one
## storey. Every storey's floor is walkable: upper floors are cells on their own
## level of the battle grid (IsometricGrid.at_level), added by add_levels() and
## joined to the storey below through the stair run. A run opens a hole in the
## floor above it. A stair run is {cell, dir, level (storey it starts on), kind ("stairs" | "ramp")}.

const NE := Vector2i(0, -1)
const SE := Vector2i(1, 0)
const SW := Vector2i(0, 1)
const NW := Vector2i(-1, 0)
const DIRV := {"ne": NE, "se": SE, "sw": SW, "nw": NW}
const OPPOSITE := {"ne": "sw", "sw": "ne", "se": "nw", "nw": "se"}
## Height layers per tile of wall height.
const LAYERS_PER_TILE := 2
## Ring cell with floor on exactly one side -> slot (the wall hugs that side).
const SIDE_SLOT := {NE: "wall_ne", SE: "wall_se", SW: "wall_sw", NW: "wall_nw"}
## Ring cell touching the floor only diagonally -> the corner post toward it.
const DIAG_SLOT := {Vector2i(-1, -1): "corner_out_n", Vector2i(1, -1): "corner_out_e", Vector2i(1, 1): "corner_out_s", Vector2i(-1, 1): "corner_out_w"}
## Second cell a two-cell door piece covers, from its anchor cell.
const DOOR_EXT := {"wall_se": NE, "wall_nw": NE, "wall_ne": SE, "wall_sw": SE}
## Walls between the camera and the room (the building's SW and SE sides):
## these fade when someone is inside.
const FRONT := ["wall_nw", "wall_ne", "corner_in_n", "corner_out_n"]
## Stair / ramp piece per climb direction: [piece letter, mirrored].
const STAIR_PIECE := {"ne": ["a", false], "nw": ["a", true], "se": ["b", false], "sw": ["b", true]}
## Roof corner where two neighbouring sides are open.
const HIP_SLOT := {"ne_nw": "hip_n", "ne_se": "hip_e", "se_sw": "hip_s", "sw_nw": "hip_w"}
## Roof inner corner: the one diagonal that is open -> valley.
const VALLEY_SLOT := {Vector2i(-1, -1): "valley_n", Vector2i(1, -1): "valley_e", Vector2i(1, 1): "valley_s", Vector2i(-1, 1): "valley_w"}


static func find(world: WorldMap, building_id: String) -> Dictionary:
	for b: Dictionary in world.buildings:
		if str(b.get("id", "")) == building_id:
			return b
	return {}


static func cells_of(b: Dictionary) -> Dictionary:
	var out := {}
	for c: Array in b.get("cells", []):
		out[Vector2i(int(c[0]), int(c[1]))] = true
	return out


## Building whose floor holds `cell` ({} if none).
static func building_at(world: WorldMap, cell: Vector2i) -> Dictionary:
	for b: Dictionary in world.buildings:
		for c: Array in b.get("cells", []):
			if int(c[0]) == cell.x and int(c[1]) == cell.y:
				return b
	return {}


## Id of the roofed building `cell` is inside ("" outdoors or under open sky).
static func inside_id(world: WorldMap, cell: Vector2i) -> String:
	var b := building_at(world, cell)
	return str(b.get("id", "")) if bool(b.get("roof", false)) or int(b.get("storeys", 1)) > 1 else ""


## [x, y] is the ground storey, [x, y, n] storey n: the cells of a list on one storey.
static func cells_on(list: Array, level: int) -> Dictionary:
	var out := {}
	for c: Array in list:
		if (int(c[2]) if c.size() > 2 else 0) == level:
			out[Vector2i(int(c[0]), int(c[1]))] = true
	return out


static func _key(cell: Vector2i, level: int) -> Array:
	return [cell.x, cell.y, level] if level > 0 else [cell.x, cell.y]


## Paints (or erases) a partition wall on a floor cell of a building, on any storey.
static func paint_inner(world: WorldMap, cell: Vector2i, erase_it: bool = false, level: int = 0) -> Array[Vector2i]:
	var b := building_at(world, cell)
	if b.is_empty() or level >= maxi(int(b.get("storeys", 1)), 1):
		return []
	var inner: Array = b.get("inner", [])
	var k := _key(cell, level)
	if erase_it == inner.has(k):
		if erase_it:
			inner.erase(k)
			(b.get("inner_doors", []) as Array).erase(k)
		else:
			inner.append(k)
		b["inner"] = inner
		return rebuild(world, b)
	return []


## Puts a prop (or any map object) on a storey of the building under it: it is
## drawn on that floor, hides with it, and blocks that floor's cell only.
static func set_object_level(world: WorldMap, obj: Dictionary, level: int) -> void:
	var c: Array = obj.get("cell", [0, 0])
	var b := building_at(world, Vector2i(int(c[0]), int(c[1])))
	if b.is_empty() or level <= 0:
		obj.erase("level")
		obj.erase("b")
		obj["z"] = int(plan(b)["zf"]) if not b.is_empty() else int(obj.get("z", 0))
		return
	var p := plan(b)
	level = mini(level, int(p["storeys"]) - 1)
	obj["level"] = level
	obj["b"] = str(b["id"])
	obj["z"] = int(p["zf"]) + level * int(p["pitch"])


## STAIRS: puts a two-cell stair (or ramp) run at `cell` on storey `level`,
## climbing toward `dir`, or takes away the run that holds the cell on that
## storey. Needs a floor cell before it and after it; adds the storey it leads to.
static func toggle_stairs(world: WorldMap, cell: Vector2i, dir: String, level: int = 0, kind: String = "stairs") -> Array[Vector2i]:
	var b := building_at(world, cell)
	if b.is_empty() or not DIRV.has(dir) or level < 0:
		return []
	var runs: Array = b.get("stairs", [])
	for r: Dictionary in runs:
		if int(r.get("level", 0)) == level and stair_cells(r).has(cell):
			runs.erase(r)
			b["stairs"] = runs
			return rebuild(world, b)
	var run := {"cell": [cell.x, cell.y], "dir": dir, "level": level, "kind": kind, "len": int(plan(b)["ph"]) * 2}
	if not _stairs_fit(cells_of(b), run) or not _stairs_clear(runs, run):
		return []
	runs.append(run)
	b["stairs"] = runs
	if int(b.get("storeys", 1)) < level + 2:
		b["storeys"] = level + 2
		b["roof"] = true
	if level == 0:
		for c: Vector2i in stair_cells(run):
			(b.get("inner", []) as Array).erase([c.x, c.y])
	return rebuild(world, b)


## A new run can't share cells with a run on its storey, stand on the hole of
## the run below, or arrive in one; nor may its own hole swallow those of the run above.
static func _stairs_clear(runs: Array, run: Dictionary) -> bool:
	var lv := int(run.get("level", 0))
	var d: Vector2i = DIRV[str(run["dir"])]
	var cs := stair_cells(run)
	var mine: Array = [cs[0] - d] + Array(cs) + [cs[cs.size() - 1] + d]
	for r: Dictionary in runs:
		var other := stair_cells(r)
		var od: Vector2i = DIRV[str(r["dir"])]
		var olv := int(r.get("level", 0))
		if olv == lv - 1 and cs.has(other[other.size() - 1] + od):
			return false  # would stand where the run below arrives
		for c: Vector2i in other:
			if (olv == lv and cs.has(c)) or (olv == lv - 1 and mine.has(c)) or (olv == lv and c == cs[cs.size() - 1] + d):
				return false
		if olv == lv + 1 and (cs.has(other[0] - od) or other.any(func(oc: Vector2i) -> bool: return cs.has(oc))):
			return false
		if olv == lv and (cs.has(other[other.size() - 1] + od) or cs.has(other[0] - od)):
			return false
	return true


## The cells of a stair flight, lowest first. One stair piece is two cells long
## and climbs one tile (2 layers), so a flight to the next storey is one piece
## per tile of wall height, end to end: `len` cells (2 for a 1-tile wall, 6 for 3).
static func stair_cells(run: Dictionary) -> Array[Vector2i]:
	var low := Vector2i(int(run["cell"][0]), int(run["cell"][1]))
	var d: Vector2i = DIRV[str(run["dir"])]
	var out: Array[Vector2i] = []
	for i in maxi(int(run.get("len", 2)), 2):
		out.append(low + d * i)
	return out


static func _stairs_fit(floor_cells: Dictionary, run: Dictionary) -> bool:
	var cs := stair_cells(run)
	var d: Vector2i = DIRV[str(run["dir"])]
	for c in cs:
		if not floor_cells.has(c):
			return false
	return floor_cells.has(cs[0] - d) and floor_cells.has(cs[cs.size() - 1] + d)


## A ground slope: `cell` climbs toward `dir`. kind "roof" uses the kit's sloped
## roof piece (one cell, 2 layers); "ramp" and "stairs" use the two-cell ramp /
## stair pieces (one tile of wall height per cell, so one storey over the run).
static func place_slope(world: WorldMap, cell: Vector2i, kit_id: String, dir: String, z: int, kind: String = "roof") -> Array[Vector2i]:
	if not DIRV.has(dir) or not world.in_bounds(cell) or not building_at(world, cell).is_empty():
		return []
	var d: Vector2i = DIRV[dir]
	var slab := float(KitMap.kit(kit_id).get("slab", 0))
	if kind == "roof":
		var piece := KitMap.resolve(kit_id, "slope_" + str(OPPOSITE[dir]))
		if piece.is_empty():
			return []
		remove_slope(world, cell)
		var o := {"part": "slope", "rise": 1, "up": slab, "sl": dir}
		if bool(piece["flip"]):
			o["flip"] = true
		world.set_tile(cell, z + 1, str(piece["tile"]), o)
		world.gameplay[cell] = {"walkable": true, "height": z + 1, "slope": [d.x, d.y], "rise": 2, "sl": true}
		return [cell]
	var info: Array = STAIR_PIECE[dir]
	var run_piece := KitMap.resolve(kit_id, ("ramp_" if kind == "ramp" else "stairs_") + str(info[0]))
	var high := cell + d
	if run_piece.is_empty() or not world.in_bounds(high) or not building_at(world, high).is_empty():
		return []
	remove_slope(world, cell)
	remove_slope(world, high)
	var so := {"part": "slope", "rise": 1, "up": slab + STAIR_UP, "sl": dir}
	if bool(info[1]) != bool(run_piece["flip"]):
		so["flip"] = true
	var front_cell := high if d.x + d.y > 0 else cell
	if front_cell != cell:
		so["at"] = [-d.x, -d.y]
	world.set_tile(front_cell, z + 1, str(run_piece["tile"]), so)
	var rules := _stair_rules({"dir": dir}, z, 2)
	var cs: Array[Vector2i] = [cell, high]
	for i in 2:
		var g: Dictionary = rules[i]
		g["walkable"] = true
		g["sl"] = true
		g["pair"] = [cs[1 - i].x, cs[1 - i].y]
		world.gameplay[cs[i]] = g
	return cs


static func remove_slope(world: WorldMap, cell: Vector2i) -> Array[Vector2i]:
	var g: Dictionary = world.gameplay.get(cell, {})
	if not bool(g.get("sl", false)):
		return []
	var out: Array[Vector2i] = [cell]
	if g.get("pair") is Array:
		out.append(Vector2i(int(g["pair"][0]), int(g["pair"][1])))
	for c in out:
		world.gameplay.erase(c)
		for e: Array in world.stack_at(c).duplicate():
			if e.size() > 2 and str((e[2] as Dictionary).get("part", "")) == "slope":
				world.remove_tile(c, int(e[0]))
	return out


## Building whose wall ring holds `cell` ({} if none).
static func wall_owner(world: WorldMap, cell: Vector2i) -> Dictionary:
	var g: Dictionary = world.gameplay.get(cell, {})
	return find(world, str(g["b"])) if g.has("b") else {}


## Paints a floor cell: joins a building of the same kit and level it touches,
## or starts a new one. Returns the cells to redraw.
static func paint(world: WorldMap, cell: Vector2i, kit_id: String, height: int, z: int, roof: bool = true) -> Array[Vector2i]:
	if not world.in_bounds(cell) or KitMap.kit(kit_id).is_empty():
		return []
	var b := building_at(world, cell)
	if b.is_empty():
		for other: Dictionary in world.buildings:
			if str(other.get("kit", "")) != kit_id or int(other.get("z", 0)) != z:
				continue
			var oc := cells_of(other)
			for d: Vector2i in [NE, SE, SW, NW]:
				if oc.has(cell + d):
					b = other
					break
			if not b.is_empty():
				break
	if b.is_empty():
		b = {"id": world.next_id("b"), "kit": kit_id, "height": clampi(height, 1, 3), "z": z,
			"cells": [], "storeys": 1, "roof": roof, "doors": []}
		world.buildings.append(b)
	elif cells_of(b).has(cell):
		return []
	var before := touched(b)
	(b["cells"] as Array).append([cell.x, cell.y])
	(b["doors"] as Array).erase([cell.x, cell.y])
	return _merge(before, rebuild(world, b))


## Takes a floor cell out of its building (the building goes with its last cell).
static func erase(world: WorldMap, cell: Vector2i) -> Array[Vector2i]:
	var b := building_at(world, cell)
	if b.is_empty():
		return []
	var before := touched(b)
	(b["cells"] as Array).erase([cell.x, cell.y])
	(b.get("inner", []) as Array).erase([cell.x, cell.y])
	(b.get("inner_doors", []) as Array).erase([cell.x, cell.y])
	var left := cells_of(b)
	b["stairs"] = (b.get("stairs", []) as Array).filter(func(r: Dictionary) -> bool: return _stairs_fit(left, r))
	clear(world, b, before)
	if (b["cells"] as Array).is_empty():
		world.buildings.erase(b)
		return before
	return _merge(before, rebuild(world, b))


## "Add storey": the roof becomes the next floor, with walls and a roof above it.
static func add_storey(world: WorldMap, building_id: String, by: int = 1) -> Array[Vector2i]:
	var b := find(world, building_id)
	if b.is_empty():
		return []
	b["storeys"] = clampi(int(b.get("storeys", 1)) + by, 1, 6)
	b["roof"] = true
	return rebuild(world, b)


## Clicking a wall: puts a door there, or takes it away. Returns redraw cells.
## A partition wall takes a thin door the same way (two cells of a straight run).
static func toggle_door(world: WorldMap, cell: Vector2i, level: int = 0) -> Array[Vector2i]:
	var ib := building_at(world, cell)
	if not ib.is_empty():
		var idoors: Array = ib.get("inner_doors", [])
		var k := _key(cell, level)
		if idoors.has(k):
			idoors.erase(k)
		elif (ib.get("inner", []) as Array).has(k):
			idoors.append(k)
		else:
			# A click on the open half of a thin door closes the door.
			var hit := false
			for dc: Array in idoors.duplicate():
				if (int(dc[2]) if dc.size() > 2 else 0) == level and absi(int(dc[0]) - cell.x) + absi(int(dc[1]) - cell.y) == 1:
					idoors.erase(dc)
					hit = true
					break
			if not hit:
				return []
		ib["inner_doors"] = idoors
		return rebuild(world, ib)
	var b := wall_owner(world, cell)
	if b.is_empty():
		return []
	var doors: Array = b["doors"]
	var pair := door_cells(world, b, cell)
	var had := false
	for c: Vector2i in pair:
		if doors.has([c.x, c.y]):
			doors.erase([c.x, c.y])
			had = true
	if not had:
		if _ring_slot(cells_of(b), cell) not in DOOR_EXT:
			return []  # corners and posts can't hold a door
		doors.append([cell.x, cell.y])
	return rebuild(world, b)


## The cells one door at `cell` opens: two along the wall when the run allows
## (the door pieces are two cells wide), else just the cell. First = the piece's anchor.
static func door_cells(_world: WorldMap, b: Dictionary, cell: Vector2i) -> Array[Vector2i]:
	var floor_cells := cells_of(b)
	var slot := _ring_slot(floor_cells, cell)
	if slot not in DOOR_EXT:
		return [cell]
	var ext: Vector2i = DOOR_EXT[slot]
	if _ring_slot(floor_cells, cell + ext) == slot:
		return [cell, cell + ext]
	if _ring_slot(floor_cells, cell - ext) == slot:
		return [cell - ext, cell]
	return [cell]


## Slot for a ring cell from where the floor is ("" = not on the ring).
static func _ring_slot(floor_cells: Dictionary, cell: Vector2i) -> String:
	if floor_cells.has(cell):
		return ""
	var sides: Array[Vector2i] = []
	for d: Vector2i in [NE, SE, SW, NW]:
		if floor_cells.has(cell + d):
			sides.append(d)
	if sides.size() == 1:
		return SIDE_SLOT[sides[0]]
	if sides.size() == 2:
		if sides.has(SW) and sides.has(SE): return "corner_in_s"
		if sides.has(NW) and sides.has(NE): return "corner_in_n"
		if sides.has(NE) and sides.has(SE): return "corner_in_e"
		if sides.has(NW) and sides.has(SW): return "corner_in_w"
	if sides.size() >= 2:
		return "cross"
	var diags: Array[Vector2i] = []
	for d: Vector2i in DIAG_SLOT:
		if floor_cells.has(cell + d):
			diags.append(d)
	if diags.size() == 1:
		return DIAG_SLOT[diags[0]]
	return "cross" if diags.size() > 1 else ""


## {cell: slot} for the whole wall ring of a floor.
static func ring(floor_cells: Dictionary) -> Dictionary:
	var out := {}
	for c: Vector2i in floor_cells:
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var r := c + Vector2i(dx, dy)
				if not out.has(r) and not floor_cells.has(r):
					var s := _ring_slot(floor_cells, r)
					if s != "":
						out[r] = s
	return out


## Every cell a building's art can sit on (floor + ring).
static func touched(b: Dictionary) -> Array[Vector2i]:
	var floor_cells := cells_of(b)
	var out: Array[Vector2i] = []
	out.assign(floor_cells.keys())
	for r: Vector2i in ring(floor_cells):
		out.append(r)
	return out


static func _merge(a: Array[Vector2i], b: Array[Vector2i]) -> Array[Vector2i]:
	var seen := {}
	for c in a + b:
		seen[c] = true
	var out: Array[Vector2i] = []
	out.assign(seen.keys())
	return out


## Removes everything generated for a building from the given cells (floor
## tiles stay as plain ground).
static func clear(world: WorldMap, b: Dictionary, cells: Array[Vector2i]) -> void:
	var id := str(b.get("id", ""))
	for c in cells:
		for e: Array in world.stack_at(c).duplicate():
			var o: Dictionary = e[2] if e.size() > 2 and e[2] is Dictionary else {}
			if str(o.get("b", "")) != id:
				continue
			if str(o.get("part", "")) == "floor" and int(e[0]) <= int(b.get("z", 0)):
				world.set_tile(c, int(e[0]), str(e[1]))
			else:
				world.remove_tile(c, int(e[0]))
		if world.roofs.has(c):
			var keep: Array = (world.roofs[c] as Array).filter(func(e: Array) -> bool:
				return str((e[2] as Dictionary).get("b", "")) != id)
			if keep.is_empty():
				world.roofs.erase(c)
			else:
				world.roofs[c] = keep
		if str(world.gameplay.get(c, {}).get("b", "")) == id:
			world.gameplay.erase(c)


static func _overlay(world: WorldMap, cell: Vector2i, z: int, tile_id: String, opts: Dictionary) -> void:
	if not world.in_bounds(cell):
		return
	var s: Array = world.roofs.get(cell, [])
	s.append([z, tile_id, opts])
	s.sort_custom(func(a: Array, b2: Array) -> bool: return int(a[0]) < int(b2[0]))
	world.roofs[cell] = s


## Thin partition piece for a set of arms (subset of ne / se / sw / nw):
## {tile, under} where `under` is a second piece drawn behind (two single arms
## make a straight run, which the sheets have no piece for).
static func partition(kit_id: String, arms: Array, height: int) -> Dictionary:
	var names: Array[String] = []
	for d in KitMap.DIRS:
		if arms.has(d):
			names.append(d)
	if names.is_empty():
		return {"tile": str(KitMap.resolve(kit_id, "thin_post", height).get("tile", "")), "flip": false}
	var slot := "thin_cross" if names.size() == 4 else "thin_" + "_".join(names)
	var piece := KitMap.resolve(kit_id, slot, height)
	if not piece.is_empty():
		return {"tile": str(piece["tile"]), "flip": bool(piece["flip"])}
	# Straight run: the back arm under the front arm.
	var back := KitMap.resolve(kit_id, "thin_" + names[names.size() - 1] if names[0] == "ne" and names.size() == 2 and names[1] == "sw" else "thin_" + names[0], height)
	var front := KitMap.resolve(kit_id, "thin_" + ("sw" if names.has("sw") and names.has("ne") else "se"), height)
	if names == ["ne", "sw"]:
		back = KitMap.resolve(kit_id, "thin_ne", height)
	elif names == ["se", "nw"]:
		back = KitMap.resolve(kit_id, "thin_nw", height)
	if back.is_empty() or front.is_empty():
		return {"tile": str(KitMap.resolve(kit_id, "thin_post", height).get("tile", "")), "flip": false}
	return {"tile": str(front["tile"]), "flip": false, "under": str(back["tile"])}


## Everything both the art and the grid need to know about a building's levels.
static func plan(b: Dictionary) -> Dictionary:
	var kit_id := str(b["kit"])
	var want_h := clampi(int(b.get("height", 1)), 1, 3)
	var real_kit := str(KitMap.resolve(kit_id, "wall_se", want_h).get("kit", kit_id))
	# The pieces' own height decides the rise (a borrowed height may differ from the one asked for).
	var ph := int(KitMap.kit(real_kit).get("height", want_h))
	var floor_cells := cells_of(b)
	var storeys := maxi(int(b.get("storeys", 1)), 1)
	var runs: Array = (b.get("stairs", []) as Array).filter(func(r: Dictionary) -> bool:
		return storeys > int(r.get("level", 0)) + 1 and _stairs_fit(floor_cells, r))
	var holes := {}  # storey -> {cell: true}: the floor of that storey is open there
	for r: Dictionary in runs:
		var up := int(r.get("level", 0)) + 1
		if not holes.has(up):
			holes[up] = {}
		for c in stair_cells(r):
			holes[up][c] = true
	var fl := KitMap.floor_layers(real_kit)
	return {"kit": kit_id, "want_h": want_h, "ph": ph, "pitch": ph * LAYERS_PER_TILE, "fl": fl,
		"zf": int(b.get("z", 0)) + fl, "slab": float(KitMap.kit(real_kit).get("slab", 0)),
		"storeys": storeys, "floor": floor_cells, "runs": runs, "holes": holes}


## Height and slope of each cell of a stair flight standing on a floor at
## `base_z`: every cell climbs one layer (a two-cell piece climbs one tile).
static func _stair_rules(run: Dictionary, base_z: int, count: int) -> Array:
	var d: Vector2i = DIRV[str(run["dir"])]
	var out: Array = []
	for i in count:
		out.append({"height": base_z + i, "lift": 0.5, "slope": [d.x, d.y], "rise": 1, "bias": 2})
	return out


## Adds every building's upper storeys to a battle grid: one cell per floor
## cell per storey (not over stair holes), the stair runs that start upstairs,
## and the links that join the top of each run to the floor it arrives on.
static func add_levels(world: WorldMap, grid: IsometricGrid) -> void:
	for b: Dictionary in world.buildings:
		var p := plan(b)
		var id := str(b.get("id", ""))
		for s in range(1, int(p["storeys"])):
			var hole: Dictionary = (p["holes"] as Dictionary).get(s, {})
			var ip := inner_plan(b, p, ring(p["floor"]), {}, s)
			var blocked := {}
			for c: Vector2i in ip["inner"]:
				if not (ip["open"] as Dictionary).has(c):
					blocked[c] = true
			for c: Vector2i in p["floor"]:
				if hole.has(c):
					continue
				var cell := IsometricGrid.Cell.new()
				cell.coords = IsometricGrid.at_level(c, s)
				cell.height = clampi(int(p["zf"]) + s * int(p["pitch"]), IsometricGrid.MIN_HEIGHT, IsometricGrid.MAX_HEIGHT)
				cell.draw_bias = 2
				cell.building = id
				if blocked.has(c):
					cell.walkable = false
					cell.blocks_los = true
					cell.cover = IsometricGrid.COVER_FULL
				grid.add_level_cell(cell)
		for r: Dictionary in p["runs"]:
			var lv := int(r.get("level", 0))
			var cs := stair_cells(r)
			var d: Vector2i = DIRV[str(r["dir"])]
			if lv > 0:
				var rules := _stair_rules(r, int(p["zf"]) + lv * int(p["pitch"]), cs.size())
				for i in cs.size():
					var sc := grid.get_cell(IsometricGrid.at_level(cs[i], lv))
					if sc == null:
						continue
					sc.height = int(rules[i]["height"])
					sc.lift = float(rules[i]["lift"])
					sc.slope = d
					sc.slope_rise = int(rules[i]["rise"])
			var arrive := IsometricGrid.at_level(cs[cs.size() - 1] + d, lv + 1)
			if grid.get_cell(arrive) != null:
				grid.add_link(IsometricGrid.at_level(cs[cs.size() - 1], lv), arrive)
	# Props and structures placed on an upper floor stand on that floor's cell.
	for o: Dictionary in world.objects:
		var lv := int(o.get("level", 0))
		if lv <= 0:
			continue
		for oc in WorldMap.footprint_cells(o):
			var gc := grid.get_cell(IsometricGrid.at_level(oc, lv))
			if gc == null:
				continue
			if str(o.get("kind", "")) in ["structure", "location"]:
				gc.walkable = false
				gc.blocks_los = true
				gc.cover = IsometricGrid.COVER_FULL
			elif str(o.get("kind", "")) in ["prop", "loot"]:
				gc.prop_id = str(o.get("id", ""))


## Partitions of one storey: {inner (cells), arms (cell -> sides it reaches
## toward), open (cell -> [anchor cell, door slot] for cells a thin door opens)}.
static func inner_plan(b: Dictionary, p: Dictionary, ring_cells: Dictionary, wall_open: Dictionary, level: int) -> Dictionary:
	var floor_cells: Dictionary = p["floor"]
	var inner := {}
	for c: Vector2i in cells_on(b.get("inner", []), level):
		if floor_cells.has(c):
			inner[c] = true
	for r: Dictionary in p["runs"]:
		if int(r.get("level", 0)) == level:
			for c in stair_cells(r):
				inner.erase(c)
	for c: Vector2i in (p["holes"] as Dictionary).get(level, {}):
		inner.erase(c)
	var arms_of := {}
	for c: Vector2i in inner:
		var arms: Array = []
		for dn: String in DIRV:
			var n: Vector2i = c + (DIRV[dn] as Vector2i)
			if inner.has(n) or (ring_cells.has(n) and not wall_open.has(n)):
				arms.append(dn)
		arms_of[c] = arms
	var inner_open := {}
	for c: Vector2i in cells_on(b.get("inner_doors", []), level):
		for axis: Array in [[SE, "door_thin_a", ["se", "nw"]], [NE, "door_thin_b", ["ne", "sw"]]]:
			var along: Vector2i = axis[0]
			for anchor: Vector2i in [c, c - along]:
				if inner_open.has(c) or not inner.has(anchor) or not inner.has(anchor + along):
					continue
				if _has_arms(arms_of[anchor], axis[2]) and _has_arms(arms_of[anchor + along], axis[2]) and not inner_open.has(anchor) and not inner_open.has(anchor + along):
					inner_open[anchor] = [anchor, axis[1]]
					inner_open[anchor + along] = [anchor, axis[1]]
	return {"inner": inner, "arms": arms_of, "open": inner_open}


## Rebuilds a building's floor, walls, partitions, doors, stairs, storeys and roof from its record.
static func rebuild(world: WorldMap, b: Dictionary) -> Array[Vector2i]:
	var cells := touched(b)
	clear(world, b, cells)
	var id := str(b["id"])
	var p := plan(b)
	var kit_id := str(p["kit"])
	var want_h := int(p["want_h"])
	var z0 := int(b.get("z", 0))
	var floor_cells: Dictionary = p["floor"]
	var ring_cells := ring(floor_cells)
	var floor_tile := str(KitMap.resolve(kit_id, "floor", want_h).get("tile", ""))
	var roof_tile := str(KitMap.resolve(kit_id, "roof", want_h).get("tile", floor_tile))
	var ph := int(p["ph"])
	var pitch := int(p["pitch"])  # layers per storey
	var fl := int(p["fl"])
	var zf := int(p["zf"])  # the floor people stand on
	var slab := float(p["slab"])
	var storeys := int(p["storeys"])
	var runs: Array = p["runs"]
	var holes: Dictionary = p["holes"]
	# Doors: clicked cells widen to the two cells a door piece spans.
	var open := {}  # cell -> anchor cell of its door
	for d: Array in b.get("doors", []):
		var pair := door_cells(world, b, Vector2i(int(d[0]), int(d[1])))
		if ring_cells.has(pair[0]):
			for c: Vector2i in pair:
				open[c] = pair[0]
	for c: Vector2i in floor_cells:
		if floor_tile != "":
			world.set_tile(c, zf, floor_tile, {"b": id, "part": "floor"})
	# Partition walls and the thin doors in them, storey by storey.
	var inner_by := {}  # storey -> inner_plan
	for s in storeys:
		var ip := inner_plan(b, p, ring_cells, open if s == 0 else {}, s)
		inner_by[s] = ip
		var base_z := zf + s * pitch
		for c: Vector2i in ip["inner"]:
			if (ip["open"] as Dictionary).has(c):
				if ip["open"][c][0] == c:
					var td := KitMap.resolve(kit_id, str(ip["open"][c][1]), want_h)
					if not td.is_empty():
						_overlay(world, c, base_z + 1, str(td["tile"]), {"b": id, "part": "door", "rise": 1, "lv": s})
				continue
			var part := partition(kit_id, ip["arms"][c], want_h)
			if str(part.get("tile", "")) == "":
				continue
			var po := {"b": id, "part": "inner", "rise": 1}
			if part.has("under"):
				po["under"] = part["under"]
			if bool(part.get("flip", false)):
				po["flip"] = true
			if s == 0:
				world.set_tile(c, zf + 1, str(part["tile"]), po)
				world.gameplay[c] = {"walkable": false, "blocks_los": true, "cover": 2, "b": id}
			else:
				po["lv"] = s
				_overlay(world, c, base_z + 1, str(part["tile"]), po)  # add_levels blocks the cell
	var inner: Dictionary = inner_by[0]["inner"]
	var inner_open: Dictionary = inner_by[0]["open"]
	for r: Dictionary in runs:
		var cs := stair_cells(r)
		var dname := str(r["dir"])
		var d: Vector2i = DIRV[dname]
		var lv := int(r.get("level", 0))
		var base_z := zf + lv * pitch
		var info: Array = STAIR_PIECE[dname]
		var piece := KitMap.resolve(kit_id, ("ramp_" if str(r.get("kind", "stairs")) == "ramp" else "stairs_") + str(info[0]), want_h)
		# One piece per tile of height, each two cells further on and one tile higher.
		for j in (cs.size() / 2 if not piece.is_empty() else 0):
			var so := {"b": id, "part": "stairs", "rise": 1, "up": slab + STAIR_UP}
			if bool(info[1]) != bool(piece["flip"]):
				so["flip"] = true
			# Stored on the cell nearer the camera so the other cell's floor can't cover it.
			var first := cs[j * 2]
			var front_cell := cs[j * 2 + 1] if d.x + d.y > 0 else first
			if front_cell != first:
				so["at"] = [-d.x, -d.y]
			var pz := base_z + 1 + j * LAYERS_PER_TILE
			if lv == 0 and j == 0:
				world.set_tile(front_cell, pz, str(piece["tile"]), so)
			else:
				so["lv"] = lv
				_overlay(world, front_cell, pz, str(piece["tile"]), so)
		if lv == 0:
			var rules := _stair_rules(r, zf, cs.size())
			for i in cs.size():
				var g: Dictionary = rules[i]
				g["walkable"] = true
				g["b"] = id
				world.gameplay[cs[i]] = g
	for c: Vector2i in ring_cells:
		if not world.in_bounds(c):
			continue
		var slot: String = ring_cells[c]
		if world.stack_at(c).is_empty() and floor_tile != "":
			world.set_tile(c, z0, floor_tile)  # footing under the wall
		var piece := KitMap.resolve(kit_id, slot, want_h)
		if slot.begins_with("wall_"):
			# Where a partition runs into this wall, the piece with the stub toward it.
			var toward: Vector2i = DIRV[slot.trim_prefix("wall_")]
			if inner.has(c + toward) and not inner_open.has(c + toward):
				var joined := KitMap.resolve(kit_id, "join_" + slot.trim_prefix("wall_"), want_h)
				if not joined.is_empty():
					piece = joined
		if piece.is_empty():
			piece = KitMap.resolve(kit_id, "cross", want_h)
		var front := slot in FRONT
		if open.has(c):
			world.gameplay[c] = {"walkable": true, "blocks_los": false, "cover": 0, "b": id, "door": true}
			if open[c] == c:
				var door := KitMap.resolve(kit_id, "door_" + slot.trim_prefix("wall_"), want_h)
				if not door.is_empty() and _door_span(open, c) == 2:
					_overlay(world, c, z0 + pitch, str(door["tile"]), _opts(id, "door", pitch - fl, bool(door["flip"]), front, 0))
		else:
			world.gameplay[c] = {"walkable": false, "blocks_los": true, "cover": 2, "b": id}
			if not piece.is_empty():
				world.set_tile(c, z0 + pitch, str(piece["tile"]), _opts(id, slot, pitch - fl, bool(piece["flip"]), front, 0))
		# Upper storeys repeat the wall (no outer doors up there), with the join where a partition meets it.
		var plain := KitMap.resolve(kit_id, slot, want_h)
		if plain.is_empty():
			plain = piece
		for s in range(1, storeys):
			piece = plain
			if slot.begins_with("wall_"):
				var to_room: Vector2i = c + (DIRV[slot.trim_prefix("wall_")] as Vector2i)
				if (inner_by[s]["inner"] as Dictionary).has(to_room) and not (inner_by[s]["open"] as Dictionary).has(to_room):
					var upper_join := KitMap.resolve(kit_id, "join_" + slot.trim_prefix("wall_"), want_h)
					if not upper_join.is_empty():
						piece = upper_join
			if not piece.is_empty():
				_overlay(world, c, z0 + (s + 1) * pitch, str(piece["tile"]), _opts(id, "upper", pitch - fl, bool(piece["flip"]), front, s))
	# The floor of every upper storey: walkable (add_levels), open over the stairs that reach it.
	for s in range(1, storeys):
		var hole: Dictionary = holes.get(s, {})
		for c: Vector2i in floor_cells:
			if floor_tile != "" and not hole.has(c):
				_overlay(world, c, zf + s * pitch, floor_tile, {"b": id, "part": "deck", "lv": s})
	if bool(b.get("roof", true)):
		var top := zf + storeys * pitch
		# A pitched roof sits on the room itself: each piece's core covers its cell and
		# its overhang reaches out over the wall. A flat roof is a slab over room and walls.
		var pitched := str(b.get("roof_style", "flat")) == "pitched"
		var region: Dictionary = floor_cells
		for c: Vector2i in (floor_cells.keys() if pitched else cells):
			var o := {"b": id, "part": "roof", "lv": storeys}
			var t := roof_tile
			if pitched:
				var rp := KitMap.resolve(kit_id, roof_slot(region, c), want_h)
				if not rp.is_empty():
					t = str(rp["tile"])
					o["rise"] = 0
					if bool(rp["flip"]):
						o["flip"] = true
			if t != "":
				_overlay(world, c, top, t, o)
	return cells


## Extra lift for stair pieces (art px): their run is drawn starting half a tile below the floor.
const STAIR_UP := 16.0


## Pitched roof piece for a cell of the roof's area, from which sides are open:
## none = the flat-topped block (a valley where only one diagonal is open),
## one = a slope falling that way, two neighbours = a hip, two opposite = a
## ridge (a wing one cell wide), three = a ridge end, four = the pyramid.
## The pieces are flat on top with the slope at the open edge, so they join
## into one roof line: block, slope, hip and valley all meet at the same height.
static func roof_slot(region: Dictionary, cell: Vector2i) -> String:
	var open_sides: Array[String] = []
	for dn in KitMap.DIRS:
		if not region.has(cell + (DIRV[dn] as Vector2i)):
			open_sides.append(dn)
	match open_sides.size():
		0:
			var diag: Array[Vector2i] = []
			for dv: Vector2i in VALLEY_SLOT:
				if not region.has(cell + dv):
					diag.append(dv)
			return str(VALLEY_SLOT[diag[0]]) if diag.size() == 1 else "roof_block"
		1:
			return "slope_" + open_sides[0]
		2:
			var key := "_".join(open_sides)
			if HIP_SLOT.has(key):
				return str(HIP_SLOT[key])
			return "ridge_x" if key == "ne_sw" else "ridge_y"
		3:
			for dn in KitMap.DIRS:
				if not open_sides.has(dn):
					return "roof_end_" + dn
	return "roof_pyramid"


static func _has_arms(arms: Array, want: Array) -> bool:
	return arms.size() == 2 and arms.has(want[0]) and arms.has(want[1])


static func _door_span(open: Dictionary, anchor: Vector2i) -> int:
	var n := 0
	for c: Vector2i in open:
		if open[c] == anchor:
			n += 1
	return n


static func _opts(id: String, part: String, rise: int, flip: bool, front: bool, lv: int) -> Dictionary:
	var o := {"b": id, "part": part, "rise": rise}
	if flip:
		o["flip"] = true
	if front:
		o["front"] = true
	if lv > 0:
		o["lv"] = lv
	return o
