"""Cut the helmets (and the hood) out of Brian's helmeted outfits as head pieces
that ride any body (Brian, 2026-11-14: "helmets as separate head pieces"). Free.

    python3 -I tools/gear/cut_helmets.py [--sheet out.png]

Per outfit and facing: the standing rotation's pixels down to the neck line
that join the head (flood fill from between the eyes). The neck line is the
bald base body's (light_bodysuit) narrowest neck row in that facing, since
every outfit stands on the base's skeleton (the skeleton's NECK point sits at
the collar, too low). Rows from a little above the eyes down keep only the
skull's own width (measured above them), so wings, backpack pipes and
shoulder pads beside the face stay out; a box round the head bounds the rest.
Eyes come from the standing skeletons (assets/gear/source/helmets/skeletons.json).
Writes assets/gear/armor/helmet_<unit>/<FACING>.png (the piece alone, cropped)
plus attach.json: point "head", grip = the eyes' midpoint in the picture, so
a rig's head point at a body's eyes seats it (GearAttach).
"""
import io
import json
import os
import sys
import zipfile

SRC = os.path.join("assets", "units", "base_male_hi", "source")
OUT = os.path.join("assets", "gear", "armor")
SKEL = os.path.join("assets", "gear", "source", "helmets", "skeletons.json")
DIRS = {"south": "S", "south-east": "SE", "east": "E", "north-east": "NE", "north": "N", "north-west": "NW", "west": "W", "south-west": "SW"}
# unit -> (zip, state, name shown in the game, box half-width round the head, extra rows under the neck)
HELMETS = {
	"samurai": ("outfit_states_r2.zip", "street_samurai", "Kabuto Helm", 13, 0),
	"tinkerer": ("outfit_states_r2.zip", "scrap_tinkerer", "Scrap Grille Helm", 11, 0),
	"dragoon_helm": ("outfit_states_r2.zip", "jumpjet_dragoon_with_helmet", "Dragoon Visor Helm", 11, 0),
	"neon_coat": ("outfit_states_r2.zip", "new_char_01", "Neon Visor Helm", 11, 0),
	"dragoon_wings": ("outfit_states_r3.zip", "jumpjet_dragoon_full", "Jumpjet Helm", 14, 0),
	"armor_6142": ("outfit_states_r3.zip", "6142", "Red Visor Helm", 11, 0),
	"hood_0101": ("outfit_states_r3.zip", "0101", "Assassin Hood", 12, 0),
	"armor_009": ("outfit_states_r3.zip", "009", "Cyan Visor Helm", 11, 0),
}


def base_neck(im) -> int:
	"""The bald base's neck: the lowest row of its narrowest run between rows 12 and 28."""
	a = im.load()
	wid = {}
	for y in range(12, 29):
		xs = [x for x in range(im.width) if a[x, y][3] > 0]
		wid[y] = (max(xs) - min(xs) + 1) if xs else 99
	m = min(wid.values())
	y = min(k for k, v in wid.items() if v == m)
	while y + 1 in wid and wid[y + 1] <= m:
		y += 1
	return y


def cut(im, kp, half: int, extra: int, neck: int):
	"""Return (piece cropped, grip [x, y] in it, box, eye, neck row) or None."""
	from PIL import Image
	w, h = im.size
	P = {k: (v["x"] * (w - 1), v["y"] * (h - 1)) for k, v in kp.items()}
	eye = ((P["LEFT EYE"][0] + P["RIGHT EYE"][0]) / 2.0, (P["LEFT EYE"][1] + P["RIGHT EYE"][1]) / 2.0)
	neck_y = neck + extra
	cx = int(round(eye[0]))
	a = im.load()
	# The skull's width: the widest the head's row run reaches (round cx, in the box) above the eyes.
	skull_y = int(eye[1]) - 3
	lo, hi = cx, cx
	for y in range(0, skull_y + 1):
		if a[cx, y][3] == 0:
			continue
		l, r = cx, cx
		while l - 1 >= cx - half and a[l - 1, y][3] > 0:
			l -= 1
		while r + 1 <= cx + half and a[r + 1, y][3] > 0:
			r += 1
		lo, hi = min(lo, l), max(hi, r)
	inside = lambda x, y: abs(x - cx) <= half if y <= skull_y else lo - 1 <= x <= hi + 1
	ok = lambda x, y: 0 <= x < w and 0 <= y <= neck_y and inside(x, y) and a[x, y][3] > 0
	start = (cx, int(round(eye[1])))
	if not ok(*start):
		# nearest opaque pixel round the eyes
		c = [(x, y) for x in range(cx - 4, cx + 5) for y in range(start[1] - 4, start[1] + 5) if ok(x, y)]
		if not c:
			return None
		start = min(c, key=lambda p: (p[0] - cx) ** 2 + (p[1] - start[1]) ** 2)
	seen, todo = {start}, [start]
	while todo:
		x, y = todo.pop()
		for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
			if n not in seen and ok(*n):
				seen.add(n)
				todo.append(n)
	o = Image.new("RGBA", im.size)
	b = o.load()
	for x, y in seen:
		b[x, y] = a[x, y]
	box = o.getbbox()
	return o.crop(box), [round(eye[0] - box[0], 1), round(eye[1] - box[1], 1)], box, eye, neck_y


