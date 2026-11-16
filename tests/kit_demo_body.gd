extends RefCounted
## Body of kit_demo.gd (loaded at runtime so it may use autoloads / class names).

const MAP_ID := "kit_street_demo"
const GROUND := "cyberpunk_cement_sidewalk_to_asphalt_street"
const KIT_A := "cyberpunk_building_with_cement_sidewalk_h3"
const KIT_B := "cast_industrial_concrete_block_walls_showing_h2"
const KIT_YARD := "low_architectural_planter_box_retaining_wall_h1"
const P := "res://assets/props/"


static func build() -> WorldMap:
	var w := WorldMap.new()
	w.id = MAP_ID
	w.name = "Kit Street Demo"
	w.kind = "city"
	w.width = 22
	w.depth = 17
	w.ambient = "#7a72b8"
	w.post = "neon_noir"
	# Ground: asphalt everywhere, then the auto-tile brush lays the sidewalks.
	var asphalt := AutoTile.tile(GROUND, 0)
	for x in w.width:
		for y in w.depth:
			w.set_tile(Vector2i(x, y), 0, asphalt, {"rise": 0, "at": GROUND})
	for x in w.width:
		for y in w.depth:
			if y <= 6 or y >= 12 or (x >= 9 and x <= 10 and y >= 12):
				if not (x >= 9 and x <= 10):
					AutoTile.paint(w, Vector2i(x, y), GROUND, 0)
	# Two buildings on the far side of the street, a low planter yard on the near side.
	for x in range(2, 8):
		for y in range(1, 5):
			AutoWall.paint(w, Vector2i(x, y), KIT_A, 3, 0)
	var a: Dictionary = AutoWall.building_at(w, Vector2i(2, 1))
	a["roof_style"] = "pitched"
	AutoWall.toggle_door(w, Vector2i(3, 5))
	AutoWall.toggle_stairs(w, Vector2i(5, 3), "ne")  # up to the second floor
	for x in range(13, 19):
		for y in range(2, 5):
			AutoWall.paint(w, Vector2i(x, y), KIT_B, 2, 0)
	for x in range(16, 19):
		AutoWall.paint(w, Vector2i(x, 1), KIT_B, 2, 0)  # an L-shaped footprint: inner corner
	AutoWall.toggle_door(w, Vector2i(14, 5))
	for y in range(2, 5):
		AutoWall.paint_inner(w, Vector2i(16, y))
	AutoWall.paint_inner(w, Vector2i(16, 3), true)  # a gap to walk through
	for x in range(3, 7):
		for y in range(14, 16):
			AutoWall.paint(w, Vector2i(x, y), KIT_YARD, 1, 0, false)
	AutoWall.toggle_door(w, Vector2i(4, 13))
	# A raised walkway on the near side, reached by ground slopes from the kit's roof pieces.
	for x in range(13, 18):
		for y in range(13, 16):
			for z in [1, 2]:
				w.set_tile(Vector2i(x, y), z, AutoTile.tile(GROUND, 15))
	for y in range(13, 16):
		AutoWall.place_slope(w, Vector2i(12, y), KIT_B, "se", 0)
	# Props from the new set.
	var props := [
		["street_cover/cyberpunk_slums_alleyway_1_jury_rigged_barricades_02.png", 8, 9],
		["street_cover/cyberpunk_slums_alleyway_1_jury_rigged_barricades_05.png", 12, 10],
		["street_cover/cyberpunk_slums_1_concrete_wall_2_concrete_wall_03.png", 15, 8],
		["junk/cyberpunk_junkpile_props_2_1_03.png", 9, 5],
		["junk/cyberpunk_junkpile_props_2_1_06.png", 19, 13],
		["plants/cyberpunk_outdoor_bushes_just_05.png", 4, 14],
		["plants/cyberpunk_outdoor_bushes_just_08.png", 6, 15],
		["plants/cyberpunk_plants_2_1_isometri_02.png", 11, 6],
		["bar/cyberpunk_futuristic_bar_props_07.png", 2, 2],
		["bar/a_high_top_cyberpunk_rectangul_5.png", 2, 4],
		["server/cyberpunk_futuristic_server_ro_08.png", 14, 2],
		["server/cyberpunk_futuristic_server_ro_2_07.png", 17, 3],
		["industrial/cyberpunk_factory_assets_04.png", 20, 14],
	]
	for p: Array in props:
		var o := w.add_object(P + str(p[0]), Vector2i(int(p[1]), int(p[2])), 0, "prop")
		o["scale"] = WorldRenderer.default_scale(w, str(o["asset"]), "prop")
	for l: Array in [[1, 6, "#ff3fb4"], [8, 6, "#3ff6ff"], [12, 6, "#ffb347"], [20, 6, "#3ff6ff"], [4, 3, "#3ff6ff"], [15, 3, "#ff7a2f"], [10, 12, "#ff3fb4"]]:
		var lo := w.add_object("", Vector2i(int(l[0]), int(l[1])), 0, "prop")
		lo["light"] = {"color": l[2], "energy": 0.75, "radius": 2.6, "flicker": 0.06, "height": 2.0}
	for x in range(0, w.width, 2):
		for y in range(0, w.depth, 2):
			w.set_particle(Vector2i(x, y), 8, "neon_rain")
	for x in range(1, w.width, 4):
		w.set_particle(Vector2i(x, 9), 1, "ground_mist")
	w.spawns = {"player": [[9, 9], [10, 9], [9, 10], [10, 10]], "enemy": [[15, 3], [16, 2], [4, 2], [18, 9]]}
	return w


