class_name IsometricGrid
extends RefCounted
## Logical battle grid: cells with height, terrain, cover and occupants, plus the
## 2:1 isometric projection, height-aware pathfinding, line of sight and cover.
##
## Pure data (no nodes) so the AI, tests and the map editor can use it headless.
## BattleMap renders it; CombatManager mutates it.

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const COVER_NONE := 0
const COVER_HALF := 1
const COVER_FULL := 2
const MAX_HEIGHT := 32
## Stack layers may go below world ground (pits, canals, basements).
const MIN_HEIGHT := -16
## Height (in levels) of a standing unit's eyes, used for line of sight.
const EYE_HEIGHT := 1.5

var width: int = 0
var depth: int = 0
var tile_width: float = 64.0
var tile_height: float = 32.0
## Screen pixels per height level.
var height_step: float = 16.0
var origin: Vector2 = Vector2.ZERO

var _cells: Dictionary = {}  # Vector2i -> Cell
## Lazy grids (huge explore maps): cells are built by `source` (Vector2i ->
## Cell) the first time something asks for them, instead of all up front.
var source: Callable
## Fallen units by cell — targets for revive / reanimate.
var _corpses: Dictionary = {}

## Stacked floors. A cell on storey L of a building has coords
## (x + L * LEVEL_STRIDE, y): the same grid, so every rule that works on
## neighbouring cells keeps working on a floor; `base()` gives where it is on
## the map and `level_of()` its storey. Storeys meet only through `links`
## (the top of a stair run <-> the floor it arrives on).
const LEVEL_STRIDE := 1024
## cell -> cells joined to it across storeys.
var links: Dictionary = {}
## Optional filter for pick_cell: return true to skip a cell (floors hidden by the see-inside fade).
var pick_skip: Callable


static func base(cell: Vector2i) -> Vector2i:
	return Vector2i(posmod(cell.x, LEVEL_STRIDE), cell.y) if cell.x >= LEVEL_STRIDE else cell


static func level_of(cell: Vector2i) -> int:
	return cell.x / LEVEL_STRIDE if cell.x >= LEVEL_STRIDE else 0


static func at_level(cell: Vector2i, level: int) -> Vector2i:
	var b := base(cell)
	return Vector2i(b.x + level * LEVEL_STRIDE, b.y)


## Adds a cell on an upper storey (see AutoWall.add_levels).
func add_level_cell(c: Cell) -> void:
	_cells[c.coords] = c


func add_link(a: Vector2i, b: Vector2i) -> void:
	for pair: Array in [[a, b], [b, a]]:
		var l: Array = links.get(pair[0], [])
		if not l.has(pair[1]):
			l.append(pair[1])
		links[pair[0]] = l


## Where a step from `cell` toward `dir` lands: across a link when a stair run
## ends there, else the next cell on the same storey.
func step_to(cell: Vector2i, dir: Vector2i) -> Vector2i:
	for l: Vector2i in links.get(cell, []):
		if base(l) - base(cell) == dir:
			return l
	return cell + dir


class Cell extends RefCounted:
	var coords: Vector2i
	var height: int = 0
	var terrain: String = "concrete"
	var tile_id: String = ""
	var walkable: bool = true
	var move_cost: int = 1
	var cover: int = COVER_NONE
	var blocks_los: bool = false
	var hazard: String = ""
	var hazard_turns: int = 0
	var prop_id: String = ""
	var occupant: Node = null
	## Slope / stairs: the grid direction it climbs toward (ZERO = flat), how
	## many layers it rises from its low edge to its high edge, and how far its
	## centre sits above `height` (fractions of a layer, drawing only).
	var slope: Vector2i = Vector2i.ZERO
	var slope_rise: int = 0
	var lift: float = 0.0
	## Extra draw order for whoever stands here (stairs art spans two cells).
	var draw_bias: int = 0
	## Building an upper-storey cell belongs to ("" on the ground).
	var building: String = ""

	func to_dict() -> Dictionary:
		var d := {"x": coords.x, "y": coords.y, "h": height, "t": terrain}
		if tile_id != "": d["tile"] = tile_id
		if not walkable: d["walkable"] = false
		if move_cost != 1: d["cost"] = move_cost
		if cover != COVER_NONE: d["cover"] = cover
		if blocks_los: d["blocks_los"] = true
		if hazard != "": d["hazard"] = hazard; d["hazard_turns"] = hazard_turns
		if prop_id != "": d["prop"] = prop_id
		return d


