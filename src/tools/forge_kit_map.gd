class_name ForgeKitMap
extends HSplitContainer
## Neon Forge ▸ KIT MAP: every building kit's cut pieces and the slot each one
## fills (floor, roof, the 4 edge walls, outer and inner corners, T-junctions,
## crossings, posts, doors, stairs, ramps, sloped roofs). Pick a kit, pick a
## slot, click the piece that belongs in it. A kit is one sheet at one wall
## height (the _hN in its file name); an empty slot borrows its mirror, then
## the nearest height in the kit's family, and the list says which.
## SAVE writes data/kits.json, which the World Painter's BUILD brush reads.
## New sheets: drop them in tools/handoff/kits and run tools/cut_kits.bat.

signal status(text: String, color: Color)

var kit_id := ""
var slot := "floor"

var _kits: ItemList
var _kit_ids: Array[String] = []
var _slots: ItemList
var _pieces: GridContainer
var _info: Label
var _flags: Label


func _ready() -> void:
	split_offset = 330
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	left.add_child(NeonTheme.label("KIT MAP", 22, NeonTheme.GREEN))
	_kits = ItemList.new()
	_kits.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_kits.item_selected.connect(func(i: int) -> void: select_kit(_kit_ids[i]))
	left.add_child(_kits)
	add_child(left)
	var right := HSplitContainer.new()
	right.split_offset = 330
	add_child(right)
	var mid := VBoxContainer.new()
	mid.custom_minimum_size.x = 300
	_info = NeonTheme.label("", 13, NeonTheme.CYAN)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(_info)
	_slots = ItemList.new()
	_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slots.item_selected.connect(func(i: int) -> void:
		slot = KitMap.SLOTS[i]
		_refresh_pieces())
	mid.add_child(_slots)
	var row := HBoxContainer.new()
	var clear := Button.new()
	clear.text = "CLEAR SLOT"
	clear.pressed.connect(func() -> void: assign(""))
	row.add_child(clear)
	var save := Button.new()
	save.text = "SAVE KIT MAP"
	save.pressed.connect(func() -> void:
		var ok := KitMap.save()
		status.emit("kits.json saved" if ok else "Could not write data/kits.json", NeonTheme.GREEN if ok else NeonTheme.MAGENTA))
	row.add_child(save)
	mid.add_child(row)
	_flags = NeonTheme.label("", 12, NeonTheme.MAGENTA)
	_flags.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(_flags)
	right.add_child(mid)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pieces = GridContainer.new()
	_pieces.columns = 6
	scroll.add_child(_pieces)
	right.add_child(scroll)
	_kit_ids.assign(ContentDB.kits.keys())
	_kit_ids.sort()
	for id in _kit_ids:
		var miss := KitMap.missing(id).size()
		_kits.add_item("h%d  %s%s" % [int(KitMap.kit(id).get("height", 0)), str(KitMap.kit(id).get("name", id)), "  (%d empty)" % miss if miss > 0 else ""])
	if not _kit_ids.is_empty():
		_kits.select(0)
		select_kit(_kit_ids[0])


func select_kit(id: String) -> void:
	kit_id = id
	var k := KitMap.kit(id)
	var heights: Array = []
	for other in KitMap.family(id, 1):
		heights.append("h%d" % int(KitMap.kit(other).get("height", 0)))
	_info.text = "%s\nWall height %d (from the file name) · family has %s · other heights borrow the nearest.\nSheet: %s" % [id, int(k.get("height", 0)), ", ".join(heights), str(k.get("sheet", ""))]
	_flags.text = "Unsure:\n· " + "\n· ".join(PackedStringArray(k.get("flags", []))) if not (k.get("flags", []) as Array).is_empty() else ""
	_refresh_slots()
	_refresh_pieces()


## What a slot shows in the list: its piece, or where it borrows from.
func slot_text(s: String) -> String:
	var own := str(KitMap.kit(kit_id).get("slots", {}).get(s, ""))
	if own != "":
		return "%s  =  %s" % [s, own]
	var r := KitMap.resolve(kit_id, s)
	if r.is_empty():
		return "%s  =  EMPTY" % s
	if str(r["borrowed"]) == "mirror":
		return "%s  <-  mirror of %s" % [s, str(KitMap.MIRROR.get(s, ""))]
	return "%s  <-  h%d (%s)" % [s, int(r["height"]), str(r["kit"])]


func _refresh_slots() -> void:
	_slots.clear()
	for s in KitMap.SLOTS:
		_slots.add_item(slot_text(s))
	_slots.select(maxi(KitMap.SLOTS.find(slot), 0))


func _refresh_pieces() -> void:
	for c in _pieces.get_children():
		c.queue_free()
	var dir := "res://assets/tiles/kits/" + kit_id
	var files: Array = Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.ends_with(".png"))
	files.sort()
	var current := str(KitMap.kit(kit_id).get("slots", {}).get(slot, ""))
	for f: String in files:
		var b := Button.new()
		b.icon = ForgeStore.load_texture(dir.path_join(f))
		b.expand_icon = true
		b.custom_minimum_size = Vector2(150, 170)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.text = f.get_basename().left(2)
		b.tooltip_text = f.get_basename()
		var piece := f.get_basename()
		if piece == current:
			b.add_theme_stylebox_override("normal", NeonTheme.panel_box(NeonTheme.GREEN))
		b.pressed.connect(func() -> void: assign(piece))
		_pieces.add_child(b)


## Puts a piece (file name without extension, "" = none) in the picked slot.
func assign(piece: String) -> void:
	var k := KitMap.kit(kit_id)
	if k.is_empty():
		return
	var slots: Dictionary = k.get("slots", {})
	if piece == "":
		slots.erase(slot)
	else:
		slots[slot] = piece
	k["slots"] = slots
	KitMap.clear_cache()
	_refresh_slots()
	_refresh_pieces()
	status.emit("%s = %s (not saved yet)" % [slot, piece if piece != "" else "empty"], NeonTheme.CYAN)
