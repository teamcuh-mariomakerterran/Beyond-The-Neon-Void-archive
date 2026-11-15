"""Stage an art drop into the game repo. COPY ONLY: the source is only read.

    py -3 tools/art/stage_art.py "E:\\assets for the neon void"

The sorting lists below were written for the 2026-11-15 drop; a new drop needs
its sheets added to AUTO / TM_PROPS / OBJ_RULES (an object no rule matches stops
the run). Afterwards: tools/cut_art_halo.bat (props), tools/art/cut_tiles.gd on
assets/incoming/tiles.tsv (tiles, then tests/scan_tiles.gd), tools/kit_height.bat
on tools/handoff/kits (add _hN to each kit name).

Writes:
  assets/incoming/rooms_props/<type>/<name>.png   object sheets (cut later by tools/cut_art_halo.bat)
  assets/incoming/tiles.tsv                        plain tile sheets -> set name (cut by tools/art/cut_tiles.gd)
  tools/handoff/autotiles/<name>.png               auto-tile (transition) sheets
  tools/handoff/kits/<name>.png + <name>.kit.json  building-kit sheets (height suffix added later)
"""
import json, os, re, shutil, sys, zipfile

SRC = sys.argv[1] if len(sys.argv) > 1 else r"E:\assets for the neon void"
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SCRATCH = os.path.join(REPO, "assets", "incoming")  # tiles.tsv + stage_log.tsv (not committed)
TM = os.path.join(SRC, "tilemaps")
OBJ = os.path.join(SRC, "objects", "static objects_enviroment objects")
DIG = os.path.join(SRC, "objects", "digimancer tech objects", "digital_god_objects", "objects")


def slug(name: str, cap: int = 64) -> str:
    base, n = name, ""
    m = re.match(r"^(.*?)\s*\((\d+)\)$", base)
    if m:
        base, n = m.group(1), str(int(m.group(2)) + 1)
    s = re.sub(r"[^a-z0-9]+", "_", base.lower()).strip("_")
    s = re.sub(r"_+", "_", s)[:cap].strip("_")
    return s + ("_v" + n if n else "")


AUTO = {
    "Concrete_to_mossy_green_slime.png", "Dark_grey_diamond-plate_steel_flooring_to_polished.png",
    "ancient_sandstone_to_sand.png", "cyberpunk_cement_sidewalk_to_asphalt_street.png",
    "cyberpunk_concrete_to_asphalt_road.png", "cyberpunk_server_room_grating_to_polished_block_ma.png",
    "polished_tile_with_circuitry_to_cement_sidewalk.png", "rocky_foothills_to_dense_forest_completely_filled.png",
    "scrap_metal_plating_to_dark_ocean_water (1).png", "scrap_metal_plating_to_dark_ocean_water.png",
}

# Tilemap sheets that are objects (whole buildings, crates, machines), by prop type.
TM_PROPS = {
    "street_cover": ["Cyberpunk_Slums_Alleyway_1_jury-rigged_barricades.png", "Cyberpunk_Slums_Alleyway_Props_-_tactical_cover_an.png",
                     "cyberpunk_slums_1_concrete_wall_2_concrete_wall.png"],
    "warehouse": ["Cyberpunk_Warehouse_Logistics_Props_-_industrial.png", "Cyberpunk_Warehouse_Logistics_Props_1_heavy_pla.png",
                  "Industrial_Shipping_Containers.png"],
    "hacking": ["Hacking_Nodes_1_Mainframe_Terminal_Console_2_Jur (1).png", "cyberpunk_hacking_nodes.png"],
    "industrial": ["Massive_truss_framework_supporting_giant_industria (1).png", "Massive_truss_framework_supporting_giant_industria.png",
                   "Modular_Scaffolding_Blocks.png", "cyberpunk_factory_assets (1).png", "cyberpunk_factory_assets.png"],
    "junk": ["Outside_Cyberpunk_Slums_1_scrap_metal_plating_2_ (1).png", "Outside_Cyberpunk_Slums_1_scrap_metal_plating_2_ (2).png",
             "Outside_Cyberpunk_Slums_1_scrap_metal_plating_2_.png", "cyberpunk_junkyard (1).png",
             "cyberpunk_orbital_junkyard_1_Torn_and_shattered_s.png"],
    "server": ["cyberpunk_enviroments_1_Server_Stack_Server_Rack.png"],
    "bar": ["cyberpunk_slums_bar_1_bar_with_beer_bottles_layin.png", "cyberpunk_slums_bar_1_stack_of_empty_kegs_2_beer.png"],
    "rooms": ["cyberpunk_living_quarters.png", "cyberpunk_offices.png"],
}
FACADE_WORDS = ["facade", "cyberpunk_environment", "redlight_district", "head_quarters", "tech_facility", "tech_labs",
                "research_lab", "cyberpunk_library", "mainframe_server_room", "secret_hideout", "cyberpunk_industrial"]

# Object folder: keyword in the (lower-case) file name -> prop type. First hit wins.
OBJ_RULES = [
    ("items", ["bar_drinks", "hologram_t", "potions_an", "street_tra", "vendor_ite"]),
    ("digimancer", ["a_cyberpunk_ancient", "digimancer"]),
    ("arcade", ["arcade"]),
    ("bar", ["bar-", "ramen", "cafe", "high-top"]),
    ("library", ["digital-lib"]),
    ("shops", ["store", "armor-ven", "weapon-ve", "pawn-shop", "armory", "skill-tra", "save-poin"]),
    ("server", ["mainframe", "server-ro"]),
    ("shelving", ["shelving"]),
    ("computers", ["computer"]),
    ("office", ["office", "desks", "table-vie", "single-fa"]),
    ("lab", ["lab-machi", "research", "assembly", "factory-m", "construct"]),
    ("home", ["apartment", "livingroom", "furniture", "lamps"]),
    ("plants", ["plants", "bushes"]),
    ("warehouse", ["warehouse", "crates"]),
    ("junk", ["junkpile"]),
    ("street", ["street", "slums-pro", "city-prop", "battle-location", "secret-hi", "cement", "indoor"]),
]


