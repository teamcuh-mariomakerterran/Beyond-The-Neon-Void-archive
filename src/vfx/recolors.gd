class_name Recolors
extends RefCounted
## Colour variants of units, made in the game as they load instead of stored as
## image files (Brian, 2026-11-15). data/recolors.json lists each variant: the
## unit it comes from and its hue rules. A variant's folder path
## (res://assets/units/outfit_samurai_cyan) works anywhere a unit folder does:
## PixelLab.is_root / unit_set and GearAttach.load_rig resolve it to the source
## unit, and unit_set recolours every frame once (cached).
##
## The maths is tools/pixellab/recolor.py's, step for step (Python's colorsys
## and round-half-to-even), so a variant matches the baked PNGs pixel for pixel.

const PATH := "res://data/recolors.json"
const UNITS := "res://assets/units"
const MIN_SAT := 0.45

static var _data: Dictionary = {}
static var _loaded := false


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		if FileAccess.file_exists(PATH):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if d is Dictionary:
				for k: String in d:
					if not k.begins_with("_") and d[k] is Dictionary:
						_data[k] = d[k]
	return _data


static func reload() -> void:
	_loaded = false


## Saves `variants` ({id: {from, rules, ...}}) to data/recolors.json, keeping
## its note, and drops cached sets so the game sees the change. Returns the path.
static func save(variants: Dictionary) -> String:
	var out := {"_note": _note()}
	var keys := variants.keys()
	keys.sort()
	for k: String in keys:
		out[k] = variants[k]
	var path := ForgeStore.save_dict_file("recolors", out)
	_data = variants.duplicate(true)
	_loaded = true
	PixelLab.forget(UNITS)
	GearAttach.clear_cache()
	return path


static func _note() -> String:
	if FileAccess.file_exists(PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary and d.has("_note"):
			return str(d["_note"])
	return "Colour variants of units, recoloured in the game as they load (src/vfx/recolors.gd)."


## The most used saturated hue band [from, to] (degrees) in `imgs`, or [] (as recolor.py's accent()).
static func accent(imgs: Array) -> Array:
	var hist: Array[int] = []
	hist.resize(12)
	hist.fill(0)
	for img: Image in imgs:
		var im := img.duplicate() as Image
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGBA8)
		var b := im.get_data()
		for p in range(0, b.size(), 4):
			if b[p + 3] == 0:
				continue
			var hsv := rgb_to_hsv(b[p] / 255.0, b[p + 1] / 255.0, b[p + 2] / 255.0)
			if hsv[1] >= MIN_SAT and hsv[2] >= 0.3:
				hist[int(hsv[0] * 12) % 12] += 1
	var best := 0
	for i in 12:
		if hist[i] > hist[best]:
			best = i
	if hist[best] < 12:
		return []
	return [posmod(best * 30 - 20, 360), posmod(best * 30 + 50, 360)]


## Every variant id, sorted.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in data():
		out.append(k)
	out.sort()
	return out


## "res://assets/units/outfit_samurai" for a variant's folder path (or bare id), else "".
static func source(dir_or_id: String) -> String:
	var v: Variant = data().get(dir_or_id.trim_suffix("/").get_file())
	if not (v is Dictionary) or str(v.get("from", "")) == "":
		return ""
	return UNITS.path_join(str(v["from"]))


static func rules(dir_or_id: String) -> Array:
	var v: Variant = data().get(dir_or_id.trim_suffix("/").get_file())
	return (v.get("rules", []) as Array) if v is Dictionary else []


## A copy of a unit set (PixelLab.unit_set shape) with every frame recoloured.
## Frames shared between animations are recoloured once. `only`: just these
## animations (the Recolour Studio's quick preview); empty = all.
static func apply(base: Dictionary, rule_list: Array, only: Array = []) -> Dictionary:
	var out := base.duplicate()
	if not base.get("ok", false):
		return out
	var src: SpriteFrames = base["frames"]
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	var done := {}
	var colors := {}
	for an: StringName in src.get_animation_names():
		if not only.is_empty() and not only.has(str(an)):
			continue
		sf.add_animation(an)
		sf.set_animation_speed(an, src.get_animation_speed(an))
		sf.set_animation_loop(an, src.get_animation_loop(an))
		for i in src.get_frame_count(an):
			var t := src.get_frame_texture(an, i)
			if t == null:
				continue
			if not done.has(t):
				var img := t.get_image()
				if img == null:
					done[t] = t
				else:
					done[t] = ImageTexture.create_from_image(recolor_image(img, rule_list, colors))
			sf.add_frame(an, done[t], src.get_frame_duration(an, i))
	out["frames"] = sf
	return out


