"""Head modules: every character's head (hair, face, or a complete helmeted head)
is a removable module, and the head slot holds exactly one (Brian, 2026-11-14).

  head slot empty    -> headless body + the character's own head module
  helmet equipped    -> headless body + that helmeted-head module (own head off)

Never "helmet drawn over the full character". Free: reads the original
PixelLab exports (never modified) and writes beside them.

    python3 -I tools/gear/heads.py propose <variant> [F ...]     auto mask proposal (mask_auto_<F>.png)
    python3 -I tools/gear/heads.py edit <variant> <F> add|remove|resolve x,y [x,y ...]
    python3 -I tools/gear/heads.py undo|redo <variant> <F>
    python3 -I tools/gear/heads.py show <variant> <F> [x0,y0,x1,y1]   text map: H head, b body, ? uncertain
    python3 -I tools/gear/heads.py extract <variant> [F ...]     head_<F>.png, body_<F>.png, module.json
    python3 -I tools/gear/heads.py preview <base> <helmet|-> out.png   diagnostics A-E, all four facings
    python3 -I tools/gear/heads.py check                         every extracted variant: head + body == source,
                                                                 the files match the masks, open flags listed

Files (assets/gear/heads/<variant>/, all on the source's own canvas, untrimmed):
  mask_auto_<F>.png   proposal (255 = head module, 0 = not), never hand edited
  edits_<F>.json      {"ops": [...], "redo": [...]}: pixel add / remove / resolve, applied in order
  head_<F>.png        source pixels inside the final mask (colours and alpha exact)
  body_<F>.png        source pixels outside it; head + body == source, checked on every extract
  module.json         canvas, canvas_offset (source -> shared coords), anchor per facing,
                      registration check, open review flags
Masks can also be painted in any pixel editor: a mask_<F>.png beside them
(255 / 0) replaces the proposal + edits when present.

The proposal (review it; it is not the answer):
  1. Shared coords are the bald base's 60x60 standing canvas. Each export is
     placed by its canvas offset (PixelLab centres wider canvases), then
     checked against the base skeleton: the neck anchor and the head points
     (eyes, nose, ears) must land within 1 px or the facing is flagged.
  2. Inside the base's neck band the head/neck boundary is a seam: one row per
     column, moving at most a row per column, along the darkest pixels (the
     drawn chin line or helmet rim). Head is the seam and above. It follows
     the drawn shape; it is not a shared row.
  3. Pixels outside the bald base silhouette (hair, horns, crests, guards,
     wings, shoulder plates) are head only if they are nearer the head core
     than the body core, within REACH px of the bald head (or above its
     crown: crests, horns, spikes), and joined to the head through head
     pixels. Wings and shoulder plates reach farther and sit nearer the
     body. Near ties and the REACH edge are marked uncertain.
  Neck ownership (Brian, 2026-11-14): the neck belongs to the HEAD module, down
  to the collar line; the collar belongs to the body. (The proposal's seam
  still sits near the chin; reviewed edits carry the neck down.)
Flags: uncertain (ownership near a tie, or the seam where head and body
touch), missing (body pixels that only the old head covered: holes inside
the body after removal) and touchup (body pixels near the neck painted in the
head's own skin colours: PixelLab drew skin into the collar). Missing and
touchup are artwork to paint, never filled here: paint the fix on a copy of
body_<F>.png saved as body_touchup_<F>.png and composition uses it.
"""
import io
import json
import math
import os
import sys
import zipfile