# --- Setup -----------------------------------------------------------------

func setup(p_width: int, p_depth: int, terrain: String = "concrete") -> void:
	width = p_width
	depth = p_depth
	_cells.clear()
	for x in width:
		for y in depth:
			var c := Cell.new()
			c.coords = Vector2i(x, y)
			c.terrain = terrain
			_cells[c.coords] = c


func in_bounds(cell: Vector2i) -> bool:
	if cell.x >= LEVEL_STRIDE:
		return _cells.has(cell)  # upper storeys only exist where a floor was built
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < depth


func get_cell(cell: Vector2i) -> Cell:
	var c: Cell = _cells.get(cell)
	if c == null and source.is_valid() and in_bounds(cell):
		c = source.call(cell)
		_cells[cell] = c
	return c


func setup_lazy(p_width: int, p_depth: int, p_source: Callable) -> void:
	width = p_width
	depth = p_depth
	_cells.clear()
	source = p_source


func all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if source.is_valid():
		for x in width:
			for y in depth:
				out.append(Vector2i(x, y))
		for c: Vector2i in _cells:
			if c.x >= LEVEL_STRIDE:
				out.append(c)
		return out
	out.assign(_cells.keys())
	return out


func get_height(cell: Vector2i) -> int:
	var c := get_cell(cell)
	return c.height if c else 0


## Height a unit is drawn at in the middle of a cell (slopes sit between layers).
func visual_height(cell: Vector2i) -> float:
	var c := get_cell(cell)
	return float(c.height) + c.lift if c else 0.0


## Height of the walking surface at a fractional grid position: flat cells are
## level, slopes and stairs rise across the cell toward their high edge.
func surface_height(p: Vector2, level: int = 0) -> float:
	var cell := Vector2i(roundi(p.x), roundi(p.y))
	var c := get_cell(at_level(cell, level))
	if c == null:
		return 0.0
	var h := float(c.height) + c.lift
	if c.slope != Vector2i.ZERO:
		h += float(c.slope_rise) * clampf((p - Vector2(cell)).dot(Vector2(c.slope)), -0.5, 0.5)
	return h


## Height of a cell's edge toward `dir` (a neighbour offset).
func edge_height(cell: Vector2i, dir: Vector2i) -> float:
	var c := get_cell(cell)
	if c == null:
		return 0.0
	return float(c.height) + c.lift + float(c.slope_rise) * 0.5 * signf(Vector2(dir).dot(Vector2(c.slope)))


## True when a slope or stairs joins two neighbouring cells: one of them climbs
## along the step and their shared edge is level, so no jump is needed.
func slope_link(a: Vector2i, b: Vector2i) -> bool:
	var ca := get_cell(a)
	var cb := get_cell(b)
	if ca == null or cb == null:
		return false
	var d := base(b) - base(a)
	if level_of(a) != level_of(b) and not (links.get(a, []) as Array).has(b):
		return false
	var along := (ca.slope != Vector2i.ZERO and (ca.slope == d or ca.slope == -d)) or (cb.slope != Vector2i.ZERO and (cb.slope == d or cb.slope == -d))
	return along and absf(edge_height(a, d) - edge_height(b, -d)) <= 0.6


## Can a unit with this jump stat step from a to b (neighbours)? Slopes and
## stairs connect their two heights without a jump check.
func can_climb(a: Vector2i, b: Vector2i, jump: int) -> bool:
	return absi(get_height(b) - get_height(a)) <= jump or slope_link(a, b)


## Draw order of whoever stands on a cell (see Cell.draw_bias).
func unit_z(cell: Vector2i) -> int:
	var c := get_cell(cell)
	return draw_order(cell) * 2 + 1 + (c.draw_bias if c else 0)


