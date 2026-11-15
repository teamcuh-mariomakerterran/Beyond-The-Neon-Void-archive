Building-kit sheets for the auto-wall system (not used by the game directly; tools/ is Godot-ignored).

hazard_kit_h1.png  Brian's hazard-stripe kit, 64 px art, wall height 1 (measured against its stair piece with tools/kit_height.bat).
  1-2 floor / flat roof, 3-40 walls (edges, corners, T, cross, posts, roof caps), 41-46 doorways, 47-50 stairs and ramps, 51-70 sloped roofs and berms.
  Cut it with tools/cut_art.bat (pieces come out in that reading order).

2026-11-15 drop (E:\assets for the neon void\tilemaps\*.zip, 37 kits): each zip's full sheet as <name>_hN.png
plus <name>_hN.kit.json (the zip's piece list: index, name such as wall_N / corner_SE / door_Na / stairs_low /
roof_hip_NE, in the sheet's reading order). 64 px art, 80 pieces (00 floor ... 79 roof_flat).
N = wall height from tools/kit_height.bat (the tallest wall measured against the stair piece's rise).
Note: most "towering"/"triple-height" kits measure h1 because their stair piece rises as tall as their walls
(stair 99 px = wall 99 px), so the yardstick reads them as one storey; their walls really are ~3x a 35 px storey.
Worth a look before the auto-wall system trusts those suffixes. The zips themselves are not in the repo.