## Copy of `img` (RGBA) with the rules applied; alpha is kept. `cache` maps
## source colours to results and can be shared between images.
static func recolor_image(img: Image, rule_list: Array, cache: Dictionary = {}) -> Image:
	var out := img.duplicate() as Image
	if out.is_compressed():
		out.decompress()
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	var bytes := out.get_data()
	for p in range(0, bytes.size(), 4):
		if bytes[p + 3] == 0:
			continue
		var key := (bytes[p] << 16) | (bytes[p + 1] << 8) | bytes[p + 2]
		if not cache.has(key):
			cache[key] = recolor_rgb(bytes[p], bytes[p + 1], bytes[p + 2], rule_list)
		var c: int = cache[key]
		bytes[p] = (c >> 16) & 255
		bytes[p + 1] = (c >> 8) & 255
		bytes[p + 2] = c & 255
	out.set_data(out.get_width(), out.get_height(), false, Image.FORMAT_RGBA8, bytes)
	return out


## One colour (0-255 channels) through the rules, packed as 0xRRGGBB.
static func recolor_rgb(r8: int, g8: int, b8: int, rule_list: Array) -> int:
	var hsv := rgb_to_hsv(r8 / 255.0, g8 / 255.0, b8 / 255.0)
	var hd: float = hsv[0] * 360.0
	var s: float = hsv[1]
	var v: float = hsv[2]
	for rule: Dictionary in rule_list:
		var band: Array = rule.get("hue", [0, 0])
		if s >= float(rule.get("min_sat", MIN_SAT)) and in_band(hd, band):
			var a0 := fposmod(float(band[0]), 360.0)
			var b0 := fposmod(float(band[1]), 360.0)
			var mid := fposmod(a0 + fposmod(b0 - a0, 360.0) / 2.0, 360.0)
			hd = fposmod(hd + float(rule.get("to", 0)) - mid, 360.0)
			s = minf(1.0, s * float(rule.get("sat", 1.0)))
			v = minf(1.0, v * float(rule.get("val", 1.0)))
			var rgb := hsv_to_rgb(hd / 360.0, s, v)
			return (round_even(rgb[0] * 255.0) << 16) | (round_even(rgb[1] * 255.0) << 8) | round_even(rgb[2] * 255.0)
	return (r8 << 16) | (g8 << 8) | b8


static func in_band(h: float, band: Array) -> bool:
	var a := posmod(int(band[0]), 360)
	var b := posmod(int(band[1]), 360)
	return (h >= a and h <= b) if a <= b else (h >= a or h <= b)


## Python's round(): halves go to the even neighbour.
static func round_even(x: float) -> int:
	var f := floorf(x)
	var d := x - f
	if d > 0.5 or (d == 0.5 and int(f) % 2 == 1):
		return int(f) + 1
	return int(f)


## colorsys.rgb_to_hsv.
static func rgb_to_hsv(r: float, g: float, b: float) -> Array[float]:
	var maxc := maxf(r, maxf(g, b))
	var minc := minf(r, minf(g, b))
	if minc == maxc:
		return [0.0, 0.0, maxc]
	var rangec := maxc - minc
	var s := rangec / maxc
	var rc := (maxc - r) / rangec
	var gc := (maxc - g) / rangec
	var bc := (maxc - b) / rangec
	var h: float
	if r == maxc:
		h = bc - gc
	elif g == maxc:
		h = 2.0 + rc - bc
	else:
		h = 4.0 + gc - rc
	return [fposmod(h / 6.0, 1.0), s, maxc]


## colorsys.hsv_to_rgb.
static func hsv_to_rgb(h: float, s: float, v: float) -> Array[float]:
	if s == 0.0:
		return [v, v, v]
	var i := int(h * 6.0)
	var f := h * 6.0 - i
	var p := v * (1.0 - s)
	var q := v * (1.0 - s * f)
	var t := v * (1.0 - s * (1.0 - f))
	match i % 6:
		0: return [v, t, p]
		1: return [q, v, p]
		2: return [p, v, t]
		3: return [p, q, v]
		4: return [t, p, v]
	return [v, p, q]
