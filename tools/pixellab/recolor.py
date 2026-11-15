"""Recoloured characters: new units made from animated ones by moving colours
(Brian, 2026-11-15). Free; the source unit is never changed.

    python3 -I tools/pixellab/recolor.py propose out.png [unit ...]   accent swaps to pick from (standing poses only)
    python3 -I tools/pixellab/recolor.py preview out.png              every variant in recolors.json, before | after
    python3 -I tools/pixellab/recolor.py bake [id ...]                write the unit folders for these variants

Variants live in tools/pixellab/recolors.json:
  [{"id": "outfit_samurai_jade", "from": "outfit_samurai",
    "rules": [{"hue": [330, 30], "to": 140, "min_sat": 0.45, "sat": 1.0, "val": 1.0}],
    "swap": {"#ff0000": "#00ff00"}}]
A rule moves every pixel whose hue is inside [from, to] degrees (wrapping past
360) and whose saturation is at least min_sat (default 0.45, which keeps skin,
greys and outlines as they are), so the band's middle lands on "to"; sat / val
scale saturation and brightness. "swap" changes exact colours first.
Alpha is kept; nothing else changes.

A baked variant is a whole unit folder, assets/units/<id>/: the source's PixelLab
zips unpacked recoloured into export/, its loose frame folders (aim_pistol/,
rest_rifle/ ...) recoloured at the same paths, frames it borrows from
elsewhere (outfit units' frames_from) recoloured into frames/, and its
pixellab.json / rig.json copied with the paths moved to the new folder. The
game sees it like any other unit (unit gallery, sprite_frames_path).
"""
import colorsys
import io
import json
import os
import shutil
import sys
import zipfile

UNITS = os.path.join("assets", "units")
SPEC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "recolors.json")
FACINGS = {"south-east": "SE", "south-west": "SW", "north-east": "NE", "north-west": "NW"}


def _hex(c):
	c = c.lstrip("#")
	return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def in_band(h, band):
	a, b = band[0] % 360, band[1] % 360
	return a <= h <= b if a <= b else (h >= a or h <= b)


def recolor_image(im, rules, swap=None):
	"""Copy of RGBA image `im` with the variant's colours."""
	sw = {_hex(k): _hex(v) for k, v in (swap or {}).items()}
	out = im.copy()
	px = out.load()
	cache = {}
	for y in range(out.height):
		for x in range(out.width):
			r, g, b, a = px[x, y]
			if a == 0:
				continue
			key = (r, g, b)
			if key not in cache:
				c = sw.get(key, key)
				h, s, v = colorsys.rgb_to_hsv(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)
				hd = h * 360.0
				for rule in rules:
					if s >= rule.get("min_sat", 0.45) and in_band(hd, rule["hue"]):
						a0, b0 = rule["hue"][0] % 360, rule["hue"][1] % 360
						mid = (a0 + ((b0 - a0) % 360) / 2.0) % 360
						hd = (hd + rule["to"] - mid) % 360
						s = min(1.0, s * rule.get("sat", 1.0))
						v = min(1.0, v * rule.get("val", 1.0))
						c = tuple(int(round(t * 255)) for t in colorsys.hsv_to_rgb(hd / 360.0, s, v))
						break
				cache[key] = c
			c = cache[key]
			px[x, y] = (c[0], c[1], c[2], a)
	return out


# --- reading a unit's standing poses ------------------------------------------------

def standing(unit):
	"""{facing: RGBA image} of a unit's standing pose (the four battle facings)."""
	from PIL import Image
	d = os.path.join(UNITS, unit)
	out = {}
	for root, dirs, files in os.walk(os.path.join(d, "export")):
		if root.endswith("rotations"):
			for f in files:
				fc = FACINGS.get(f[:-4])
				if fc:
					out[fc] = Image.open(os.path.join(root, f)).convert("RGBA")
			if out:
				return out
	for z in sorted(f for f in os.listdir(d) if f.endswith(".zip")):
		zf = zipfile.ZipFile(os.path.join(d, z))
		names = [n for n in zf.namelist() if "/rotations/" in n and n.endswith(".png")]
		names.sort(key=lambda n: (not n.startswith("Idle/"), n))
		for n in names:
			fc = FACINGS.get(n.rsplit("/", 1)[1][:-4])
			if fc and fc not in out:
				out[fc] = Image.open(io.BytesIO(zf.read(n))).convert("RGBA")
		if out:
			return out
	return out


def accent(ims):
	"""The most used saturated hue band (degrees) across the standing poses, or None."""
	hist = [0] * 12
	for im in ims.values():
		for r, g, b, a in im.getdata():
			if a == 0:
				continue
			h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
			if s >= 0.45 and v >= 0.3:
				hist[int(h * 12) % 12] += 1
	if max(hist) < 12:
		return None
	i = hist.index(max(hist))
	return [(i * 30 - 20) % 360, (i * 30 + 50) % 360]


TARGETS = [("red", 0), ("gold", 45), ("green", 130), ("cyan", 185), ("violet", 280), ("pink", 320)]


