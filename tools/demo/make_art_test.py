"""Test map for the 2026-11-15 art drop (new tiles + cut props), not part of the campaign.

Writes data/maps/art_drop_test.json: a rainy 16x16 block that shows the new tile sets
side by side (asphalt road, sidewalks, a dive-bar floor, a server room, park, desert,
water, forest, mountains) and the new props standing on them (facades along the back,
bar, server racks, arcade, plants, warehouse crates and containers, digimancer tech).
Run from the repo root: py -3 tools/demo/make_art_test.py
"""
import json
import os
import random

random.seed(11)
W = D = 16
TILES = "assets/tiles"
PROPS = "assets/props"


def tset(name):
    """Tile ids of one cut set, in order (ids are the path under assets/tiles, no extension)."""
    files = sorted(f for f in os.listdir(os.path.join(TILES, name)) if f.endswith(".png"))
    return [name + "/" + f[:-4] for f in files]


def props(folder, *prefixes):
    files = sorted(f for f in os.listdir(os.path.join(PROPS, folder)) if f.endswith(".png"))
    if prefixes:
        files = [f for f in files if f.startswith(prefixes)]
    return ["res://" + PROPS + "/" + folder + "/" + f for f in files]


road = tset("dark_asphalt_1_plain_asphalt_2_worn_3_wet_4_ye")[:6]
walk = tset("concrete_side_walk_1_flat_concrete_section_2_cur")
bar_floor = tset("wooden_old_dive_bar_flooring_v3")[:8]
server_floor = tset("metal_server_room_flooring_v3")
park = tset("grasslands") + tset("digital_flower_fields")[:4]
desert = tset("dark_crimson_sand_floor_scattered_with_small_volca_v4")[:6]
water = tset("dark_ocean_water")
forest = tset("dense_forest_completely_filled_with_trees")
rock = tset("ancient_mountains")
plates = tset("heavy_duty_grey_diamond_plate_steel_flooring_paint")

tiles = {}


def put(x, y, tile, z=0):
    tiles[f"{x},{y}"] = [[z, tile]]


for x in range(W):
    for y in range(D):
        if x in (7, 8):
            put(x, y, random.choice(road))
        elif y == 9:
            put(x, y, random.choice(road))
        elif x in (6, 9) or y in (8, 10):
            put(x, y, random.choice(walk))
        elif x < 6 and 1 <= y < 8:
            put(x, y, random.choice(bar_floor))
        elif x > 9 and 1 <= y < 8:
            put(x, y, random.choice(server_floor))
        elif x < 3 and y > 10:
            put(x, y, random.choice(forest))
        elif x < 6 and y > 10:
            put(x, y, random.choice(park))
        elif x > 12 and y > 12:
            put(x, y, random.choice(water))
        elif x > 9 and y > 10:
            put(x, y, random.choice(desert if y < 13 else plates))
        else:
            put(x, y, random.choice(walk))
for x in range(W):
    put(x, 0, random.choice(plates))
put(0, 15, rock[0], 0)
put(1, 15, rock[1], 0)

objects = []


def obj(asset, x, y, kind="prop", scale=1.0, flip=False):
    objects.append({"id": f"obj_art_drop_test_{len(objects) + 1}", "asset": asset, "cell": [x, y], "z": 0,
                    "offset": [0, 0], "scale": scale, "flip": flip, "layer": 0, "kind": kind, "anim": None,
                    "loot_item_id": "", "found_text": "", "empty_text": "", "dialog_npc": "", "location": None})


# Back row: building facades (one cube per tile).
facades = props("facades", "cyberpunk_environment_1_storefront", "cyberpunk_redlight", "cyberpunk_store_facade")
for x, f in zip(range(W), random.sample(facades, W)):
    if x not in (7, 8):
        obj(f, x, 0, "structure")
# Dive bar (west block).
bar = props("bar", "a_high_top", "a_cyberpunk_bar_chair", "cyberpunk_futuristic_bar_props")
for (x, y), f in zip([(1, 2), (3, 2), (1, 4), (3, 4), (5, 2), (2, 6), (4, 6), (5, 5)], random.sample(bar, 8)):
    obj(f, x, y)
# Server room (east block).
server = props("server", "cyberpunk_futuristic_server_ro", "cyberpunk_futuristic_mainframe")
for (x, y), f in zip([(10, 2), (11, 2), (12, 2), (14, 2), (10, 5), (12, 5), (14, 5), (15, 4)], random.sample(server, 8)):
    obj(f, x, y)
obj(props("arcade")[4], 15, 7)
obj(props("arcade")[7], 13, 7)
# Plaza: digimancer tech at the crossroads corner.
dig = props("digimancer")
obj([d for d in dig if d.endswith("teleporter.png")][0], 6, 11, "structure", 0.5)
obj([d for d in dig if d.endswith("reactor_core.png")][0], 9, 11, "structure", 0.5)
# Park plants and forest edge.
for (x, y), f in zip([(3, 11), (4, 12), (5, 13), (3, 14), (5, 15)], random.sample(props("plants"), 5)):
    obj(f, x, y)
# Warehouse yard (south-east): crates, containers, barrels.
ware = props("warehouse", "industrial_shipping") + props("street_cover") + props("warehouse", "cyberpunk_warehouse")
for (x, y), f in zip([(10, 11), (11, 12), (12, 11), (10, 14), (11, 15), (12, 14)], random.sample(ware, 6)):
    obj(f, x, y)
# Street clutter on the sidewalks.
street = props("street", "cyberpunk_futuristic_street_pr", "cyberpunk_futuristic_slums_pro")
for (x, y), f in zip([(6, 2), (9, 3), (6, 6), (9, 6), (2, 10), (13, 10)], random.sample(street, 6)):
    obj(f, x, y)

particles = {f"{x},{y}": [[6, "neon_rain"]] for x in range(W) for y in range(D) if (x + y) % 2 == 0}
gameplay = {}
for o in objects:
    gameplay["%d,%d" % tuple(o["cell"])] = {"walkable": False, "cover": 1}
for x in range(13, W):
    for y in range(13, D):
        gameplay[f"{x},{y}"] = {"walkable": False}

m = {"format": 2, "id": "art_drop_test", "name": "Art Drop Test (2026-11-15)", "kind": "city",
     "width": W, "depth": D, "tile_width": 128, "tile_height": 64, "height_step": 32,
     "ambient": "#7a72b8", "post": "neon_noir", "tiles": tiles, "details": [], "particles": particles,
     "objects": objects, "spawns": {"player": [[7, 15]], "enemy": []}, "gameplay": gameplay, "anchors": []}
with open("data/maps/art_drop_test.json", "w", encoding="utf-8", newline="\n") as fh:
    json.dump(m, fh, indent="\t", ensure_ascii=False)
    fh.write("\n")
print("art_drop_test: %d tiles, %d objects" % (len(tiles), len(objects)))
