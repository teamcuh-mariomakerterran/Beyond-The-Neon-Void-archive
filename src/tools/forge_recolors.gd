class_name ForgeRecolors
extends HSplitContainer
## Neon Forge ▸ RECOLOUR STUDIO: new characters, NPCs and enemies from units
## already in the game, by moving their colours. Pick a base unit, add colour
## rules (which hues move, where they land, saturation and brightness), watch
## the four facings and any animation before / after, then SAVE: the variant
## goes into data/recolors.json (no image files) and works anywhere a unit
## folder does: res://assets/units/<variant id>. NEW CHARACTER / NEW NPC make
## an entry that uses it. Tags are free notes for now (e.g. "fire", "heavy
## armour", "elite"); nothing in the rules reads them yet.

signal status(text: String, color: Color)
## A bucket was edited (characters / npcs), so Neon Forge marks it dirty.
signal edited(bucket: String)

const ROOT := "res://assets/units"
const FACINGS := ["SE", "SW", "NE", "NW"]
const ZOOM := 3

## Every variant, as saved plus unsaved edits ({id: {from, rules, label, tags}}).
var variants: Dictionary = {}
## The variant being edited (its id) and the unit it comes from.
var current_id := ""
var base_dir := ""
var rules: Array = []

var _bases: Array[String] = []
var _base_list: ItemList
var _variant_list: ItemList
var _variant_ids: Array[String] = []
var _id_edit: LineEdit
var _label_edit: LineEdit
var _tags_edit: LineEdit
var _rules_box: VBoxContainer
var _before: Array[TextureRect] = []
var _after: Array[TextureRect] = []
var _anim_pick: OptionButton
var _anim_rect: TextureRect
var _anim_frames: Array[Texture2D] = []
var _anim_t := 0.0
var _anim_fps := 10.0
var _base_set: Dictionary = {}
var _dirty := false


