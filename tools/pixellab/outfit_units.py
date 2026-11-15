"""Package the 14 animated base_male_hi outfits as game units (Brian, 2026-11-15:
"push the characters and their animations so they are in game"). Free.

    python3 -I tools/pixellab/outfit_units.py            # every outfit
    python3 -I tools/pixellab/outfit_units.py samurai    # just these

Writes assets/units/outfit_<unit>/ the way src/vfx/pixel_lab.gd reads a unit:
  export/<state>/rotations/<direction>.png   the 8 standing poses (idle), from the outfit zip
  pixellab.json   every clip through frames_from, pointing at the approved clean
                  frames in assets/units/base_male_hi/source/<unit>_<clip>_<F>_clean
                  (nothing is copied; the newest take is the one in the plain folder):
                    walk2 -> walk (loop)   hit -> hit       death -> death   jump -> jump
                    use_item -> cast       throw -> throw   pistol -> aim and attack
                    rifle_rest -> rest_rifle (loop)         rifle_raise -> aim_rifle
  rig.json        hand / elbow / head points: the standing skeleton per facing
                  (assets/gear/source/helmets/skeletons.json) and, per frame of every
                  clip, the poses the frames were drawn on (aim.json next to them), with
                  the same gun rules as aim_pose.rig: forearm tilt on the pistol, the grip
                  side as hand_r and the support hand as hand_l on the rifle clips, gun_r.
Head swapping is not part of this (later); the units wear their own heads.
"""
import io
import json
import math
import os
import shutil
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aim_pose  # noqa: E402

SRC = os.path.join("assets", "units", "base_male_hi", "source")
SKEL = os.path.join("assets", "gear", "source", "helmets", "skeletons.json")
DIRS = {"south": "S", "south-east": "SE", "east": "E", "north-east": "NE", "north": "N", "north-west": "NW", "west": "W", "south-west": "SW"}
FACINGS = ["SE", "SW", "NE", "NW"]
RIGHT_HAND_FRONT = {"S": 1, "SE": 1, "E": 1, "NE": 1, "N": -1, "NW": -1, "W": -1, "SW": -1}
UNITS = {
	"medic_buns": ("outfit_states.zip", "same_character_same_6"),
	"longcoat": ("outfit_states.zip", "long_coat"),
	"dragoon": ("outfit_states.zip", "jumpjet_dragoon"),
	"undercut": ("outfit_states.zip", "same_character_same_2"),
	"heavy40": ("outfit_states.zip", "same_character_same_3"),
	"slicked20": ("outfit_states.zip", "same_character_same_4"),
	"samurai": ("outfit_states_r2.zip", "street_samurai"),
	"tinkerer": ("outfit_states_r2.zip", "scrap_tinkerer"),
	"dragoon_helm": ("outfit_states_r2.zip", "jumpjet_dragoon_with_helmet"),
	"neon_coat": ("outfit_states_r2.zip", "new_char_01"),
	"dragoon_wings": ("outfit_states_r3.zip", "jumpjet_dragoon_full"),
	"armor_6142": ("outfit_states_r3.zip", "6142"),
	"hood_0101": ("outfit_states_r3.zip", "0101"),
	"armor_009": ("outfit_states_r3.zip", "009"),
}
# clip -> (game action, loop); pistol also plays as attack
ACTIONS = {"walk2": ("walk", True), "hit": ("hit", False), "death": ("death", False), "jump": ("jump", False),
	"use_item": ("cast", False), "throw": ("throw", False), "pistol": ("aim", False),
	"rifle_rest": ("rest_rifle", True), "rifle_raise": ("aim_rifle", False)}
GUN = ("pistol", "rifle_rest", "rifle_raise")


def frames_dir(unit, clip, F):
	return os.path.join(SRC, "%s_%s_%s_clean" % (unit, clip, F))


def count(d):
	return len([f for f in os.listdir(d) if f.startswith("frame_") and f.endswith(".png")]) if os.path.isdir(d) else 0


def standing_base(unit, F):
	"""Standing keypoints on the clip canvas (as aim_pose.poses expects them before padding)."""
	sk = json.load(open(SKEL))[unit]
	w, h = int(sk["size"]["width"]), int(sk["size"]["height"])
	kp = sk["skel"][aim_pose.DIRS[F]]
	return {k: (v["x"] * (w - 1), v["y"] * (h - 1) + (w - h) / 2.0) for k, v in kp.items()}, w


def rig_for(unit):
	sk = json.load(open(SKEL))[unit]
	w, h = int(sk["size"]["width"]), int(sk["size"]["height"])
	names = {"hand_r": "RIGHT ARM", "hand_l": "LEFT ARM", "elbow_r": "RIGHT ELBOW", "elbow_l": "LEFT ELBOW", "head": "NOSE"}
	pts = {k: {"facing": {}, "anims": {}} for k in list(names) + ["shoulder_r", "gun_r"]}
	for d, kp in sk["skel"].items():
		F = DIRS[d]
		zr = RIGHT_HAND_FRONT[F]
		for name, label in names.items():
			z = zr if name.endswith("_r") else (-zr if name.endswith("_l") else 1)
			pts[name]["facing"][F] = [int(round(kp[label]["x"] * (w - 1))), int(round(kp[label]["y"] * (h - 1))), z]
	for F in FACINGS:
		base, bw = standing_base(unit, F)
		zr = RIGHT_HAND_FRONT[F]
		for clip, (act, _) in ACTIONS.items():
			meta_p = os.path.join(SRC, "%s_%s_%s" % (unit, clip, F), "aim.json")
			if not os.path.exists(meta_p):
				continue
			joints = json.load(open(meta_p))["joints"]
			n = count(frames_dir(unit, clip, F))
			fr = [joints[min(i, len(joints) - 1)] for i in range(n)]
			anims = [act + "_" + F] + (["attack_" + F] if clip == "pistol" else [])
			if clip in GUN:
				_gun_points(pts, fr, base, bw, F, clip, anims)
				continue
			for an in anims:
				pts["hand_r"]["anims"][an] = [[round(f["RIGHT ARM"][0]), round(f["RIGHT ARM"][1]), zr] for f in fr]
				pts["hand_l"]["anims"][an] = [[round(f["LEFT ARM"][0]), round(f["LEFT ARM"][1]), -zr] for f in fr]
				pts["elbow_r"]["anims"][an] = [[round(f["RIGHT ELBOW"][0]), round(f["RIGHT ELBOW"][1]), zr] for f in fr]
				pts["elbow_l"]["anims"][an] = [[round(f["LEFT ELBOW"][0]), round(f["LEFT ELBOW"][1]), -zr] for f in fr]
				pts["head"]["anims"][an] = [[round(f["NOSE"][0]), round(f["NOSE"][1]), 1] for f in fr]
	return {"source": "standing skeletons + the poses each clip was drawn on (tools/pixellab/outfit_units.py)",
		"cell": w, "points": pts}


