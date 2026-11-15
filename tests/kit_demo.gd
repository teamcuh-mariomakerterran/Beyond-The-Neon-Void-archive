extends SceneTree
## Builds the kit street demo map (data/maps/kit_street_demo.json) with the
## auto-wall and auto-tile brushes, and takes screenshots of it.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 1920x1080 -s res://tests/kit_demo.gd -- <out_prefix> [build]
## "build" rewrites the map file first. Writes <out>_street.png, <out>_inside.png, <out>_inside2.png.


func _initialize() -> void:
	await process_frame
	var body: RefCounted = load("res://tests/kit_demo_body.gd").new()
	await body.run(self)
	quit()