SRC = os.path.join("assets", "units", "base_male_hi", "source")
OUT = os.path.join("assets", "gear", "heads")
SKEL = os.path.join("assets", "gear", "source", "helmets", "skeletons.json")
FD = {"SE": "south-east", "SW": "south-west", "NE": "north-east", "NW": "north-west"}
SHARED = 60
# variant -> (zip, state, helmeted?)
VARIANTS = {
	"base": ("outfit_states.zip", "light_bodysuit", False),
	"medic_buns": ("outfit_states.zip", "same_character_same_6", False),
	"longcoat": ("outfit_states.zip", "long_coat", False),
	"dragoon": ("outfit_states.zip", "jumpjet_dragoon", False),
	"undercut": ("outfit_states.zip", "same_character_same_2", False),
	"heavy40": ("outfit_states.zip", "same_character_same_3", False),
	"slicked20": ("outfit_states.zip", "same_character_same_4", False),
	"samurai": ("outfit_states_r2.zip", "street_samurai", True),
	"tinkerer": ("outfit_states_r2.zip", "scrap_tinkerer", True),
	"dragoon_helm": ("outfit_states_r2.zip", "jumpjet_dragoon_with_helmet", True),
	"neon_coat": ("outfit_states_r2.zip", "new_char_01", True),
	"dragoon_wings": ("outfit_states_r3.zip", "jumpjet_dragoon_full", True),
	"armor_6142": ("outfit_states_r3.zip", "6142", True),
	"hood_0101": ("outfit_states_r3.zip", "0101", True),
	"armor_009": ("outfit_states_r3.zip", "009", True),
}
# Left out of head swapping (Brian, 2026-11-14): too much of an edge case (wings, jaw guard, neck).
SKIP = {"dragoon_wings"}
HEAD_POINTS = ["LEFT EYE", "RIGHT EYE", "NOSE", "LEFT EAR", "RIGHT EAR"]
ANCHOR = "NECK"
TIE = 1.5  # px: distance margin under which ownership is marked uncertain
BAND_UP, BAND_DOWN = 2, 2  # seam rows round the base neck row (shared coords)
REACH = 5  # px: how far outside the bald head a head pick may reach (hair volume, helmet shell)


# --- sources and coordinates -------------------------------------------------

_img = {}


def raw(variant, F):
	from PIL import Image
	if (variant, F) not in _img:
		zipn, state, _ = VARIANTS[variant]
		_img[variant, F] = Image.open(io.BytesIO(zipfile.ZipFile(os.path.join(SRC, zipn)).read(
			"%s/rotations/%s.png" % (state, FD[F])))).convert("RGBA")
	return _img[variant, F]


