extends SceneTree
## Converts a PixelLab "spritesheet" export (one PNG + its JSON: a rotations row
## and one row per animation facing) into the folder layout PixelLab (src/vfx/
## pixel_lab.gd) reads, so the unit loads in battles and the unit gallery:
##
##   <out>/<state>/rotations/<direction>.png
##   <out>/<state>/animations/<Anim>/<direction>/frame_000.png ...
##
##   godot --headless -s tools/art/pixellab_sheet.gd -- <sheet.json> <out dir> <state> [names.json]
##
## names.json maps an animation_group_id to a short animation name
## ({"016f9d8d-...": "Hover_Flinch"}); names decide the game action (see
## PixelLab.KEYWORDS), so pick words like idle / walk / attack / hit / death /
## cast / jump. Without a name the animation text's first words are used.
## A second row for the same facing becomes "<direction>-take2". Only reads
## the sheet; nothing is written outside <out>.


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		print("usage: godot --headless -s tools/art/pixellab_sheet.gd -- <sheet.json> <out dir> <state> [names.json]")
		quit(1)
		return
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var names: Dictionary = {}
	if a.size() > 3:
		names = JSON.parse_string(FileAccess.get_file_as_string(a[3]))
	var sheet_info: Dictionary = meta["spritesheet"]
	var img := Image.load_from_file(a[0].get_base_dir().path_join(str(sheet_info["path"])))
	img.convert(Image.FORMAT_RGBA8)
	var cw := int(sheet_info["cell_size"]["width"])
	var ch := int(sheet_info["cell_size"]["height"])
	var state_dir: String = a[1].path_join(a[2])
	var frames_written := 0
	for row: Dictionary in sheet_info["rows"]:
		var r := int(row["row"])
		var n := int(row["frame_count"])
		if str(row["type"]) == "rotations":
			var dirs: Array = row["directions"]
			DirAccess.make_dir_recursive_absolute(state_dir.path_join("rotations"))
			for k in n:
				img.get_region(Rect2i(k * cw, r * ch, cw, ch)).save_png(state_dir.path_join("rotations").path_join(str(dirs[k]) + ".png"))
				frames_written += 1
			continue
		var gid := str(row.get("animation_group_id", ""))
		var anim: String = names.get(gid, _slug(str(row.get("animation", "anim"))))
		var facing := str(row["direction"])
		var fdir := state_dir.path_join("animations").path_join(anim).path_join(facing)
		var take := 2
		while DirAccess.dir_exists_absolute(fdir):
			fdir = state_dir.path_join("animations").path_join(anim).path_join("%s-take%d" % [facing, take])
			take += 1
		DirAccess.make_dir_recursive_absolute(fdir)
		for k in n:
			img.get_region(Rect2i(k * cw, r * ch, cw, ch)).save_png(fdir.path_join("frame_%03d.png" % k))
			frames_written += 1
		print("%s %s: %d frames" % [anim, fdir.get_file(), n])
	print("wrote %d images under %s" % [frames_written, state_dir])
	quit(0)


func _slug(text: String) -> String:
	var words := text.to_lower().split(" ", false)
	var out := "_".join(words.slice(0, 3))
	var clean := ""
	for c in out:
		clean += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" else ""
	return clean.capitalize().replace(" ", "_")
