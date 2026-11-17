class_name AutoTile
extends RefCounted
## Auto-tile brush: paints one material into another and picks the edge and
## corner pieces from the neighbours (sets in data/autotiles.json, cut from the
## 4 x 4 transition sheets by tools/cut_kits.bat).
##
## A set has 16 pieces, one per combination of the diamond's four corners
## carrying the raised ("high") material: piece = S + 2*W + 4*E + 8*N.
## A painted cell is all high; a corner is high when any of the four cells
## that share it is painted, so the cells around a painted area turn into
## edges and corners on their own. Painted cells live in WorldMap.autotile.

const S := 1
const W := 2
const E := 4
const N := 8
## The four cells sharing each corner, as offsets from the cell (bit -> offsets).
const CORNER_CELLS := {
	N: [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)],
	E: [Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 0), Vector2i(1, 0)],
	S: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	W: [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(-1, 1), Vector2i(0, 1)],
}


static func sets() -> Dictionary:
	return ContentDB.autotiles


## Which corners of `cell` carry the set's high material (0-15).
static func mask(world: WorldMap, cell: Vector2i, set_id: String) -> int:
	var m := 0
	for bit: int in CORNER_CELLS:
		for off: Vector2i in CORNER_CELLS[bit]:
			if str(world.autotile.get(cell + off, "")) == set_id:
				m |= bit
				break
	return m


static func tile(set_id: String, m: int) -> String:
	var file := str(ContentDB.autotiles.get(set_id, {}).get("pieces", {}).get(str(m), ""))
	return "autotiles/%s/%s" % [set_id, file] if file != "" else ""


## Paints (or with erase, unpaints) a cell on layer z and re-picks the pieces
## of the 3 x 3 cells around it. Returns the cells whose tiles changed.
static func paint(world: WorldMap, cell: Vector2i, set_id: String, z: int, erase: bool = false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not world.in_bounds(cell) or not ContentDB.autotiles.has(set_id):
		return out
	if erase:
		if str(world.autotile.get(cell, "")) != set_id:
			return out
		world.autotile.erase(cell)
	else:
		world.autotile[cell] = set_id
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var c := cell + Vector2i(dx, dy)
			if world.in_bounds(c) and refresh(world, c, set_id, z):
				out.append(c)
	return out


## Re-picks one cell's piece. Cells that carry none of the high material keep
## their own tile, unless they held one of this set's pieces (then the plain low one).
static func refresh(world: WorldMap, cell: Vector2i, set_id: String, z: int) -> bool:
	var m := mask(world, cell, set_id)
	var at_z := world.top_z(cell, z)
	var old := world.tile_at(cell, at_z)
	var ours := str(world.tile_opts(cell, at_z).get("at", "")) == set_id
	if m == 0 and not ours:
		return false
	var t := tile(set_id, m)
	if t == "" or (t == old and ours):
		return false
	world.set_tile(cell, at_z, t, {"rise": 0, "at": set_id})
	return true