def stored_skeleton(variant, F):
	"""PixelLab's stored keypoints, placed by canvas centring only (shared coords)."""
	skel = json.load(open(SKEL))
	key = variant if variant in skel else "slicked20"  # the bald base has none stored: it shares the template's
	k = skel[key]["skel"][FD[F]]
	w, h = skel[key]["size"]["width"], skel[key]["size"]["height"]
	ko = ((SHARED - w) // 2, (SHARED - h) // 2)
	return {n: (v["x"] * (w - 1) + ko[0], v["y"] * (h - 1) + ko[1]) for n, v in k.items()}


FEET = 8  # rows above the soles used to register a variant: below every wing, cape tip and weapon


_off = {}


def register(variant, F):
	"""canvas_offset (dx, dy) source -> shared, measured from the pixels: the shift that lays this
	variant's feet (its lowest FEET rows) best over the bald base's feet. PixelLab state changes can
	move the drawing on its canvas without moving the stored skeleton (dragoon_wings: up to 7 px), so
	the stored skeleton is only checked against this, never trusted for placement."""
	if (variant, F) in _off:
		return _off[variant, F]
	im = raw(variant, F)
	c = ((SHARED - im.width) // 2, (SHARED - im.height) // 2)
	if variant == "base":
		_off[variant, F] = c
		return c
	b = raw("base", F)
	bp = opaque(b)
	bb = max(y for _, y in bp)
	bfeet = {p for p in bp if p[1] > bb - FEET}
	vp = opaque(im)
	vb = max(y for _, y in vp)
	vfeet = [p for p in vp if p[1] > vb - FEET]
	best = None
	for dx in range(-12, 13):
		for dy in range(-4, 5):
			sh = {(x + c[0] + dx, y + c[1] + dy) for x, y in vfeet}
			inter = len(sh & bfeet)
			score = inter / float(len(sh | bfeet))
			if best is None or score > best[0] + 1e-9 or (abs(score - best[0]) < 1e-9 and abs(dx) + abs(dy) < abs(best[1]) + abs(best[2])):
				best = (score, dx, dy)
	_off[variant, F] = (c[0] + best[1], c[1] + best[2])
	return _off[variant, F]


def source(variant, F):
	"""(RGBA image on its own canvas, canvas_offset source -> shared (measured), keypoints in shared coords).
	Keypoints are the reference skeleton: every variant shares the base's anatomy once registered."""
	return raw(variant, F), register(variant, F), stored_skeleton("slicked20", F)


def registration(variant, F):
	"""How far the stored skeleton sits from where the pixels put this variant (px, per point), plus
	the feet overlap. Large numbers: PixelLab moved the drawing; placement uses the pixels."""
	im = raw(variant, F)
	c = ((SHARED - im.width) // 2, (SHARED - im.height) // 2)
	off = register(variant, F)
	st = stored_skeleton(variant, F)
	ref = stored_skeleton("slicked20", F)
	# the stored skeleton, moved by the measured shift, against the reference
	sh = (off[0] - c[0], off[1] - c[1])
	return {n: round(math.dist((st[n][0] + sh[0], st[n][1] + sh[1]), ref[n]), 2) for n in [ANCHOR] + HEAD_POINTS}


def opaque(im):
	a = im.load()
	return {(x, y) for y in range(im.height) for x in range(im.width) if a[x, y][3] > 0}


# --- the proposal --------------------------------------------------------------

_ref = {}


def ref_neck_row(F):
	"""Top row of the bald base's narrowest neck rows (shared coords): the centre of the seam band."""
	if F in _ref:
		return _ref[F]
	im, off, _ = source("base", F)
	a = im.load()
	wid = {}
	for y in range(12, 29):
		xs = [x for x in range(im.width) if a[x, y][3] > 0]
		wid[y] = (max(xs) - min(xs) + 1) if xs else 99
	m = min(wid.values())
	_ref[F] = min(y for y, v in wid.items() if v <= m + 1) + off[1]
	return _ref[F]


def seam(im, off, F, xs):
	"""{x: row} (source coords) through the darkest pixels in the band, one row per column, steps <= 1."""
	a = im.load()
	r0 = ref_neck_row(F) - off[1]
	rows = list(range(r0 - BAND_UP, r0 + BAND_DOWN + 1))
	def cost(x, y):
		if not (0 <= x < im.width and 0 <= y < im.height) or a[x, y][3] == 0:
			return 0.35  # air: a free-ish pass, but a drawn outline is cheaper
		return sum(a[x, y][:3]) / 765.0
	best = {y: (cost(xs[0], y), [y]) for y in rows}
	for x in xs[1:]:
		nb = {}
		for y in rows:
			c, p = min((best[py] for py in (y - 1, y, y + 1) if py in best), key=lambda t: t[0])
			nb[y] = (c + cost(x, y), p + [y])
		best = nb
	path = min(best.values(), key=lambda t: t[0])[1]
	return dict(zip(xs, path))


def propose(variant, F):
	"""(head set, uncertain set, info) in source coords."""
	im, off, kp = source(variant, F)
	pix = opaque(im)
	base, boff, _ = source("base", F)
	bsil = {(x + boff[0] - off[0], y + boff[1] - off[1]) for x, y in opaque(base)}  # bald silhouette, this canvas
	xs_all = sorted({x for x, _ in bsil})
	sv = seam(im, off, F, list(range(xs_all[0], xs_all[-1] + 1)))
	sb = seam(base, boff, F, list(range(min(x for x, _ in opaque(base)), max(x for x, _ in opaque(base)) + 1)))
	sb = {x + boff[0] - off[0]: y + boff[1] - off[1] for x, y in sb.items()}
	# Head core: variant pixels inside the bald silhouette, above both seams' columns (the variant's seam rules).
	head_core = {(x, y) for x, y in pix if (x, y) in bsil and x in sv and y <= sv[x]}
	body_core = {(x, y) for x, y in pix if (x, y) in bsil and not (x in sv and y <= sv[x])}
	rest = pix - head_core - body_core
	def nearest(p, core):
		return min((math.dist(p, q) for q in core), default=1e9)
	pick, unc = set(head_core), set()
	bald_head = {p for p in bsil if p[0] in sb and p[1] <= sb[p[0]]}
	crown = min(y for _, y in bald_head)
	hx0, hx1 = min(x for x, _ in bald_head), max(x for x, _ in bald_head)
	cand = {}
	for p in rest:
		dh, db = nearest(p, head_core), nearest(p, body_core)
		reach = nearest(p, bald_head)
		above = p[1] < crown + 3 and hx0 - 2 <= p[0] <= hx1 + 2
		ok = dh < db and (reach <= REACH or above)
		cand[p] = (dh if ok else 1e9, db)
		if abs(dh - db) <= TIE or (not above and abs(reach - REACH) <= 1 and dh < db):
			unc.add(p)
	# head picks must join the head through head pixels
	todo = list(head_core)
	while todo:
		x, y = todo.pop()
		for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
			if n in cand and n not in pick and cand[n][0] < cand[n][1]:
				pick.add(n)
				todo.append(n)
	for p, (dh, db) in cand.items():
		if dh < db and p not in pick:
			unc.add(p)  # nearer the head but cut off from it: ask
	# the seam where head meets body is a judgement call too
	for x, y in pick:
		if (x, y + 1) in pix and (x, y + 1) not in pick:
			unc.add((x, y))
	info = {"seam": {str(x): y for x, y in sv.items()}, "neck_row_shared": ref_neck_row(F)}
	return pick, unc, info


# --- masks and edits ------------------------------------------------------------

def folder(variant):
	d = os.path.join(OUT, variant)
	os.makedirs(d, exist_ok=True)
	return d


def save_set(path, s, size):
	from PIL import Image
	m = Image.new("L", size, 0)
	px = m.load()
	for p in s:
		px[p] = 255
	m.save(path)


def load_set(path):
	from PIL import Image
	m = Image.open(path).convert("L")
	px = m.load()
	return {(x, y) for y in range(m.height) for x in range(m.width) if px[x, y] >= 128}


def edits_path(variant, F):
	return os.path.join(folder(variant), "edits_%s.json" % F)


def load_edits(variant, F):
	p = edits_path(variant, F)
	return json.load(open(p)) if os.path.exists(p) else {"ops": [], "redo": []}


def final(variant, F):
	"""(head mask, uncertain still open) after the edits (or a hand-painted mask_<F>.png)."""
	d = folder(variant)
	painted = os.path.join(d, "mask_%s.png" % F)
	unc = set(tuple(p) for p in json.load(open(os.path.join(d, "review_%s.json" % F)))["uncertain"]) \
		if os.path.exists(os.path.join(d, "review_%s.json" % F)) else set()
	if os.path.exists(painted):
		m = load_set(painted)
	else:
		m = load_set(os.path.join(d, "mask_auto_%s.png" % F))
	for op in load_edits(variant, F)["ops"]:
		px = {tuple(p) for p in op["px"]}
		if op["op"] == "add":
			m |= px
		elif op["op"] == "remove":
			m -= px
		unc -= px  # any edit on a pixel is a decision
	return m, unc


def do_propose(variant, Fs):
	if variant in SKIP:
		sys.exit("%s is left out of head swapping (SKIP)" % variant)
	d = folder(variant)
	for F in Fs:
		im, off, _ = source(variant, F)
		m, unc, info = propose(variant, F)
		save_set(os.path.join(d, "mask_auto_%s.png" % F), m, im.size)
		json.dump({"uncertain": sorted(unc), **info}, open(os.path.join(d, "review_%s.json" % F), "w"))
		print(variant, F, "head", len(m), "uncertain", len(unc))


def do_edit(variant, F, op, pts):
	e = load_edits(variant, F)
	e["ops"].append({"op": op, "px": [[int(v) for v in p.split(",")] for p in pts]})
	e["redo"] = []
	json.dump(e, open(edits_path(variant, F), "w"))


def do_undo(variant, F, redo=False):
	e = load_edits(variant, F)
	src, dst = ("redo", "ops") if redo else ("ops", "redo")
	if e[src]:
		e[dst].append(e[src].pop())
	json.dump(e, open(edits_path(variant, F), "w"))
	print("ops", len(e["ops"]), "redo", len(e["redo"]))


def do_show(variant, F, box=None):
	im, _, _ = source(variant, F)
	m, unc = final(variant, F)
	pix = opaque(im)
	x0, y0, x1, y1 = box or (0, 0, im.width - 1, 34)
	print("    " + "".join(str(x % 10) for x in range(x0, x1 + 1)))
	for y in range(y0, y1 + 1):
		print("%3d " % y + "".join("?" if (x, y) in unc else ("H" if (x, y) in m else ("b" if (x, y) in pix else "."))
			for x in range(x0, x1 + 1)))


# --- extraction, alignment ------------------------------------------------------

def missing(body_pix, removed):
	"""Removed pixels that now leave a hole inside the body (enclosed: no way out to the canvas edge
	through air on a 4-path without crossing the body), i.e. body artwork nobody painted."""
	if not removed:
		return set()
	xs = [x for x, _ in body_pix | removed]
	ys = [y for _, y in body_pix | removed]
	x0, x1, y0, y1 = min(xs) - 1, max(xs) + 1, min(ys) - 1, max(ys) + 1
	out, todo = {(x0, y0)}, [(x0, y0)]
	while todo:
		x, y = todo.pop()
		for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
			if x0 <= n[0] <= x1 and y0 <= n[1] <= y1 and n not in out and n not in body_pix:
				out.add(n)
				todo.append(n)
	return {p for p in removed if p not in out}


def touchup(im, head_mask, body_pix):
	"""Body pixels within 4 px below/beside the head module that use one of the head's skin colours."""
	a = im.load()
	skin = set()
	for p in head_mask:
		r, g, b = a[p][:3]
		if r >= 140 and r > g > b and g >= 0.55 * r and b >= 0.4 * r:
			skin.add(a[p][:3])
	low = {}
	for x, y in head_mask:
		low[x] = max(low.get(x, -1), y)
	near = lambda x, y: any(xx in low and 0 <= y - low[xx] <= 4 for xx in range(x - 4, x + 5))
	return {p for p in body_pix if a[p][:3] in skin and near(*p)}


def do_extract(variant, Fs):
	from PIL import Image
	d = folder(variant)
	mp = os.path.join(d, "module.json")
	meta = json.load(open(mp)) if os.path.exists(mp) else {}
	zipn, state, helm = VARIANTS[variant]
	meta.update({"variant": variant, "source": "%s:%s rotations" % (zipn, state), "mode": "replace",
		"helmeted": helm, "anchor_point": ANCHOR})
	for F in Fs:
		im, off, kp = source(variant, F)
		m, unc = final(variant, F)
		a = im.load()
		head = Image.new("RGBA", im.size)
		body = Image.new("RGBA", im.size)
		h, b = head.load(), body.load()
		for y in range(im.height):
			for x in range(im.width):
				if a[x, y][3] == 0:
					continue
				(h if (x, y) in m else b)[x, y] = a[x, y]
		re = body.copy()
		re.alpha_composite(head)
		assert re.tobytes() == im.tobytes(), "%s %s: head + body != source" % (variant, F)
		head.save(os.path.join(d, "head_%s.png" % F))
		body.save(os.path.join(d, "body_%s.png" % F))
		miss = missing(opaque(body), m & opaque(im))
		tu = touchup(im, m & opaque(im), opaque(body))
		reg = registration(variant, F)
		meta.setdefault("canvas", {})[F] = list(im.size)
		meta.setdefault("canvas_offset", {})[F] = list(off)
		meta.setdefault("anchor", {})[F] = [round(kp[ANCHOR][0], 2), round(kp[ANCHOR][1], 2)]
		meta.setdefault("registration", {})[F] = reg
		meta.setdefault("flags", {})[F] = {"uncertain": len(unc), "missing": sorted(miss), "touchup": sorted(tu),
			"skeleton_disagrees_px": max(reg.values())}
		print(variant, F, "head", len(m), "uncertain", len(unc), "missing", len(miss), "registration", max(reg.values()))
	json.dump(meta, open(mp, "w"), indent="\t")


# --- composition ------------------------------------------------------------------

def compose(body_variant, head_variant, F):
	"""The one head slot: body_variant's headless body + exactly one head module (its own when
	head_variant is None or equal), placed so the module's neck anchor lands on the body's.
	Returns (image on the body's canvas, gap pixels: air enclosed by the result)."""
	from PIL import Image
	bm = json.load(open(os.path.join(OUT, body_variant, "module.json")))
	hv = head_variant or body_variant
	hm = json.load(open(os.path.join(OUT, hv, "module.json")))
	fixed = os.path.join(OUT, body_variant, "body_touchup_%s.png" % F)
	body = Image.open(fixed if os.path.exists(fixed) else os.path.join(OUT, body_variant, "body_%s.png" % F)).convert("RGBA")
	head = Image.open(os.path.join(OUT, hv, "head_%s.png" % F)).convert("RGBA")
	# shared -> body canvas: minus the body's offset; the head's anchor (shared) -> body anchor (shared)
	ba, ha = bm["anchor"][F], hm["anchor"][F]
	bo, ho = bm["canvas_offset"][F], hm["canvas_offset"][F]
	dx = round((ba[0] - ha[0]) + ho[0] - bo[0])
	dy = round((ba[1] - ha[1]) + ho[1] - bo[1])
	out = body.copy()
	out.alpha_composite(head, (dx, dy)) if dx >= 0 and dy >= 0 else _paste(out, head, dx, dy)
	return out, missing(opaque(out), set()) | _gaps(out, body)


def _paste(dst, src, dx, dy):
	from PIL import Image
	c = Image.new("RGBA", dst.size)
	c.paste(src, (dx, dy))
	dst.alpha_composite(c)


def _gaps(out, body):
	"""Air pixels enclosed by the composed character (no 4-path to the edge): a seam between module and body."""
	pix = opaque(out)
	w, h = out.size
	todo = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
	todo = [p for p in todo if p not in pix]
	seen = set(todo)
	while todo:
		x, y = todo.pop()
		for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
			if 0 <= n[0] < w and 0 <= n[1] < h and n not in seen and n not in pix:
				seen.add(n)
				todo.append(n)
	return {(x, y) for y in range(h) for x in range(w) if (x, y) not in pix and (x, y) not in seen}


# --- diagnostics ---------------------------------------------------------------------

def do_preview(base_v, helm_v, out):
	"""Per facing: A base source + mask | B base head | A helmet source + mask | B helmet module |
	C headless base body | D body + base head | E body + helmet (base head off)."""
	from PIL import Image, ImageDraw
	K, CW, CH = 5, 44, 40
	cols = ["A %s mask" % base_v, "B %s head" % base_v] + (["A %s mask" % helm_v, "B %s module" % helm_v] if helm_v else []) + \
		["C headless body (orange: touch up)", "D body + own head"] + (["E body + %s" % helm_v] if helm_v else [])
	o = Image.new("RGBA", (len(cols) * CW * K, 4 * CH * K + 24), (24, 25, 34, 255))
	dr = ImageDraw.Draw(o)
	for i, c in enumerate(cols):
		dr.text((i * CW * K + 4, 6), c, fill=(255, 255, 255))
	def checker(size):
		c = Image.new("RGBA", size, (90, 90, 100, 255))
		px = c.load()
		for y in range(size[1]):
			for x in range(size[0]):
				if (x // 2 + y // 2) % 2:
					px[x, y] = (130, 130, 140, 255)
		return c
	def tinted(v, F):
		im, _, _ = source(v, F)
		m, unc = final(v, F)
		t = im.copy()
		px = t.load()
		for y in range(t.height):
			for x in range(t.width):
				c = px[x, y]
				if c[3] == 0:
					continue
				if (x, y) in unc:
					px[x, y] = (255, 230, 0, 255)
				elif (x, y) in m:
					px[x, y] = ((c[0] + 0) // 2, (c[1] + 255) // 2, (c[2] + 255) // 2, 255)
				else:
					px[x, y] = (c[0] // 3, c[1] // 3, c[2] // 3, 255)
		return t
	def flagged(im, gaps, col=(255, 0, 0, 255)):
		t = im.copy()
		px = t.load()
		for p in gaps:
			if 0 <= p[0] < t.width and 0 <= p[1] < t.height:
				px[p] = col
		return t
	for r, F in enumerate(["SE", "SW", "NE", "NW"]):
		bm = json.load(open(os.path.join(OUT, base_v, "module.json")))
		ax, ay = bm["anchor"][F]
		bo = bm["canvas_offset"][F]
		cx, cy = int(ax) - bo[0], int(ay) - bo[1]
		def put(i, im, offset=(0, 0)):
			x0, y0 = cx - CW // 2 + offset[0], cy - 30 + offset[1]
			cell = checker((CW, CH))
			cell.alpha_composite(im.crop((x0, y0, x0 + CW, y0 + CH)))
			o.alpha_composite(cell.resize((CW * K, CH * K), Image.NEAREST), (i * CW * K, 24 + r * CH * K))
		put(0, tinted(base_v, F))
		put(1, Image.open(os.path.join(OUT, base_v, "head_%s.png" % F)))
		col = 2
		if helm_v:
			hm = json.load(open(os.path.join(OUT, helm_v, "module.json")))
			ho = hm["canvas_offset"][F]
			hoff = (ho[0] * -1 + bo[0], ho[1] * -1 + bo[1])
			put(2, tinted(helm_v, F), hoff)
			put(3, Image.open(os.path.join(OUT, helm_v, "head_%s.png" % F)), hoff)
			col = 4
		body = Image.open(os.path.join(OUT, base_v, "body_%s.png" % F))
		miss = set(tuple(p) for p in bm["flags"][F]["missing"])
		tu = set(tuple(p) for p in bm["flags"][F].get("touchup", []))
		put(col, flagged(flagged(body, tu, (255, 140, 0, 255)), miss))
		d_img, d_gap = compose(base_v, None, F)
		put(col + 1, flagged(d_img, d_gap))
		if helm_v:
			e_img, e_gap = compose(base_v, helm_v, F)
			put(col + 2, flagged(e_img, e_gap))
		src, _, _ = source(base_v, F)
		same = d_img.tobytes() == src.tobytes()
		dr.text(((col + 1) * CW * K + 4, 24 + r * CH * K + 4), "%s  D == source: %s  touch-up px: %d" % (F, "yes" if same else "NO", len(tu)),
			fill=(120, 255, 120) if same else (255, 80, 80))
	o.save(out)
	print(out)


def do_check() -> int:
	"""Acceptance checks on every extracted variant; prints open flags. Exit 1 on a broken rule."""
	from PIL import Image
	bad = 0
	for v in sorted(os.listdir(OUT)) if os.path.isdir(OUT) else []:
		mp = os.path.join(OUT, v, "module.json")
		if not os.path.exists(mp):
			continue
		meta = json.load(open(mp))
		for F in meta.get("anchor", {}):
			im, _, _ = source(v, F)
			m, unc = final(v, F)
			head = Image.open(os.path.join(OUT, v, "head_%s.png" % F)).convert("RGBA")
			body = Image.open(os.path.join(OUT, v, "body_%s.png" % F)).convert("RGBA")
			re = body.copy()
			re.alpha_composite(head)
			hp, bp = opaque(head), opaque(body)
			ok = re.tobytes() == im.tobytes() and not (hp & bp) and hp == (m & opaque(im))
			if not ok:
				bad += 1
			fl = meta["flags"][F]
			print("%-14s %s  %s  uncertain %d  missing %d  skeleton off %.1f px" % (v, F, "ok " if ok else "BAD",
				len(unc), len(fl["missing"]), fl["skeleton_disagrees_px"]))
	return 1 if bad else 0


if __name__ == "__main__":
	a = sys.argv[1:]
	if not a:
		print(__doc__)
	elif a[0] == "propose":
		do_propose(a[1], a[2:] or list(FD))
	elif a[0] == "edit":
		do_edit(a[1], a[2], a[3], a[4:])
	elif a[0] in ("undo", "redo"):
		do_undo(a[1], a[2], a[0] == "redo")
	elif a[0] == "show":
		do_show(a[1], a[2], tuple(int(v) for v in a[3].split(",")) if len(a) > 3 else None)
	elif a[0] == "extract":
		do_extract(a[1], a[2:] or list(FD))
	elif a[0] == "preview":
		do_preview(a[1], a[2] if a[2] != "-" else None, a[3])
	elif a[0] == "check":
		sys.exit(do_check())
