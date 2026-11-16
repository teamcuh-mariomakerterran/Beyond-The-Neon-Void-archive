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
	# A three-storey tower: stairs from the ground and from the second floor; pitched roof.
	for x in range(2, 8):
		for y in range(1, 5):
			AutoWall.paint(w, Vector2i(x, y), KIT_A, 3, 0)
	var a: Dictionary = AutoWall.building_at(w, Vector2i(2, 1))
	a["roof_style"] = "pitched"
	AutoWall.toggle_door(w, Vector2i(3, 5))
	AutoWall.toggle_stairs(w, Vector2i(5, 3), "ne")
	AutoWall.toggle_stairs(w, Vector2i(7, 3), "ne", 1)
	# An L-shaped block with a pitched roof (valley, ridges, ends), a partition and a door in it.
	for x in range(13, 19):
		for y in range(2, 5):
			AutoWall.paint(w, Vector2i(x, y), KIT_B, 2, 0)
	for y in range(-1, 2):
		for x in range(16, 19):
			if y >= 0:
				AutoWall.paint(w, Vector2i(x, y), KIT_B, 2, 0)
	AutoWall.building_at(w, Vector2i(13, 2))["roof_style"] = "pitched"
	AutoWall.toggle_door(w, Vector2i(14, 5))
	for y in range(2, 5):
		AutoWall.paint_inner(w, Vector2i(16, y))
	AutoWall.toggle_door(w, Vector2i(16, 3))
	for x in range(3, 7):
		for y in range(14, 16):
			AutoWall.paint(w, Vector2i(x, y), KIT_YARD, 1, 0, false)
	AutoWall.toggle_door(w, Vector2i(4, 13))
	# A narrow shed: its roof is a ridge between two ends.
	for x in range(9, 12):
		AutoWall.paint(w, Vector2i(x, 2), KIT_B, 2, 0)
	AutoWall.building_at(w, Vector2i(9, 2))["roof_style"] = "pitched"
	AutoWall.rebuild(w, AutoWall.building_at(w, Vector2i(9, 2)))
	AutoWall.rebuild(w, AutoWall.building_at(w, Vector2i(13, 2)))
	# A raised walkway on the near side, reached by ground slopes from the kit's roof pieces.
	for x in range(13, 18):
		for y in range(13, 16):
			for z in [1, 2]:
				w.set_tile(Vector2i(x, y), z, AutoTile.tile(GROUND, 15))
	for y in range(13, 16):
		AutoWall.place_slope(w, Vector2i(12, y), KIT_B, "se", 0)
	AutoWall.place_slope(w, Vector2i(18, 13), KIT_B, "nw", 2, "ramp")  # the kit's two-cell ramp, on the walkway
	# Props from the new set.
	var props := [
		["street_cover/cyberpunk_slums_alleyway_1_jury_rigged_barricades_02.png", 8, 9],
		["street_cover/cyberpunk_slums_alleyway_1_jury_rigged_barricades_05.png", 12, 10],
		["street_cover/cyberpunk_slums_1_concrete_wall_2_concrete_wall_03.png", 15, 8],
		["junk/cyberpunk_junkpile_props_2_1_03.png", 9, 5],
		["junk/cyberpunk_junkpile_props_2_1_06.png", 19, 13],
		["plants/cyberpunk_outdoor_bushes_just_05.png", 4, 14],
		["plants/cyberpunk_outdoor_bushes_just_08.png", 6, 15],
		["plants/cyberpunk_plants_2_1_isometri_02.png", 11, 7],
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
	w.spawns = {"player": [[9, 9], [10, 9], [9, 10], [10, 10]], "enemy": [[15, 3], [14, 2], [4, 2], [18, 9]]}
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
	if not args.has("battle"):
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
		for shot: Array in [["street", Vector2i(9, 9), 0], ["inside", Vector2i(4, 4), 0], ["floor2", Vector2i(3, 2), 1], ["floor3", Vector2i(3, 2), 2], ["roofs", Vector2i(13, 8), 0], ["inside2", Vector2i(14, 3), 0], ["slope", Vector2i(12, 14), 0]]:
			ex.set("level", shot[2])
			ex.set("cell", shot[1])
			ex.call("_place_avatar")
			await _wait(tree, 70)
			tree.root.get_texture().get_image().save_png(S % [out, shot[0]])
		# Clip: from the street, in the door, up two stair runs to the 3rd floor.
		var N := Vector2i(0, -1)
		var E := Vector2i(1, 0)
		var W := Vector2i(-1, 0)
		var Sd := Vector2i(0, 1)
		for clip: Array in [["floors", Vector2i(4, 7), [N, N, N, E, N, N, N, E, Sd, Sd, Sd, E, N, N, N, W, W, W, Sd]],
				["slope", Vector2i(9, 14), [E, E, E, E, E, E]]]:
			ex.set("level", 0)
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
			print(clip[0], " ends at ", ex.get("cell"), " storey ", ex.get("level"))
	# Battle clip: the demo mission, AI on both sides, enemies on the floors above.
	CombatManager.autobattle = true
	CampaignManager.start_mission("demo_kit_street")
	await _wait(tree, 60)
	for i in 900:
		CombatManager.autobattle = true
		await _wait(tree, 1)
		if i % 2 == 0:
			tree.root.get_texture().get_image().save_png("%s_clip_battle_%03d.png" % [out, i / 2])
	print("saved ", out)
