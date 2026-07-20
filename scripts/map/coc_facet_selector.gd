class_name CocFacetSelector
extends RefCounted
## Camera-relative facet selection from the recovered engine quantizer.
##
## display_angle = (presentation_world - CameraDirection + 360) mod 360
## Map-data Direction is unchanged. Under CoC X-flip, exterior wall families get
## +180° for facet selection only (outward faces); interiors stay identity.

const LETTERS_4: PackedStringArray = ["e", "s", "w", "n"]
const LETTERS_8: PackedStringArray = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]


static func camera_degrees() -> int:
	## Same effective camera step as position remap (includes reverse-cam).
	return IsometricGrid.camera_direction_degrees()


static func presentation_world_for_family(family: String, world_direction_degrees: int) -> int:
	var world := MapCoordinateTransform.presentation_world_direction(world_direction_degrees)
	## Opposite face ≡ +180° (e↔w and s↔n). Only when X-flip is active — that is
	## what inverted exterior textured sides relative to OG.
	if (
		MapCoordinateTransform.uses_coc_x_flip()
		and CocRenderRules.uses_outward_face_remap(family)
	):
		world = posmod(world + 180, 360)
	return world


static func display_angle(world_direction_degrees: int, family: String = "") -> int:
	var world: int
	if family.is_empty():
		world = MapCoordinateTransform.presentation_world_direction(world_direction_degrees)
	else:
		world = presentation_world_for_family(family, world_direction_degrees)
	return posmod(world - camera_degrees(), 360)


static func slot_for_facets(display_angle_deg: int, facets: int) -> int:
	var angle := posmod(display_angle_deg, 360)
	match facets:
		1:
			return 0
		2:
			return int(((angle + 90) % 360) / 180)
		4:
			return int(((angle + 45) % 360) / 90)
		8:
			return int(((angle + 22) % 360) / 45)
		_:
			## Unknown facet counts: clamp to nearest supported quantizer.
			if facets > 4:
				return int(((angle + 22) % 360) / 45) % 8
			if facets > 1:
				return int(((angle + 45) % 360) / 90) % 4
			return 0


static func letter_for_slot(slot: int, facets: int) -> String:
	match facets:
		1:
			return "e"
		2:
			## Spec documents 4/8 letters; 2-facet families use opposite cardinals.
			return "e" if slot == 0 else "w"
		8:
			return LETTERS_8[posmod(slot, 8)]
		_:
			return LETTERS_4[posmod(slot, 4)]


static func select_letter(family: String, world_direction_degrees: int) -> String:
	return select_letter_at_camera(family, world_direction_degrees, camera_degrees())


static func select_letter_at_camera(
	family: String,
	world_direction_degrees: int,
	camera_direction_degrees: int,
) -> String:
	var facets := CocTileCatalog.facet_count(family)
	var world := presentation_world_for_family(family, world_direction_degrees)
	var angle := posmod(world - camera_direction_degrees, 360)
	var slot := slot_for_facets(angle, facets)
	return MapCoordinateTransform.reflect_facet_letter(letter_for_slot(slot, facets))


static func resolve_draw(family: String, world_direction_degrees: int, anim_frame: int = 0) -> Dictionary:
	return resolve_draw_at_camera(family, world_direction_degrees, camera_degrees(), anim_frame)


static func resolve_draw_at_camera(
	family: String,
	world_direction_degrees: int,
	camera_direction_degrees: int,
	anim_frame: int = 0,
) -> Dictionary:
	var letter := select_letter_at_camera(family, world_direction_degrees, camera_direction_degrees)
	var world := presentation_world_for_family(family, world_direction_degrees)
	var angle := posmod(world - camera_direction_degrees, 360)
	var resolved := CocTileCatalog.resolve(family, letter, anim_frame)
	if resolved.is_empty():
		return {
			"family": family.to_upper(),
			"letter": letter,
			"path": "",
			"hotspot": CocTileCatalog.DEFAULT_HOTSPOT,
			"missing": true,
			"display_angle": angle,
			"facet_count": CocTileCatalog.facet_count(family),
		}
	resolved["letter"] = letter
	resolved["missing"] = false
	resolved["display_angle"] = angle
	resolved["facet_count"] = CocTileCatalog.facet_count(family)
	return resolved
