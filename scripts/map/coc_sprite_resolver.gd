class_name CocSpriteResolver
extends RefCounted
## Single shared placement → sprite resolution for gameplay and the map editor.
##
## Callers supply family + world_direction (+ optional image1). Camera is presentation-only.
## Never persist the resolved path/letter — redraw always re-resolves.
##
## Default: CocFacetSelector (family + world direction + facet camera 0/90/180/270).
## Cross-family MapAssetRegistry camera_variants (source_family / foreign path) override the
## texture for that camera — Asset Editor irregular corner mappings must reach the map view.
## Same-family variant paths (e/n/w/s of the placement family) do NOT override; world
## direction still drives the facet letter.


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
		draw_info = _apply_authored_camera_variant(draw_info, fam, cam)

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


## Honor Asset Editor cross-family camera_variants (e.g. IWCR@0 → IWCRS3A_e).
static func _apply_authored_camera_variant(
	draw_info: Dictionary,
	family: String,
	camera_direction_degrees: int,
) -> Dictionary:
	if draw_info.is_empty():
		return draw_info
	MapAssetRegistry.ensure_loaded()
	var variant := MapAssetRegistry.camera_variant(family, camera_direction_degrees)
	if variant.is_empty():
		return draw_info

	var letter := str(variant.get("letter", "e")).to_lower()
	var override_fam := str(variant.get("source_family", "")).to_upper()
	var facet := str(variant.get("facet", ""))
	if override_fam.is_empty() and not facet.is_empty():
		var us := facet.rfind("_")
		if us > 0:
			override_fam = facet.substr(0, us).to_upper()
			letter = facet.substr(us + 1).to_lower()

	## Same-family variants are documentation / hotspot authoring only.
	if override_fam.is_empty() or override_fam == family.to_upper():
		return draw_info

	var resolved := CocTileCatalog.resolve(override_fam, letter)
	if resolved.is_empty():
		var abs_path := _registry_path_to_res(str(variant.get("path", "")))
		if abs_path.is_empty() or not CocTileCatalog.exists(abs_path):
			return draw_info
		resolved = {
			"path": abs_path,
			"letter": letter,
			"family": override_fam,
			"hotspot": CocTileCatalog.DEFAULT_HOTSPOT,
		}

	draw_info["path"] = str(resolved.get("path", ""))
	draw_info["letter"] = letter
	draw_info["source_family"] = override_fam
	draw_info["facet"] = "%s_%s" % [override_fam, letter]
	draw_info["registry_override"] = true
	draw_info["missing"] = draw_info["path"].is_empty()
	var hs: Variant = variant.get("hotspot", resolved.get("hotspot", null))
	if hs is Array and (hs as Array).size() >= 2:
		draw_info["hotspot"] = Vector2(float(hs[0]), float(hs[1]))
	elif hs is Vector2:
		draw_info["hotspot"] = hs
	elif resolved.has("hotspot"):
		draw_info["hotspot"] = resolved.get("hotspot")
	return draw_info


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