func set_height(cell: Vector2i, h: int) -> void:
	var c := get_cell(cell)
	if c:
		c.height = clampi(h, MIN_HEIGHT, MAX_HEIGHT)


func is_walkable(cell: Vector2i) -> bool:
	var c := get_cell(cell)
	return c != null and c.walkable


# --- Occupancy -------------------------------------------------------------

func get_occupant(cell: Vector2i) -> Node:
	var c := get_cell(cell)
	if c == null or c.occupant == null or not is_instance_valid(c.occupant):
		return null
	return c.occupant


func set_occupant(cell: Vector2i, unit: Node) -> void:
	var c := get_cell(cell)
	if c:
		c.occupant = unit


func clear_occupant(cell: Vector2i, unit: Node = null) -> void:
	var c := get_cell(cell)
	if c and (unit == null or c.occupant == unit):
		c.occupant = null


func move_occupant(from_cell: Vector2i, to_cell: Vector2i) -> void:
	var unit := get_occupant(from_cell)
	clear_occupant(from_cell)
	set_occupant(to_cell, unit)


func add_corpse(cell: Vector2i, unit: Node) -> void:
	_corpses[cell] = unit


func get_corpse(cell: Vector2i) -> Node:
	var u: Node = _corpses.get(cell)
	return u if u != null and is_instance_valid(u) else null


func remove_corpse(cell: Vector2i) -> void:
	_corpses.erase(cell)


func corpse_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_corpses.keys())
	return out


# --- Projection ------------------------------------------------------------

## World position of the centre of a cell's top face.
func grid_to_world(cell: Vector2i, include_height: bool = true) -> Vector2:
	var bc := base(cell)
	var x := (bc.x - bc.y) * tile_width * 0.5
	var y := (bc.x + bc.y) * tile_height * 0.5
	if include_height:
		y -= visual_height(cell) * height_step
	return origin + Vector2(x, y)


## Inverse projection ignoring height (ground plane).
func world_to_grid_flat(world_pos: Vector2) -> Vector2i:
	var p := world_pos - origin
	var gx := (p.x / (tile_width * 0.5) + p.y / (tile_height * 0.5)) * 0.5
	var gy := (p.y / (tile_height * 0.5) - p.x / (tile_width * 0.5)) * 0.5
	return Vector2i(roundi(gx), roundi(gy))


## Height-aware picking: returns the front-most cell whose top face contains
## `world_pos`, or Vector2i(-1, -1) if none.
func pick_cell(world_pos: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_order := -INF
	var hw := tile_width * 0.5
	var hh := tile_height * 0.5
	for cell: Vector2i in _cells:
		if cell.x >= LEVEL_STRIDE and pick_skip.is_valid() and pick_skip.call(cell):
			continue
		var center := grid_to_world(cell)
		var d := world_pos - center
		if absf(d.x) / hw + absf(d.y) / hh <= 1.0:
			var order := float(draw_order(cell)) + get_height(cell) * 0.01
			if order > best_order:
				best_order = order
				best = cell
	return best


## Draw-order key: larger = drawn later (in front).
static func draw_order(cell: Vector2i) -> int:
	var bc := base(cell)
	return bc.x + bc.y


# --- Distance & ranges -----------------------------------------------------

## Steps on the map between two cells; each storey apart counts as 2 more (no
## reaching through a floor).
static func distance(a: Vector2i, b: Vector2i) -> int:
	var ba := base(a)
	var bb := base(b)
	return absi(ba.x - bb.x) + absi(ba.y - bb.y) + 2 * absi(level_of(a) - level_of(b))


static func cardinal_direction(from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	var d := base(to_cell) - base(from_cell)
	if d == Vector2i.ZERO:
		return Vector2i(1, 0)
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))


func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in DIRECTIONS:
		var n := cell + dir
		if in_bounds(n):
			out.append(n)
	for l: Vector2i in links.get(cell, []):
		out.append(l)
	return out


## Cells with min_r <= manhattan distance <= max_r from center.
func cells_in_range(center: Vector2i, min_r: int, max_r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-max_r, max_r + 1):
		var rem := max_r - absi(dx)
		for dy in range(-rem, rem + 1):
			var c := center + Vector2i(dx, dy)
			var dist := absi(dx) + absi(dy)
			if dist >= min_r and in_bounds(c):
				out.append(c)
	return out


