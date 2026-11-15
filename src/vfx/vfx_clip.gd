class_name VFXClip
extends VFXPart
## A Lattice clip (lattice.clip JSON + strip) played as one layer of a VFX
## effect: Lattice's spell, impact and summon animations inside the
## data-driven effects. Keys (plus the common VFXPart ones):
##   path    res:// path of the *_clip.json (required)
##   scale   size multiplier (1 = the clip's own pixels)
##   speed   playback rate (1 = as authored)
##   loop    keep looping for `life` (default: play once)
##   face    flip to face the target (default true for clips anchored "at")
##   glow    colour multiplier (above 1 blooms through the HDR glow)
##   clip    for a PixelLab VFX Creator export (path = its manifest.json):
##           "whole" (default), "behind", "front" or "part-<id>"
##   depth   "behind": drawn on the floor of the target cell, under the unit
##           standing there (the battle passes floor_z); default: over everything
## Blend defaults to "mix" (Lattice FX are authored for normal blending).
## The impact moment is the clip's first hits[] frame, else frame 0
## (Lattice's rule), so damage numbers land with the animation.

var _clip: Dictionary = {}
var _spr: Sprite2D


func default_blend() -> String:
	return "mix"


## The clip a part names: a Lattice clip, or one clip of a PixelLab VFX pack.
static func load_for(p: Dictionary) -> Dictionary:
	var path := str(p.get("path", ""))
	if LatticeClip.is_pack(path):
		return LatticeClip.load_pack(path, str(p.get("clip", "whole")))
	return LatticeClip.load_clip(path)


func _setup() -> void:
	_clip = load_for(d)
	if not _clip.get("ok", false):
		push_warning("VFX clip: can't load " + str(d.get("path", "")))
		life = 0.01
		return
	if d.has("loop"):
		_clip = _clip.merged({"loop": bool(d["loop"])}, true)  # a copy: the cache stays as authored
	var speed := maxf(num("speed", 1.0), 0.05)
	if not d.has("life"):
		life = float(_clip.get("start", 0.0)) / speed + float(_clip["total"]) / 1000.0 / speed
	if str(d.get("depth", "")) == "behind":
		z_as_relative = false
		z_index = int(fx.params.get("floor_z", 0))
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sc := num("scale", 1.0)
	_spr.scale = Vector2(sc, sc)
	var anchor: Vector2 = _clip["anchor"]
	_spr.offset = -anchor
	var face: bool = d.get("face", str(d.get("anchor", "at")) == "at")
	if face and fx.has_target and fx.target_local.x < 0.0:
		_spr.flip_h = true
		_spr.offset.x = -(float(_clip["cell"].x) - anchor.x)
	_spr.modulate = Color(glow, glow, glow, 1.0)
	_spr.use_parent_material = true
	add_child(_spr)


func _update(lt: float, _dt: float) -> void:
	if _spr == null:
		return
	var tt := lt * maxf(num("speed", 1.0), 0.05) - float(_clip.get("start", 0.0))
	_spr.visible = tt >= 0.0
	if tt < 0.0:
		return
	_spr.texture = LatticeClip.frame_texture(_clip, LatticeClip.frame_at(_clip, tt))


## Seconds into this part when it hits (first hits[] frame, else frame 0).
static func hit_time(p: Dictionary) -> float:
	var clip := load_for(p)
	if not clip.get("ok", false):
		return 0.0
	if clip.has("start") and not p.has("hit_frame"):
		return float(clip["start"])  # VFX packs: the blast lands as it starts
	var frame := 0
	var hits: Array = clip.get("hits", [])
	if not hits.is_empty() and hits[0] is Dictionary:
		frame = int(hits[0].get("frame", 0))
	var seq: Array = clip["seq"]
	var ms: Array = clip["ms"]
	var at := 0.0
	for k in seq.size():
		if int(seq[k]) == frame:
			break
		at += float(ms[k])
	return at / 1000.0 / maxf(float(p.get("speed", 1.0)), 0.05)