def propose(out, units):
	from PIL import Image, ImageDraw
	K = 3
	rows = []
	for u in units:
		ims = standing(u)
		if "SE" not in ims:
			continue
		band = accent(ims)
		if band is None:
			rows.append((u, None, ims["SE"], []))
			continue
		mid = (band[0] + 35) % 360
		picks = [(n, t) for n, t in TARGETS if min(abs(t - mid), 360 - abs(t - mid)) > 50][:4]
		rows.append((u, band, ims["SE"], [(n, t, recolor_image(ims["SE"], [{"hue": band, "to": t}])) for n, t in picks]))
	W = 70 * K
	o = Image.new("RGBA", (5 * W + 170, len(rows) * (64 * K) + 10), (24, 25, 34, 255))
	d = ImageDraw.Draw(o)
	for r, (u, band, src, vs) in enumerate(rows):
		y = 5 + r * 64 * K
		d.text((4, y + 4), u, fill=(255, 255, 255))
		d.text((4, y + 18), "accent %s" % (band,), fill=(170, 170, 190))
		for c, im in enumerate([src] + [v[2] for v in vs]):
			cell = Image.new("RGBA", (70, 64))
			cell.alpha_composite(im.crop((0, 0, 70, 64)) if im.width >= 70 else im, ((70 - im.width) // 2, 0))
			o.alpha_composite(cell.resize((W, 64 * K), Image.NEAREST), (170 + c * W, y))
			if c:
				d.text((170 + c * W + 4, y + 4), "%s (%d)" % (vs[c - 1][0], vs[c - 1][1]), fill=(255, 255, 0))
		if band is None:
			d.text((170 + W + 4, y + 40), "no strong accent colour: use a swap rule", fill=(255, 160, 80))
	o.save(out)
	print(out, len(rows), "units")


def preview(out):
	from PIL import Image, ImageDraw
	spec = json.load(open(SPEC)) if os.path.exists(SPEC) else []
	K = 3
	o = Image.new("RGBA", (8 * 64 * K + 10, max(1, len(spec)) * 64 * K + 10), (24, 25, 34, 255))
	d = ImageDraw.Draw(o)
	for r, v in enumerate(spec):
		ims = standing(v["from"])
		for c, F in enumerate(["SE", "SW", "NE", "NW"]):
			if F not in ims:
				continue
			for k, im in enumerate((ims[F], recolor_image(ims[F], v.get("rules", []), v.get("swap")))):
				o.alpha_composite(im.resize((im.width * K, im.height * K), Image.NEAREST), ((c * 2 + k) * 64 * K, 5 + r * 64 * K))
		d.text((4, 8 + r * 64 * K), v["id"], fill=(255, 255, 0))
	o.save(out)
	print(out)


# --- baking a unit folder --------------------------------------------------------------

def bake(v):
	from PIL import Image
	src = os.path.join(UNITS, v["from"])
	dst = os.path.join(UNITS, v["id"])
	if os.path.isdir(dst):
		shutil.rmtree(dst)
	os.makedirs(dst)
	rules, swap = v.get("rules", []), v.get("swap")
	n = 0
	def write_png(data_or_path, out_path):
		nonlocal n
		im = Image.open(io.BytesIO(data_or_path) if isinstance(data_or_path, bytes) else data_or_path).convert("RGBA")
		os.makedirs(os.path.dirname(out_path), exist_ok=True)
		recolor_image(im, rules, swap).save(out_path)
		n += 1
	src_res, dst_res = "res://assets/units/%s/" % v["from"], "res://assets/units/%s/" % v["id"]
	for f in sorted(os.listdir(src)):
		p = os.path.join(src, f)
		if f.endswith(".zip"):
			zf = zipfile.ZipFile(p)
			for name in zf.namelist():
				if name.endswith(".png"):
					write_png(zf.read(name), os.path.join(dst, "export", f[:-4], name))
		elif os.path.isdir(p) and f not in ("extracted",):
			for root, _, files in os.walk(p):
				for ff in files:
					if ff.endswith(".png"):
						write_png(os.path.join(root, ff), os.path.join(dst, os.path.relpath(os.path.join(root, ff), src)))
	for jf in ("pixellab.json", "rig.json"):
		p = os.path.join(src, jf)
		if not os.path.exists(p):
			continue
		conf = json.load(open(p))
		if jf == "pixellab.json":
			# frames borrowed from outside the unit: recolour them into frames/<anim>/<facing>/
			for anim, by_f in conf.get("frames_from", {}).items():
				for F, spec in by_f.items():
					d0 = spec["dir"]
					if d0.startswith(src_res):
						continue
					local = os.path.join("frames", anim, F)
					fs = d0[len("res://"):]
					for ff in sorted(os.listdir(fs)):
						if ff.startswith("frame_") and ff.endswith(".png"):
							write_png(os.path.join(fs, ff), os.path.join(dst, local, ff))
					spec["dir"] = dst_res + local.replace(os.sep, "/")
			conf["_recolor"] = {"from": v["from"], "rules": rules, "swap": swap or {}}
		text = json.dumps(conf, indent="\t").replace(src_res, dst_res)
		open(os.path.join(dst, jf), "w").write(text)
	print(dst, n, "pictures")


def main():
	a = sys.argv[1:]
	if not a:
		print(__doc__)
	elif a[0] == "propose":
		us = a[2:] or sorted(u for u in os.listdir(UNITS) if u.startswith(("outfit_", "pool_")))
		propose(a[1], us)
	elif a[0] == "preview":
		preview(a[1])
	elif a[0] == "bake":
		spec = json.load(open(SPEC))
		for v in spec:
			if not a[1:] or v["id"] in a[1:]:
				bake(v)


if __name__ == "__main__":
	main()