def main() -> None:
	from PIL import Image, ImageDraw
	skel = json.load(open(SKEL))
	sheet = []
	for unit, (zipn, state, name, half, extra) in HELMETS.items():
		z = zipfile.ZipFile(os.path.join(SRC, zipn))
		folder = os.path.join(OUT, "helmet_" + unit)
		os.makedirs(folder, exist_ok=True)
		grips = {}
		for d, F in DIRS.items():
			im = Image.open(io.BytesIO(z.read("%s/rotations/%s.png" % (state, d)))).convert("RGBA")
			base = Image.open(io.BytesIO(z.read("light_bodysuit/rotations/%s.png" % d))).convert("RGBA")
			if base.size != im.size:  # wider canvas (wings): the base centred in it
				b = Image.new("RGBA", im.size)
				b.alpha_composite(base, ((im.width - base.width) // 2, im.height - base.height))
				base = b
			r = cut(im, skel[unit]["skel"][d], half, extra, base_neck(base))
			if r is None:
				print("NO HEAD", unit, F)
				continue
			piece, grip, box, eye, neck_y = r
			piece.save(os.path.join(folder, F + ".png"))
			grips[F] = grip
			sheet.append((unit, F, im, piece, box, eye, neck_y, half))
		meta = {"point": "head", "grip": grips.get("SE", [0, 0]), "grips": grips, "order": 1,
			"name": name, "from": "%s:%s standing rotations" % (zipn, state)}
		json.dump(meta, open(os.path.join(folder, "attach.json"), "w"), indent="\t")
		print(unit, "->", folder, sorted(grips))
	if "--sheet" in sys.argv:
		K, C = 4, 68
		order = ["SE", "SW", "NE", "NW"]
		units = list(HELMETS)
		o = Image.new("RGBA", (len(order) * 2 * C * K, len(units) * C * K // 2 + 20), (60, 62, 80, 255))
		dd = ImageDraw.Draw(o)
		for unit, F, im, piece, box, eye, neck_y, half in sheet:
			if F not in order:
				continue
			r, c = units.index(unit), order.index(F)
			x0, y0 = c * 2 * C * K, 20 + r * C * K // 2
			src = im.crop((0, 0, im.width, 34)).resize((im.width * K, 34 * K), Image.NEAREST)
			o.alpha_composite(src, (x0, y0))
			dd.line([(x0, y0 + neck_y * K), (x0 + im.width * K, y0 + neck_y * K)], fill=(255, 0, 255, 255))
			cx = int(round(eye[0]))
			dd.rectangle([x0 + (cx - half) * K, y0, x0 + (cx + half + 1) * K, y0 + neck_y * K], outline=(255, 255, 0, 255))
			p = piece.resize((piece.width * K, piece.height * K), Image.NEAREST)
			o.alpha_composite(p, (x0 + C * K + box[0] * K, y0 + box[1] * K))
			dd.text((x0 + 4, y0 + 2), "%s %s" % (unit, F), fill=(255, 255, 255))
		o.save(sys.argv[sys.argv.index("--sheet") + 1])


if __name__ == "__main__":
	main()
