class_name CocSpriteResolver
extends RefCounted
## Single shared placement → sprite resolution for gameplay and the map editor.
##
## Callers supply family + world_direction (+ optional image1). Camera is presentation-only.
## Never persist the resolved path/letter — redraw always re-resolves.
##
## MapAssetRegistry camera_variants are editor authoring data (hotspot/offset/depth);
## runtime facet pick stays CocFacetSelector (family + world direction + facet camera).
## Facet camera degrees are the normal 0/90/180/270 sequence (not coord-remap reverse).
## Do not bypass facet resolution with camera-only registry sprites — that ignores
## placement direction and breaks walls/corners on load.


static func resolve_placement(
	family: String,
	world_direction_degrees: int,
	image1: String = "",
	camera_direction_degrees: int = -1,
) -> Dictionary:
	var fam := family.to_upper()
	var cam := camera_direction_degrees
	if cam < 0:
		cam = CocFacetSelector.camera_degrees()

	var draw_info: Dictionary = {}
	if CocRenderRules.is_floor_family(fam):
		draw_info = CocRenderRules.resolve_floor_display(fam, world_direction_degrees)
		## Footage floor mapping ignores camera; still record camera for inspector/debug.
		draw_info["camera_direction"] = cam
		draw_info["world_direction"] = world_direction_degrees
	else:
		draw_info = CocFacetSelector.resolve_draw_at_camera(fam, world_direction_degrees, cam)

	draw_info["family"] = fam
	draw_info["world_direction"] = world_direction_degrees
	draw_info["camera_direction"] = cam
	draw_info["image1"] = image1.to_upper()
	draw_info["unusable"] = CocRenderRules.is_unusable_sprite(draw_info)

	## Optional Image1 underlay resolve (same rules as OriginalUnderlayLayer).
	var underlay := {}
	var img1 := image1.to_upper()
	if not img1.is_empty():
		underlay = CocRenderRules.resolve_floor_display(img1, world_direction_degrees)
		underlay["family"] = img1
	draw_info["image1_resolve"] = underlay
	return draw_info


## Browser / ghost helpers — always current camera.
static func resolve_preview(family: String, world_direction_degrees: int) -> Dictionary:
	return resolve_placement(family, world_direction_degrees, "", CocFacetSelector.camera_degrees())