func _wait(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.process_frame


func run(tree: SceneTree) -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://kit_demo"
	if args.has("build"):
		var f := FileAccess.open("res://data/maps/%s.json" % MAP_ID, FileAccess.WRITE)
		if f == null or not f.store_string(JSON.stringify(build().to_dict(), "", true) + "\n"):
			push_error("can't write the demo map")
		f = null
		ContentDB.reload()
	var S := "%s_%s.png"
	# Editor: the BUILD brush in the World Painter, then the Kit map tab.
	tree.change_scene_to_file("res://scenes/editor/neon_forge.tscn")
	await _wait(tree, 10)
	tree.current_scene.call("show_section", "world")
	await _wait(tree, 5)
	var painter: ForgeWorldPainter = tree.current_scene.get("_world")
	painter.load_map(MAP_ID)
	painter.set_mode(ForgeWorldPainter.Mode.BUILD)
	await _wait(tree, 60)
	tree.root.get_texture().get_image().save_png(S % [out, "painter"])
	tree.current_scene.call("show_section", "kits")
	await _wait(tree, 30)
	tree.root.get_texture().get_image().save_png(S % [out, "kitmap"])
	var cm: Node = tree.root.get_node("CampaignManager")
	cm.set("current_explore", {"map_id": MAP_ID, "spawn": 0})
	tree.change_scene_to_file("res://scenes/world/explore.tscn")
	await _wait(tree, 30)
	var ex: Node = tree.current_scene
	for shot: Array in [["street", Vector2i(9, 9)], ["inside", Vector2i(4, 4)], ["stairs", Vector2i(5, 3)], ["upstairs", Vector2i(3, 2)], ["inside2", Vector2i(15, 3)], ["slope", Vector2i(12, 14)]]:
		ex.set("cell", shot[1])
		ex.call("_place_avatar")
		await _wait(tree, 70)
		tree.root.get_texture().get_image().save_png(S % [out, shot[0]])
	# Clips: in through the door, up the stairs to the second floor; then up a ground slope.
	for clip: Array in [["stairs", Vector2i(4, 8), [Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 0), Vector2i(0, 1)]],
			["slope", Vector2i(9, 14), [Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0)]]]:
		ex.set("cell", clip[1])
		ex.call("_place_avatar")
		await _wait(tree, 40)
		var n := 0
		for d: Vector2i in clip[2]:
			ex.call("_step", d)
			for i in 60:
				await _wait(tree, 1)
				tree.root.get_texture().get_image().save_png("%s_clip_%s_%03d.png" % [out, clip[0], n])
				n += 1
				if not bool(ex.get("_moving")):
					break
		print(clip[0], " ends at ", ex.get("cell"))
	print("saved ", out)