# --- Pathfinding -----------------------------------------------------------

## Dijkstra flood from `start`. Returns {cell: {"cost": int, "prev": Vector2i}}.
## - Height changes greater than `jump` are impassable.
## - Units of other teams block movement; allies can be passed through.
## - Hazard cells cost +2 so the AI (and path preview) prefers avoiding them.
func flood(start: Vector2i, move: int, jump: int, team: int, ignore_units: bool = false) -> Dictionary:
	var result := {start: {"cost": 0, "prev": start}}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		# Pop lowest-cost cell (grids are small; a linear scan is fine).
		var best_i := 0
		for i in range(1, frontier.size()):
			if result[frontier[i]]["cost"] < result[frontier[best_i]]["cost"]:
				best_i = i
		var current: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)
		var cur_cost: int = result[current]["cost"]
		for n in neighbors(current):
			var nc := get_cell(n)
			if nc == null or not nc.walkable:
				continue
			if not can_climb(current, n, jump):
				continue
			if not ignore_units:
				var occ := get_occupant(n)
				if occ != null and occ.get("team") != team:
					continue
			var step := nc.move_cost + (2 if nc.hazard != "" else 0)
			var new_cost := cur_cost + step
			if new_cost > move:
				continue
			if not result.has(n) or new_cost < result[n]["cost"]:
				result[n] = {"cost": new_cost, "prev": current}
				if not frontier.has(n):
					frontier.append(n)
	return result