func _ready() -> void:
	split_offset = 280
	variants = Recolors.data().duplicate(true)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	left.add_theme_constant_override("separation", 6)
	add_child(left)
	left.add_child(NeonTheme.label("RECOLOUR STUDIO", 22, NeonTheme.GREEN))
	var hint := NeonTheme.label("Pick a base unit, add colour rules, SAVE. Variants cost no image files.", 12, NeonTheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(hint)
	left.add_child(NeonTheme.label("BASE UNITS", 14, NeonTheme.CYAN))
	_base_list = ItemList.new()
	_base_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_base_list.item_selected.connect(func(i: int) -> void: open_base(_bases[i]))
	left.add_child(_base_list)
	left.add_child(NeonTheme.label("ITS VARIANTS", 14, NeonTheme.CYAN))
	_variant_list = ItemList.new()
	_variant_list.custom_minimum_size.y = 160
	_variant_list.item_selected.connect(func(i: int) -> void: open_variant(_variant_ids[i]))
	left.add_child(_variant_list)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	scroll.add_child(right)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	right.add_child(bar)
	for spec: Array in [["NEW VARIANT", new_variant], ["DUPLICATE", duplicate_variant], ["SAVE", save],
			["DELETE", delete_variant], ["NEW CHARACTER", func() -> void: make_entry("characters")],
			["NEW NPC", func() -> void: make_entry("npcs")]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		bar.add_child(b)
	var names := GridContainer.new()
	names.columns = 2
	right.add_child(names)
	_id_edit = _field(names, "ID", "outfit_samurai_jade")
	_label_edit = _field(names, "NAME", "Jade Samurai")
	_tags_edit = _field(names, "TAGS", "fire, heavy armour, elite")
	# Before / after, the four battle facings.
	var faces := GridContainer.new()
	faces.columns = 5
	right.add_child(faces)
	faces.add_child(NeonTheme.label("BEFORE", 14, NeonTheme.TEXT_DIM))
	for f: String in FACINGS:
		_before.append(_face(faces))
	faces.add_child(NeonTheme.label("AFTER", 14, NeonTheme.CYAN))
	for f: String in FACINGS:
		_after.append(_face(faces))
	var arow := HBoxContainer.new()
	right.add_child(arow)
	arow.add_child(NeonTheme.label("ANIMATION", 14, NeonTheme.TEXT_DIM))
	_anim_pick = OptionButton.new()
	_anim_pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_anim_pick.item_selected.connect(func(_i: int) -> void: _refresh_anim())
	arow.add_child(_anim_pick)
	_anim_rect = _face(arow)
	_anim_rect.custom_minimum_size = Vector2(96, 96) * ZOOM * 0.75
	# Rules.
	var rhead := HBoxContainer.new()
	right.add_child(rhead)
	rhead.add_child(NeonTheme.label("COLOUR RULES", 16, NeonTheme.GREEN))
	var add := Button.new()
	add.text = "+ RULE"
	add.pressed.connect(func() -> void: add_rule())
	rhead.add_child(add)
	var auto := Button.new()
	auto.text = "+ RULE FROM ACCENT"
	auto.tooltip_text = "Picks the base unit's strongest accent colour band."
	auto.pressed.connect(add_accent_rule)
	rhead.add_child(auto)
	_rules_box = VBoxContainer.new()
	_rules_box.add_theme_constant_override("separation", 6)
	right.add_child(_rules_box)
	_fill_bases()


func _field(grid: GridContainer, label: String, placeholder: String) -> LineEdit:
	grid.add_child(NeonTheme.label(label, 14, NeonTheme.TEXT_DIM))
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size.x = 320
	e.text_changed.connect(func(_t: String) -> void: _dirty = true)
	grid.add_child(e)
	return e


func _face(parent: Control) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(64, 64) * ZOOM * 0.6
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(t)
	return t


# --- lists ------------------------------------------------------------------------

## Every unit folder the game can load (variants included, so a variant can be a base).
static func base_units() -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(ROOT):
		var names := Array(DirAccess.get_directories_at(ROOT))
		names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
		for n: String in names:
			var d := ROOT.path_join(n)
			if PixelLab.is_root(d):
				out.append(d)
	return out


func _fill_bases() -> void:
	_bases = base_units()
	_base_list.clear()
	for d in _bases:
		var n := 0
		for v: String in variants:
			if str(variants[v].get("from", "")) == d.get_file():
				n += 1
		_base_list.add_item(d.get_file() + ("   (%d)" % n if n > 0 else ""))
	if base_dir == "" and not _bases.is_empty():
		# Start on the first unit that already has variants, showing its first one.
		var at := 0
		for i in _bases.size():
			if _base_list.get_item_text(i).ends_with(")"):
				at = i
				break
		_base_list.select(at)
		open_base(_bases[at])
		if not _variant_ids.is_empty():
			open_variant(_variant_ids[0])


func _fill_variants() -> void:
	_variant_list.clear()
	_variant_ids.clear()
	var keys := variants.keys()
	keys.sort()
	for v: String in keys:
		if str(variants[v].get("from", "")) == base_dir.get_file():
			_variant_ids.append(v)
			var lbl := str(variants[v].get("label", ""))
			_variant_list.add_item(v + ("  " + lbl if lbl != "" else ""))
			if v == current_id:
				_variant_list.select(_variant_list.item_count - 1)


# --- editing ------------------------------------------------------------------------

func open_base(dir: String) -> void:
	_commit()
	base_dir = dir
	_base_set = PixelLab.unit_set(dir)
	current_id = ""
	rules = []
	_id_edit.text = ""
	_label_edit.text = ""
	_tags_edit.text = ""
	_anim_pick.clear()
	var sf: SpriteFrames = _base_set.get("frames", SpriteFrames.new())
	var anims := Array(sf.get_animation_names()).map(func(a: StringName) -> String: return str(a))
	anims.sort()
	for a: String in anims:
		if a.ends_with("_SE") and not a.begins_with("idle_"):
			_anim_pick.add_item(a.trim_suffix("_SE"))
	for i in _anim_pick.item_count:
		if _anim_pick.get_item_text(i) == "walk":
			_anim_pick.select(i)
	_fill_variants()
	_rebuild_rules()
	refresh()


func open_variant(id: String) -> void:
	_commit()
	var v: Dictionary = variants.get(id, {})
	current_id = id
	rules = (v.get("rules", []) as Array).duplicate(true)
	_id_edit.text = id
	_label_edit.text = str(v.get("label", ""))
	_tags_edit.text = ", ".join(PackedStringArray(v.get("tags", [])))
	_fill_variants()
	_rebuild_rules()
	refresh()


func new_variant() -> void:
	if base_dir == "":
		return
	_commit()
	var id := unique_id(base_dir.get_file() + "_new")
	variants[id] = {"from": base_dir.get_file(), "rules": []}
	open_variant(id)
	add_accent_rule()
	_dirty = true
	status.emit("New variant %s: shape it, then SAVE." % id, NeonTheme.CYAN)


func duplicate_variant() -> void:
	if current_id == "":
		return
	_commit()
	var id := unique_id(current_id + "_copy")
	variants[id] = (variants[current_id] as Dictionary).duplicate(true)
	open_variant(id)
	_dirty = true


func delete_variant() -> void:
	if current_id == "":
		return
	variants.erase(current_id)
	status.emit("Removed %s (SAVE to write it)." % current_id, NeonTheme.MAGENTA)
	current_id = ""
	rules = []
	_dirty = true
	_fill_variants()
	_rebuild_rules()
	refresh()


func unique_id(base: String) -> String:
	var id := ForgeStore.slugify(base)
	var n := 2
	var try := id
	while variants.has(try) or DirAccess.dir_exists_absolute(ROOT.path_join(try)):
		try = "%s_%d" % [id, n]
		n += 1
	return try


## Writes the form back into `variants` (renaming if the id changed).
func _commit() -> void:
	if current_id == "" or not variants.has(current_id):
		return
	var v: Dictionary = variants[current_id]
	v["rules"] = rules.duplicate(true)
	if _label_edit.text.strip_edges() != "":
		v["label"] = _label_edit.text.strip_edges()
	else:
		v.erase("label")
	var tags: Array = []
	for t: String in _tags_edit.text.split(",", false):
		if t.strip_edges() != "":
			tags.append(t.strip_edges())
	if tags.is_empty():
		v.erase("tags")
	else:
		v["tags"] = tags
	var new_id := ForgeStore.slugify(_id_edit.text)
	if new_id != "" and new_id != current_id and not variants.has(new_id) and not DirAccess.dir_exists_absolute(ROOT.path_join(new_id)):
		variants.erase(current_id)
		variants[new_id] = v
		current_id = new_id


func save() -> void:
	_commit()
	var path := Recolors.save(variants)
	_dirty = false
	_fill_bases()
	_fill_variants()
	status.emit("Saved %d variants to %s" % [variants.size(), path] if path != "" else "Could not save recolors.json", NeonTheme.GREEN if path != "" else NeonTheme.MAGENTA)


## A character (or an NPC with its own character) that uses the current variant.
func make_entry(bucket: String) -> void:
	if current_id == "":
		status.emit("Pick or make a variant first.", NeonTheme.MAGENTA)
		return
	save()
	var art := ROOT.path_join(current_id)
	var nice := _label_edit.text.strip_edges() if _label_edit.text.strip_edges() != "" else current_id.capitalize()
	var ch := CharacterData.new()
	ch.id = ForgeStore.unique_id("characters", current_id)
	ch.display_name = nice
	ch.sprite_frames_path = art
	ForgeStore.put_entry("characters", ch)
	edited.emit("characters")
	if bucket == "npcs":
		var npc := NPCResource.new()
		npc.id = ForgeStore.unique_id("npcs", "npc_" + current_id)
		npc.display_name = nice
		npc.character_id = ch.id
		ForgeStore.put_entry("npcs", npc)
		edited.emit("npcs")
		status.emit("NPC %s made (character %s); Ctrl+S saves." % [npc.id, ch.id], NeonTheme.GREEN)
	else:
		status.emit("Character %s made; Ctrl+S saves." % ch.id, NeonTheme.GREEN)


# --- rules ----------------------------------------------------------------------------

func add_rule(rule: Dictionary = {}) -> void:
	rules.append(rule if not rule.is_empty() else {"hue": [160, 230], "to": 0})
	_dirty = true
	_rebuild_rules()
	refresh()


func add_accent_rule() -> void:
	var imgs: Array = []
	var sf: SpriteFrames = _base_set.get("frames", SpriteFrames.new())
	for f: String in FACINGS:
		if sf.has_animation("idle_" + f) and sf.get_frame_count("idle_" + f) > 0:
			imgs.append(sf.get_frame_texture("idle_" + f, 0).get_image())
	var band := Recolors.accent(imgs)
	if band.is_empty():
		status.emit("No strong accent colour on this unit: set the band by hand.", NeonTheme.AMBER)
		band = [160, 230]
	var mid := fposmod(band[0] + fposmod(band[1] - band[0], 360) / 2.0, 360.0)
	add_rule({"hue": band, "to": int(fposmod(mid + 180.0, 360.0))})


func _rebuild_rules() -> void:
	for c in _rules_box.get_children():
		c.queue_free()
	for i in rules.size():
		_rules_box.add_child(_rule_row(i))


func _rule_row(i: int) -> Control:
	var r: Dictionary = rules[i]
	var box := PanelContainer.new()
	var g := GridContainer.new()
	g.columns = 4
	box.add_child(g)
	var band: Array = r.get("hue", [0, 0])
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(48, 20)
	var from_sw := ColorRect.new()
	from_sw.custom_minimum_size = Vector2(48, 20)
	var paint := func() -> void:
		var b: Array = r.get("hue", [0, 0])
		var mid := fposmod(float(b[0]) + fposmod(float(b[1]) - float(b[0]), 360.0) / 2.0, 360.0)
		from_sw.color = Color.from_hsv(mid / 360.0, 0.9, 0.95)
		swatch.color = Color.from_hsv(float(r.get("to", 0)) / 360.0, clampf(0.9 * float(r.get("sat", 1.0)), 0, 1), clampf(0.95 * float(r.get("val", 1.0)), 0, 1))
	_slider(g, "HUE FROM", 0, 359, 1, float(band[0]), func(v: float) -> void:
		(r["hue"] as Array)[0] = int(v)
		paint.call())
	_slider(g, "HUE TO", 0, 359, 1, float(band[1]), func(v: float) -> void:
		(r["hue"] as Array)[1] = int(v)
		paint.call())
	_slider(g, "BECOMES", 0, 359, 1, float(r.get("to", 0)), func(v: float) -> void:
		r["to"] = int(v)
		paint.call())
	_slider(g, "MIN SATURATION", 0.0, 1.0, 0.01, float(r.get("min_sat", Recolors.MIN_SAT)), func(v: float) -> void:
		r["min_sat"] = v
		if is_equal_approx(v, Recolors.MIN_SAT):
			r.erase("min_sat"))
	_slider(g, "SATURATION ×", 0.0, 2.0, 0.05, float(r.get("sat", 1.0)), func(v: float) -> void:
		r["sat"] = v
		if is_equal_approx(v, 1.0):
			r.erase("sat")
		paint.call())
	_slider(g, "BRIGHTNESS ×", 0.0, 2.0, 0.05, float(r.get("val", 1.0)), func(v: float) -> void:
		r["val"] = v
		if is_equal_approx(v, 1.0):
			r.erase("val")
		paint.call())
	var sw := HBoxContainer.new()
	sw.add_child(from_sw)
	sw.add_child(NeonTheme.label(" → ", 14, NeonTheme.TEXT))
	sw.add_child(swatch)
	g.add_child(NeonTheme.label("RULE %d" % (i + 1), 14, NeonTheme.CYAN))
	g.add_child(sw)
	var del := Button.new()
	del.text = "REMOVE"
	del.pressed.connect(func() -> void:
		rules.remove_at(i)
		_dirty = true
		_rebuild_rules()
		refresh())
	g.add_child(del)
	paint.call()
	return box


func _slider(g: GridContainer, label: String, lo: float, hi: float, step: float, value: float, on: Callable) -> void:
	g.add_child(NeonTheme.label(label, 13, NeonTheme.TEXT_DIM))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size.x = 180
	var num := NeonTheme.label(str(value), 13, NeonTheme.TEXT)
	num.custom_minimum_size.x = 44
	s.value_changed.connect(func(v: float) -> void:
		on.call(v)
		num.text = str(snappedf(v, step))
		_dirty = true
		refresh())
	var row := HBoxContainer.new()
	row.add_child(s)
	row.add_child(num)
	g.add_child(row)


# --- preview ------------------------------------------------------------------------

## Redraws the before / after facings and the animation with the current rules.
func refresh() -> void:
	var sf: SpriteFrames = _base_set.get("frames", SpriteFrames.new())
	var cache := {}
	for k in FACINGS.size():
		var an: String = "idle_" + FACINGS[k]
		var tex: Texture2D = sf.get_frame_texture(an, 0) if sf.has_animation(an) and sf.get_frame_count(an) > 0 else null
		_before[k].texture = tex
		_after[k].texture = _recolor(tex, cache)
	_refresh_anim(cache)


func _refresh_anim(cache: Dictionary = {}) -> void:
	_anim_frames.clear()
	var sf: SpriteFrames = _base_set.get("frames", SpriteFrames.new())
	if _anim_pick.selected < 0:
		return
	var an := _anim_pick.get_item_text(_anim_pick.selected) + "_SE"
	if not sf.has_animation(an):
		return
	_anim_fps = sf.get_animation_speed(an)
	for i in sf.get_frame_count(an):
		_anim_frames.append(_recolor(sf.get_frame_texture(an, i), cache))


func _recolor(tex: Texture2D, cache: Dictionary) -> Texture2D:
	if tex == null or rules.is_empty():
		return tex
	var img := tex.get_image()
	return ImageTexture.create_from_image(Recolors.recolor_image(img, rules, cache)) if img else tex


func _process(delta: float) -> void:
	if _anim_frames.is_empty():
		return
	_anim_t += delta
	_anim_rect.texture = _anim_frames[int(_anim_t * _anim_fps) % _anim_frames.size()]
