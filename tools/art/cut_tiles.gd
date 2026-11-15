extends SceneTree
## cut_tiles.gd -- <tiles.tsv> <out root>
## Each tsv line: <sheet path>\t<set name>. Cuts a PixelLab tile sheet (columns of
## 128 px cells, 1 px transparent gutters) into one PNG per tile:
## <out root>/<set>/<set>_<a, b, ... z, aa ...>.png (letters, not numbers, so the
## tile scanner keeps them as variants, not animation frames). Each tile keeps
## its column's full 128 px width and the opaque rows of its own piece.

var CELL := 128


func _letters(i: int) -> String:
	var s := ""
	var n := i
	while true:
		s = char(97 + n % 26) + s
		n = n / 26 - 1
		if n < 0:
			break
	return s


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var lines := FileAccess.get_file_as_string(a[0]).strip_edges().split("\n")
	var out_root: String = a[1]
	var total := 0
	for line in lines:
		var parts := line.split("\t")
		var src := Image.load_from_file(parts[0])
		var set_name := parts[1].strip_edges()
		src.convert(Image.FORMAT_RGBA8)
		var w := src.get_width()
		CELL = 128 if (w + 1) % 129 == 0 else 64
		var cols := maxi(1, (w + 1) / (CELL + 1))
		var found: Array = ArtCutter.find_pieces(src, 1, 40)["pieces"]
		var dir := out_root.path_join(set_name)
		DirAccess.make_dir_recursive_absolute(dir)
		var k := 0
		var warn := ""
		for p: Dictionary in found:
			var r: Rect2i = p["rect"]
			var col := clampi(int(r.get_center().x) / (CELL + 1), 0, cols - 1)
			var x0 := col * (CELL + 1)
			if r.size.x > CELL + 2 or r.position.x < x0 - 1 or r.end.x > x0 + CELL + 1:
				warn += " wide@%s" % r
			var crop := Rect2i(x0, r.position.y, mini(CELL, w - x0), r.size.y)
			src.get_region(crop).save_png(dir.path_join("%s_%s.png" % [set_name, _letters(k)]))
			k += 1
		total += k
		print("%s\t%d tiles\t%dx%d%s" % [set_name, k, w, src.get_height(), warn])
	print("total ", total)
	quit(0)
