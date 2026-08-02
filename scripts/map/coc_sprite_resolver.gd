class_name CocSpriteResolver
extends RefCounted
## Single shared placement → sprite resolution for gameplay and the map editor.
##
## Callers supply family + world_direction (+ optional image1). Camera is presentation-only.
## Never persist the resolved path — redraw always re-resolves.
##
## Resolution:
## 1) relative_facet = quantize(presentation_world(family, Direction) - camera)
##    using CocFacetSelector's established handedness (incl. exterior +180°).
## 2) Look up camera_variants[relative_facet] in the Asset Registry.
## 3) If that variant has an explicit path, render it as an opaque asset id —
##    never inspect _e/_n/_w/_s suffixes or re-derive orientation from the filename.
## 4) Else fall back to CocFacetSelector + CocTileCatalog.
## 5) Always apply the selected variant's hotspot / render_offset / depth_offset.
##
## Asset Editor columns 0/90/180/270 author the four relative-facet textures.
## They are NOT absolute view-camera lookups.


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
	cam = posmod(cam, 360)
	var world_dir := posmod(world_direction_degrees, 360)

	var draw_info: Dictionary = {}
	if CocRenderRules.is_floor_family(fam):
		draw_info = CocRenderRules.resolve_floor_display(fam, world_dir)
	else:
		MapAssetRegistry.ensure_loaded()
		var relative := CocFacetSelector.relative_facet_degrees(fam, world_dir, cam)
		var variant := MapAssetRegistry.camera_variant(fam, relative)
		if _variant_has_explicit_path(variant):
			draw_info = _draw_from_opaque_path(fam, world_dir, cam, relative, variant)
		else:
			draw_info = CocFacetSelector.resolve_draw_at_camera(fam, world_dir, cam)
			draw_info = _apply_variant_presentation(draw_info, variant)
			draw_info["relative_facet"] = relative

	draw_info["family"] = fam
	draw_info["world_direction"] = world_dir
	draw_info["camera_direction"] = cam
	if not draw_info.has("relative_facet"):
		draw_info["relative_facet"] = CocFacetSelector.relative_facet_degrees(fam, world_dir, cam)
	draw_info["image1"] = image1.to_upper()
	draw_info["unusable"] = CocRenderRules.is_unusable_sprite(draw_info)

	var underlay := {}
	var img1 := image1.to_upper()
	if not img1.is_empty():
		underlay = CocRenderRules.resolve_floor_display(img1, world_dir)
		underlay["family"] = img1
	draw_info["image1_resolve"] = underlay
	return draw_info


static func resolve_preview(family: String, world_direction_degrees: int) -> Dictionary:
	return resolve_placement(family, world_direction_degrees, "", CocFacetSelector.camera_degrees())


## Runtime-matching preview at a view camera (uses relative facet for world_dir).
static func resolve_camera_preview(
	family: String,
	camera_direction_degrees: int,
	world_direction_degrees: int = 0,
) -> Dictionary:
	return resolve_placement(family, world_direction_degrees, "", camera_direction_degrees)


## Asset Editor column thumbnail — authored registry path for that variant key only.
static func resolve_authored_variant(family: String, variant_key_degrees: int) -> Dictionary:
	MapAssetRegistry.ensure_loaded()
	var fam := family.to_upper()
	var key := posmod(variant_key_degrees, 360)
	var variant := MapAssetRegistry.camera_variant(fam, key)
	if _variant_has_explicit_path(variant):
		return _draw_from_opaque_path(fam, 0, key, key, variant)
	return {
		"family": fam,
		"path": "",
		"relative_facet": key,
		"camera_direction": key,
		"world_direction": 0,
		"missing": true,
	}


static func _variant_has_explicit_path(variant: Dictionary) -> bool:
	if variant.is_empty() or bool(variant.get("fallback", false)):
		return false
	return _path_exists(_registry_path_to_res(str(variant.get("path", ""))))


## Path is an opaque asset id. Letter/facet fields are inspector metadata only —
## never parsed from the filename, never used to re-pick orientation.
static func _draw_from_opaque_path(
	family: String,
	world_direction_degrees: int,
	camera_direction_degrees: int,
	relative_facet_degrees: int,
	variant: Dictionary,
) -> Dictionary:
	var path := _registry_path_to_res(str(variant.get("path", "")))
	var letter := str(variant.get("letter", "")).to_lower()
	var override_fam := str(variant.get("source_family", "")).to_upper()
	var facet := str(variant.get("facet", ""))
	if override_fam.is_empty():
		override_fam = family.to_upper()
	if letter.is_empty():
		letter = "?"
	var draw_info := {
		"family": family.to_upper(),
		"path": path,
		"letter": letter,
		"source_family": override_fam,
		"facet": facet,
		"registry_override": true,
		"relative_facet": relative_facet_degrees,
		"missing": not _path_exists(path),
		"display_angle": CocFacetSelector.display_angle_at_camera(
			family, world_direction_degrees, camera_direction_degrees
		),
		"facet_count": CocTileCatalog.facet_count(family),
		"world_direction": world_direction_degrees,
		"camera_direction": camera_direction_degrees,
	}
	return _apply_variant_presentation(draw_info, variant)


static func _apply_variant_presentation(
	draw_info: Dictionary,
	variant: Dictionary,
	hotspot_fallback: Variant = null,
) -> Dictionary:
	if draw_info.is_empty() or variant.is_empty():
		return draw_info
	var hs: Variant = variant.get("hotspot", hotspot_fallback)
	if hs is Array and (hs as Array).size() >= 2:
		draw_info["hotspot"] = Vector2(float(hs[0]), float(hs[1]))
	elif hs is Vector2:
		draw_info["hotspot"] = hs
	elif not draw_info.has("hotspot"):
		draw_info["hotspot"] = CocTileCatalog.DEFAULT_HOTSPOT

	var ro: Variant = variant.get("render_offset", null)
	if ro is Array and (ro as Array).size() >= 2:
		draw_info["render_offset"] = Vector2(float(ro[0]), float(ro[1]))
	elif ro is Vector2:
		draw_info["render_offset"] = ro
	elif not draw_info.has("render_offset"):
		draw_info["render_offset"] = Vector2.ZERO

	if variant.has("depth_offset"):
		draw_info["depth_offset"] = float(variant.get("depth_offset", 0.0))
	elif not draw_info.has("depth_offset"):
		draw_info["depth_offset"] = 0.0
	return draw_info


static func _path_exists(path: String) -> bool:
	if path.is_empty():
		return false
	return CocTileCatalog.exists(path) or ResourceLoader.exists(path) or FileAccess.file_exists(path)


static func _registry_path_to_res(path: String) -> String:
	var p := path.strip_edges().replace("\\", "/")
	if p.is_empty():
		return ""
	if p.begins_with("res://"):
		return p
	if p.begins_with("assets/"):
		return "res://%s" % p
	if p.begins_with("sprites/"):
		return "res://assets/%s" % p
	return "res://assets/sprites/coc_tiles/%s" % p.get_file()