def _gun_points(pts, frames, base, w, F, clip, anims):
	"""aim_pose.rig's rules, on the saved poses."""
	if clip in ("rifle_rest", "rifle_raise"):
		pad = (aim_pose.CANVAS - w) / 2.0
		g_, s_ = aim_pose.gun_sides({k: (v[0] + pad, v[1] + pad) for k, v in base.items()}, F)
		frames = [dict(f, **{"_sides": ("RIGHT", "LEFT"), "RIGHT ARM": f[g_ + " ARM"], "RIGHT ELBOW": f[g_ + " ELBOW"],
			"RIGHT SHOULDER": f[g_ + " SHOULDER"], "LEFT ARM": f[s_ + " ARM"]}) for f in frames]
	else:
		frames = [dict(f, _sides=("RIGHT", "LEFT")) for f in frames]
	gclip = "rifle_raise" if clip == "rifle_rest" else clip
	aim = aim_pose.gun_deg(frames[-1], gclip)
	sign = 1.0 if F.endswith("E") else -1.0
	def tilt(f):
		a = ((aim_pose.gun_deg(f, gclip) - aim + 180.0) % 360.0 - 180.0) * sign
		return round(max(-aim_pose.REST_TILT_MAX, min(aim_pose.REST_TILT_MAX, a)) * sign, 1)
	z = 1 if F.startswith("S") else -1
	for an in anims:
		pts["hand_r"]["anims"][an] = [[round(f["RIGHT ARM"][0]), round(f["RIGHT ARM"][1]), z, tilt(f)] for f in frames]
		pts["elbow_r"]["anims"][an] = [[round(f["RIGHT ELBOW"][0]), round(f["RIGHT ELBOW"][1]), z] for f in frames]
		pts["head"]["anims"][an] = [[round(f["NOSE"][0]), round(f["NOSE"][1]), 1] for f in frames]
		if clip == "pistol" and F in aim_pose.GUN_ALONG_AIM:
			aim_deg = math.degrees(math.atan2(aim_pose.AIM[F][1], aim_pose.AIM[F][0]))
			seq = aim_pose.RAISE + [1.0] * (len(frames) - len(aim_pose.RAISE))
			gun = []
			for f, t in zip(frames, seq):
				fa = aim_pose.forearm_deg(f)
				e = aim_pose.ease(t)
				gun.append([round(fa + ((aim_deg - fa + 180.0) % 360.0 - 180.0) * e, 1), 0, 0])
			pts["gun_r"]["anims"][an] = gun
		if clip in ("rifle_rest", "rifle_raise"):
			pts["shoulder_r"]["anims"][an] = [[round(f["RIGHT SHOULDER"][0]), round(f["RIGHT SHOULDER"][1]), z] for f in frames]
			pts["hand_l"]["anims"][an] = [[round(f["LEFT ARM"][0]), round(f["LEFT ARM"][1]), z] for f in frames]


def package(unit):
	zipn, state = UNITS[unit]
	out = os.path.join("assets", "units", "outfit_" + unit)
	rot = os.path.join(out, "export", unit, "rotations")
	if os.path.isdir(os.path.join(out, "export")):
		shutil.rmtree(os.path.join(out, "export"))
	os.makedirs(rot, exist_ok=True)
	z = zipfile.ZipFile(os.path.join(SRC, zipn))
	for d in DIRS:
		open(os.path.join(rot, d + ".png"), "wb").write(z.read("%s/rotations/%s.png" % (state, d)))
	ff, missing = {}, []
	for clip, (act, loop) in ACTIONS.items():
		for name in [act] + (["attack"] if clip == "pistol" else []):
			for F in FACINGS:
				d = frames_dir(unit, clip, F)
				n = count(d)
				if not n:
					missing.append("%s %s" % (clip, F))
					continue
				spec = {"dir": "res://" + d.replace(os.sep, "/"), "frames": [0, n - 1]}
				if loop:
					spec["loop"] = True
				ff.setdefault(name, {})[F] = spec
	conf = {"_about": "Outfit unit on the base_male_hi body; clips are our own poses (tools/pixellab/outfit_units.py). "
		"Idle is the standing pose; head swapping comes later.", "fps": 10, "frames_from": ff}
	json.dump(conf, open(os.path.join(out, "pixellab.json"), "w"), indent="\t")
	json.dump(rig_for(unit), open(os.path.join(out, "rig.json"), "w"), indent="\t")
	print(out, "clips", len(ff), "missing", missing or "none")


if __name__ == "__main__":
	for u in sys.argv[1:] or list(UNITS):
		package(u)
