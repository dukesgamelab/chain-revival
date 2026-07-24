class_name CocSpriteResolver
extends RefCounted
## Single shared placement → sprite resolution for gameplay and the map editor.
##
## Callers supply family + world_direction (+ optional image1). Camera is presentation-only.
## Authored MapAssetRegistry camera_variants override auto facet pick per camera angle.
## Never persist the resolved path/letter — redraw always re-resolves.

const MapAssetRegistryClass := preload("res://scripts/map/map_asset_registry.gd")


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
	cam = _snap_camera_degrees(cam)

	var draw_info: Dictionary = {}
	if CocRenderRules.is_floor_family(fam):
		draw_info = CocRenderRules.resolve_floor_display(fam, world_direction_degrees)
		## Footage floor mapping ignores camera; still record camera for inspector/debug.
		draw_info["camera_direction"] = cam
		draw_info["world_direction"] = world_direction_degrees
	else:
		## Prefer per-camera authored sprite from the map asset registry.
		draw_info = _resolve_registry_camera_variant(fam, cam)
		if draw_info.is_empty():
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


static func _snap_camera_degrees(camera_direction_degrees: int) -> int:
	var cam := posmod(camera_direction_degrees, 360)
	## Registry keys are 0/90/180/270.
	return int(round(float(cam) / 90.0)) * 90 % 360


static func _resolve_registry_camera_variant(family: String, camera_deg: int) -> Dictionary:
	if not MapAssetRegistryClass.has_family(family):
		return {}
	var variant := MapAssetRegistryClass.camera_variant(family, camera_deg)
	if variant.is_empty():
		return {}
	var letter := str(variant.get("letter", "")).to_lower()
	var facet := str(variant.get("facet", ""))
	var src_fam := str(variant.get("source_family", "")).to_upper()
	if src_fam.is_empty() and facet.contains("_"):
		src_fam = facet.get_slice("_", 0).to_upper()
	if src_fam.is_empty():
		src_fam = family
	if letter.is_empty() and facet.contains("_"):
		letter = facet.get_slice("_", 1).to_lower()
	if letter.is_empty():
		return {}

	var resolved := CocTileCatalog.resolve(src_fam, letter, 0)
	var path := str(variant.get("path", ""))
	if not path.is_empty():
		if not path.begins_with("res://"):
			path = "res://assets/%s" % path if not path.begins_with("assets/") else "res://%s" % path
	if resolved.is_empty():
		if path.is_empty() or not CocTileCatalog.exists(path):
			return {}
		resolved = {
			"family": src_fam,
			"letter": letter,
			"path": path,
			"hotspot": CocTileCatalog.DEFAULT_HOTSPOT,
			"missing": false,
		}
	else:
		## Authored path wins when present and loadable.
		if not path.is_empty() and CocTileCatalog.exists(path):
			resolved["path"] = path
		resolved["missing"] = false

	var hs: Variant = variant.get("hotspot", null)
	if hs is Array and (hs as Array).size() >= 2:
		resolved["hotspot"] = Vector2(float(hs[0]), float(hs[1]))
	elif hs is Vector2:
		resolved["hotspot"] = hs

	var ro: Variant = variant.get("render_offset", [0, 0])
	if ro is Array and (ro as Array).size() >= 2:
		resolved["render_offset"] = Vector2(float(ro[0]), float(ro[1]))
	else:
		resolved["render_offset"] = Vector2.ZERO
	resolved["depth_offset"] = int(variant.get("depth_offset", 0))
	resolved["letter"] = letter
	resolved["facet"] = facet if not facet.is_empty() else "%s_%s" % [src_fam, letter]
	resolved["source_family"] = src_fam
	resolved["from_registry"] = true
	resolved["display_angle"] = camera_deg
	resolved["facet_count"] = CocTileCatalog.facet_count(src_fam)
	return resolved