def obj_name(f: str) -> str:
    b = os.path.splitext(f)[0]
    b = re.sub(r"^pixellab-", "", b)
    b = re.sub(r"-\d{10,}$", "", b)  # pixellab timestamp
    b = re.sub(r"\.\.\.-\d+-\d+", "", b)  # "...-1112845510-0"
    return slug(b, 64)


def copy(src: str, dst: str, log: list) -> None:
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    stem, ext = os.path.splitext(dst)
    k = 2
    while os.path.exists(dst):  # PixelLab takes of one prompt share a name: number them
        dst = "%s_%d%s" % (stem, k, ext)
        k += 1
    shutil.copy2(src, dst)
    log.append((src, dst))


def main() -> None:
    log: list = []
    incoming = os.path.join(REPO, "assets", "incoming", "rooms_props")
    tiles_tsv = []
    tm_prop = {f: t for t, fs in TM_PROPS.items() for f in fs}
    for f in sorted(os.listdir(TM)):
        p = os.path.join(TM, f)
        if not f.lower().endswith(".png"):
            continue
        if f in AUTO:
            copy(p, os.path.join(REPO, "tools", "handoff", "autotiles", slug(os.path.splitext(f)[0]) + ".png"), log)
        elif f in tm_prop or any(w in f.lower() for w in FACADE_WORDS):
            t = tm_prop.get(f, "facades")
            copy(p, os.path.join(incoming, t, slug(os.path.splitext(f)[0]) + ".png"), log)
        else:
            tiles_tsv.append(p + "\t" + slug(os.path.splitext(f)[0], 64))
    for f in sorted(os.listdir(OBJ)):
        if not f.lower().endswith(".png"):
            continue
        low = f.lower()
        t = next((t for t, ws in OBJ_RULES if any(w in low for w in ws)), None)
        if t is None:
            raise SystemExit("unsorted object: " + f)
        copy(os.path.join(OBJ, f), os.path.join(incoming, t, obj_name(f) + ".png"), log)
    # Digimancer tech objects (reactor core.png only: its Layer 1 / _strip copies are the same art).
    for f, n in [("Object_digital_sarcophagus.png", "digital_sarcophagus"), ("object_teleporter.png", "teleporter"),
                 ("object_teleporter_alter_control_interface.png", "teleporter_altar_control_interface"),
                 ("reactor core.png", "reactor_core"), ("structure 132_strip.png", "structure_132"),
                 ("structure 32_strip.png", "structure_32"), ("a_cyberpunk_ancient_...-788964062-0 (3).png", "a_cyberpunk_ancient_v4"),
                 ("a_large_cyberpunk_fa...-1859865504-0.png", "a_large_cyberpunk_fa")]:
        copy(os.path.join(DIG, f), os.path.join(incoming, "digimancer", n + ".png"), log)
    copy(os.path.join(SRC, "boss units and structures", "structures", "sprite_strip.png"),
         os.path.join(incoming, "boss_structures", "boss_structure.png"), log)
    copy(os.path.join(SRC, "signs", "sign_023.png"), os.path.join(incoming, "signs", "sign_023.png"), log)
    wm = os.path.join(SRC, "world map structures_locations")
    copy(os.path.join(wm, "world map location_the great altar tree.png"), os.path.join(incoming, "world_map_locations", "great_altar_tree.png"), log)
    copy(os.path.join(wm, "world map location_the great altar tree_post_destruction.png"),
         os.path.join(incoming, "world_map_locations", "great_altar_tree_post_destruction.png"), log)
    with zipfile.ZipFile(os.path.join(wm, "world_map_location_floating_temple-spritesheet.zip")) as zf:
        dst = os.path.join(incoming, "world_map_locations", "floating_temple.png")
        with open(dst, "wb") as fh:
            fh.write(zf.read("world_map_location_floating_temple.png"))
        log.append((wm + "!floating_temple", dst))
    # Building kits: the zip's full sheet + its kit.json (piece names in sheet order).
    for z in sorted(os.listdir(TM)):
        if not z.endswith(".zip"):
            continue
        with zipfile.ZipFile(os.path.join(TM, z)) as zf:
            names = zf.namelist()
            kit = next(n for n in names if n.endswith("kit.json"))
            root = kit.rsplit("/", 1)[0]
            sheet = root + "/" + root.split("/")[-1] + ".png"
            name = slug(os.path.splitext(z)[0], 44)
            dst = os.path.join(REPO, "tools", "handoff", "kits", name + ".png")
            if os.path.exists(dst):
                raise SystemExit("name clash: " + dst)
            with open(dst, "wb") as fh:
                fh.write(zf.read(sheet))
            with open(dst[:-4] + ".kit.json", "wb") as fh:
                fh.write(zf.read(kit))
            log.append((os.path.join(TM, z) + "!" + sheet, dst))
    with open(os.path.join(SCRATCH, "tiles.tsv"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(tiles_tsv) + "\n")
    with open(os.path.join(SCRATCH, "stage_log.tsv"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(a + "\t" + b for a, b in log) + "\n")
    print("copied", len(log), "files;", len(tiles_tsv), "tile sheets queued")


if __name__ == "__main__":
    main()
