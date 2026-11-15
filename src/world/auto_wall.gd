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
##   building = {id, kit, height (1-3), z, cells [[x, y]..], storeys, roof, doors [[x, y]..]}

const NE := Vector2i(0, -1)
const SE := Vector2i(1, 0)
const SW := Vector2i(0, 1)
const NW := Vector2i(-1, 0)
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
	return str(b.get("id", "")) if bool(b.get("roof", false)) else ""


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
static func toggle_door(world: WorldMap, cell: Vector2i) -> Array[Vector2i]:
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
			if str(o.get("part", "")) == "floor":
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


## Rebuilds a building's floor, walls, doors, storeys and roof from its record.
static func rebuild(world: WorldMap, b: Dictionary) -> Array[Vector2i]:
	var cells := touched(b)
	clear(world, b, cells)
	var id := str(b["id"])
	var kit_id := str(b["kit"])
	var want_h := clampi(int(b.get("height", 1)), 1, 3)
	var z0 := int(b.get("z", 0))
	var floor_cells := cells_of(b)
	var ring_cells := ring(floor_cells)
	var floor_tile := str(KitMap.resolve(kit_id, "floor", want_h).get("tile", ""))
	var roof_tile := str(KitMap.resolve(kit_id, "roof", want_h).get("tile", floor_tile))
	# Doors: clicked cells widen to the two cells a door piece spans.
	var open := {}  # cell -> anchor cell of its door
	for d: Array in b.get("doors", []):
		var pair := door_cells(world, b, Vector2i(int(d[0]), int(d[1])))
		if ring_cells.has(pair[0]):
			for c: Vector2i in pair:
				open[c] = pair[0]
	for c: Vector2i in floor_cells:
		if floor_tile != "":
			world.set_tile(c, z0, floor_tile, {"b": id, "part": "floor"})
	var storeys := maxi(int(b.get("storeys", 1)), 1)
	# The pieces' own height decides the rise (a borrowed height may differ from the one asked for).
	var rise := int(KitMap.resolve(kit_id, "wall_se", want_h).get("height", want_h)) * LAYERS_PER_TILE
	for c: Vector2i in ring_cells:
		if not world.in_bounds(c):
			continue
		var slot: String = ring_cells[c]
		if world.stack_at(c).is_empty() and floor_tile != "":
			world.set_tile(c, z0, floor_tile)  # footing under the wall
		var piece := KitMap.resolve(kit_id, slot, want_h)
		if piece.is_empty():
			piece = KitMap.resolve(kit_id, "cross", want_h)
		var front := slot in FRONT
		if open.has(c):
			world.gameplay[c] = {"walkable": true, "blocks_los": false, "cover": 0, "b": id, "door": true}
			if open[c] == c:
				var door := KitMap.resolve(kit_id, "door_" + slot.trim_prefix("wall_"), want_h)
				if not door.is_empty() and _door_span(open, c) == 2:
					_overlay(world, c, z0 + rise, str(door["tile"]), _opts(id, "door", int(door["height"]), bool(door["flip"]), front))
		else:
			world.gameplay[c] = {"walkable": false, "blocks_los": true, "cover": 2, "b": id}
			if not piece.is_empty():
				world.set_tile(c, z0 + rise, str(piece["tile"]), _opts(id, slot, int(piece["height"]), bool(piece["flip"]), front))
		# Upper storeys repeat the wall (no doors up there).
		for s in range(1, storeys):
			if not piece.is_empty():
				_overlay(world, c, _base(z0, rise, s) + rise, str(piece["tile"]), _opts(id, "upper", int(piece["height"]), bool(piece["flip"]), false))
	# A slab over every storey: the next floor, or the roof on top.
	if bool(b.get("roof", true)) or storeys > 1:
		for s in storeys:
			var top := s == storeys - 1
			if top and not bool(b.get("roof", true)):
				break
			var slab := roof_tile if top else floor_tile
			if slab == "":
				continue
			for c: Vector2i in cells:
				_overlay(world, c, _base(z0, rise, s) + rise + 1, slab, {"b": id, "part": "roof" if top else "upper"})
	return cells


## Layer a storey's walls stand on (each storey = its walls + a one-layer slab).
static func _base(z0: int, rise: int, storey: int) -> int:
	return z0 + storey * (rise + 1)


static func _door_span(open: Dictionary, anchor: Vector2i) -> int:
	var n := 0
	for c: Vector2i in open:
		if open[c] == anchor:
			n += 1
	return n


static func _opts(id: String, part: String, piece_h: int, flip: bool, front: bool) -> Dictionary:
	var o := {"b": id, "part": part, "rise": piece_h * LAYERS_PER_TILE}
	if flip:
		o["flip"] = true
	if front:
		o["front"] = true
	return o