## Cells a unit can end its move on (unoccupied, reachable).
func reachable_cells(start: Vector2i, move: int, jump: int, team: int, ignore_units: bool = false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var flooded := flood(start, move, jump, team, ignore_units)
	for cell: Vector2i in flooded:
		if cell == start or get_occupant(cell) == null:
			out.append(cell)
	return out


## Shortest walk from one cell to another for exploration (no units, no move
## budget): 4-way steps that `climb` allows, across storeys by the stair links.
## Returns the cells after `from` up to `to`, or [] if there is no way.
func walk(from: Vector2i, to: Vector2i, climb: int) -> Array[Vector2i]:
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty() and not prev.has(to):
		var c: Vector2i = queue.pop_front()
		for d in DIRECTIONS:
			var n := step_to(c, d)
			if not prev.has(n) and is_walkable(n) and can_climb(c, n, climb):
				prev[n] = c
				queue.append(n)
	var out: Array[Vector2i] = []
	if not prev.has(to):
		return out
	var cur := to
	while cur != from:
		out.push_front(cur)
		cur = prev[cur]
	return out


## Walking steps from every cell to the nearest of `sources` (units ignored):
## {cell: steps}. On maps with storeys the AI marches by this, so it heads for
## the stairs instead of standing under a target it can't reach.
func walk_distances(sources: Array[Vector2i], jump: int) -> Dictionary:
	var dist := {}
	var queue: Array[Vector2i] = []
	for s in sources:
		if not dist.has(s):
			dist[s] = 0
			queue.append(s)
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for n in neighbors(c):
			if not dist.has(n) and is_walkable(n) and can_climb(c, n, jump):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	return dist


## Path from start to goal (inclusive of both), or [] if unreachable within `move`.
func find_path(start: Vector2i, goal: Vector2i, move: int, jump: int, team: int, ignore_units: bool = false) -> Array[Vector2i]:
	var flooded := flood(start, move, jump, team, ignore_units)
	return path_from_flood(flooded, start, goal)


static func path_from_flood(flooded: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not flooded.has(goal):
		return path
	var cur := goal
	var guard := 0
	while cur != start and guard < 4096:
		path.push_front(cur)
		cur = flooded[cur]["prev"]
		guard += 1
	path.push_front(start)
	return path


# --- Line of sight & cover -------------------------------------------------

## Supercover line between cell centres, excluding the endpoints.
static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 2
	if n == 0:
		return out
	for i in range(1, n):
		var t := float(i) / n
		var c := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		if c != a and c != b and not out.has(c):
			out.append(c)
	return out


## True if nothing between a and b blocks sight. Blocking = a blocks_los cell or
## terrain rising above the sight line (eye height at both ends).
func has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	var ha := get_height(a) + EYE_HEIGHT
	var hb := get_height(b) + EYE_HEIGHT
	var la := level_of(a)
	var lb := level_of(b)
	var total := float(distance(base(a), base(b)))
	if total <= 1.0 and la == lb:
		return true
	# Across storeys the line runs over the map; a floor between the two heights blocks it.
	var cross := la != lb
	var from_c := base(a) if cross else a
	for c in line_cells(from_c, base(b) if cross else b):
		if cross:
			var lo := minf(ha, hb) - EYE_HEIGHT
			var hi := maxf(ha, hb) - EYE_HEIGHT
			for lv in range(1, maxi(la, lb) + 1):
				var deck := get_cell(at_level(c, lv))
				if deck != null and deck.slope == Vector2i.ZERO and float(deck.height) > lo and float(deck.height) <= hi:
					return false
		var cell := get_cell(c)
		if cell == null:
			continue
		if cell.blocks_los:
			return false
		var t := float(distance(from_c, c)) / maxf(total, 1.0)
		if float(cell.height) > lerpf(ha, hb, t):
			return false
	return true


## How much cover (0–1) the target has against this attacker. Each cover
## cell next to the target is judged by where the shot comes from:
##   full cover: head-on (attacker beyond the cover) 1.0 = no line of sight,
##               from a side angle FULL_FLANK (0.66)
##   half cover: head-on HALF_FRONT (0.5), side angle HALF_FLANK (0.25)
## Terrain rising 2+ levels counts as full cover, 1 level as half. Melee
## (adjacent) ignores cover; shooting from 3+ levels above halves it.
const FULL_FLANK := 0.66
const HALF_FRONT := 0.5
const HALF_FLANK := 0.25
const HEAD_ON := 0.92  # alignment (cos, ~22°) that counts as "straight across the cover"


func cover_fraction(target_cell: Vector2i, attacker_cell: Vector2i) -> float:
	if distance(target_cell, attacker_cell) <= 1:
		return 0.0
	var v := Vector2(base(attacker_cell) - base(target_cell)).normalized()
	var th := get_height(target_cell)
	var best := 0.0
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c := get_cell(target_cell + dir)
		if c == null:
			continue
		var level := c.cover
		var rise := c.height - th
		if rise >= 2:
			level = COVER_FULL
		elif rise == 1:
			level = maxi(level, COVER_HALF)
		if level == COVER_NONE:
			continue
		var align := v.dot(Vector2(dir))
		var f := 0.0
		if align >= HEAD_ON:
			f = 1.0 if level == COVER_FULL else HALF_FRONT
		elif align > 0.2:
			f = FULL_FLANK if level == COVER_FULL else HALF_FLANK
		best = maxf(best, f)
	if get_height(attacker_cell) - th >= 3:
		best *= 0.5
	return best


## Directional cover the target gets against the attacker (XCOM-style): the
## neighbouring cell on the attacker's side must hold cover or rise above the
## target. Returns COVER_NONE / COVER_HALF / COVER_FULL.
func cover_against(target_cell: Vector2i, attacker_cell: Vector2i) -> int:
	var f := cover_fraction(target_cell, attacker_cell)
	return COVER_FULL if f >= FULL_FLANK else (COVER_HALF if f > 0.0 else COVER_NONE)


# --- Hazards ---------------------------------------------------------------

func set_hazard(cell: Vector2i, hazard_type: String, turns: int) -> void:
	var c := get_cell(cell)
	if c:
		c.hazard = hazard_type
		c.hazard_turns = turns


func get_hazard(cell: Vector2i) -> String:
	var c := get_cell(cell)
	return c.hazard if c else ""


## Hazards count down in rounds, not seconds (the original used frame delta).
func tick_hazards() -> Array[Vector2i]:
	var cleared: Array[Vector2i] = []
	for cell: Vector2i in _cells:
		var c: Cell = _cells[cell]
		if c.hazard != "":
			c.hazard_turns -= 1
			if c.hazard_turns <= 0:
				c.hazard = ""
				cleared.append(cell)
	return cleared


## Swaps terrain data (not occupants) between two cells — Warp Coordinates.
func swap_cell_data(a: Vector2i, b: Vector2i) -> void:
	var ca := get_cell(a)
	var cb := get_cell(b)
	if ca == null or cb == null:
		return
	for prop in ["height", "terrain", "tile_id", "walkable", "move_cost", "cover", "blocks_los", "hazard", "hazard_turns", "prop_id"]:
		var tmp: Variant = ca.get(prop)
		ca.set(prop, cb.get(prop))
		cb.set(prop, tmp)


# --- Serialization (map files) --------------------------------------------

func to_dict() -> Dictionary:
	var cells := []
	for cell: Vector2i in _cells:
		cells.append(_cells[cell].to_dict())
	return {"width": width, "depth": depth, "tile_width": tile_width, "tile_height": tile_height, "height_step": height_step, "cells": cells}


## Becomes an exact copy of `other` (cells built eagerly, occupants not
## copied). Unlike to_dict() -> load_dict() it keeps painted overrides that
## happen to equal the code defaults (a walkable bridge over water).
func copy_from(other: IsometricGrid) -> void:
	setup(other.width, other.depth)
	tile_width = other.tile_width
	tile_height = other.tile_height
	height_step = other.height_step
	links = other.links.duplicate(true)
	for coords: Vector2i in other.all_cells():
		var src := other.get_cell(coords)
		if src != null and coords.x >= LEVEL_STRIDE and not _cells.has(coords):
			var nc := Cell.new()
			nc.coords = coords
			_cells[coords] = nc
		var c := get_cell(coords)
		if src == null or c == null:
			continue
		c.height = src.height
		c.terrain = src.terrain
		c.tile_id = src.tile_id
		c.walkable = src.walkable
		c.move_cost = src.move_cost
		c.cover = src.cover
		c.blocks_los = src.blocks_los
		c.hazard = src.hazard
		c.hazard_turns = src.hazard_turns
		c.prop_id = src.prop_id
		c.slope = src.slope
		c.slope_rise = src.slope_rise
		c.lift = src.lift
		c.draw_bias = src.draw_bias
		c.building = src.building


func load_dict(data: Dictionary, terrain_defs: Dictionary = {}) -> void:
	setup(int(data.get("width", 12)), int(data.get("depth", 12)), str(data.get("default_terrain", "concrete")))
	tile_width = float(data.get("tile_width", tile_width))
	tile_height = float(data.get("tile_height", tile_height))
	height_step = float(data.get("height_step", height_step))
	for entry: Dictionary in data.get("cells", []):
		var coords := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var c := get_cell(coords)
		if c == null:
			continue
		c.height = clampi(int(entry.get("h", 0)), MIN_HEIGHT, MAX_HEIGHT)
		c.terrain = str(entry.get("t", c.terrain))
		apply_terrain_defaults(c, terrain_defs)
		c.tile_id = str(entry.get("tile", ""))
		if entry.has("walkable"): c.walkable = bool(entry["walkable"])
		if entry.has("cost"): c.move_cost = int(entry["cost"])
		if entry.has("cover"): c.cover = int(entry["cover"])
		if entry.has("blocks_los"): c.blocks_los = bool(entry["blocks_los"])
		c.hazard = str(entry.get("hazard", ""))
		c.hazard_turns = int(entry.get("hazard_turns", 0))
		c.prop_id = str(entry.get("prop", ""))


## Applies a terrain definition's defaults (walkable, cost, cover) to a cell.
static func apply_terrain_defaults(c: Cell, terrain_defs: Dictionary) -> void:
	var def: Dictionary = terrain_defs.get(c.terrain, {})
	c.walkable = bool(def.get("walkable", true))
	c.move_cost = int(def.get("move_cost", 1))
	c.cover = int(def.get("cover", COVER_NONE))
	c.blocks_los = bool(def.get("blocks_los", false))
