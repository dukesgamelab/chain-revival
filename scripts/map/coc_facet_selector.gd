class_name CocFacetSelector
extends RefCounted
## Camera-relative facet selection from the recovered engine quantizer.
##
## display_angle = (Direction - CameraDirection + 360) mod 360
## World Direction stays in map data; camera is presentation-only.

const LETTERS_4: PackedStringArray = ["e", "s", "w", "n"]
const LETTERS_8: PackedStringArray = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]


static func camera_degrees() -> int:
	## Matches IsometricGrid view rotation steps (0/90/180/270 clockwise).
	return posmod(IsometricGrid.current_view_rotation, 4) * 90


static func display_angle(world_direction_degrees: int) -> int:
	return posmod(world_direction_degrees - camera_degrees(), 360)


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
	var angle := posmod(world_direction_degrees - camera_direction_degrees, 360)
	var slot := slot_for_facets(angle, facets)
	return letter_for_slot(slot, facets)


static func resolve_draw(family: String, world_direction_degrees: int, anim_frame: int = 0) -> Dictionary:
	return resolve_draw_at_camera(family, world_direction_degrees, camera_degrees(), anim_frame)


static func resolve_draw_at_camera(
	family: String,
	world_direction_degrees: int,
	camera_direction_degrees: int,
	anim_frame: int = 0,
) -> Dictionary:
	var letter := select_letter_at_camera(family, world_direction_degrees, camera_direction_degrees)
	var resolved := CocTileCatalog.resolve(family, letter, anim_frame)
	if resolved.is_empty():
		return {
			"family": family.to_upper(),
			"letter": letter,
			"path": "",
			"hotspot": CocTileCatalog.DEFAULT_HOTSPOT,
			"missing": true,
			"display_angle": posmod(world_direction_degrees - camera_direction_degrees, 360),
			"facet_count": CocTileCatalog.facet_count(family),
		}
	resolved["letter"] = letter
	resolved["missing"] = false
	resolved["display_angle"] = posmod(world_direction_degrees - camera_direction_degrees, 360)
	resolved["facet_count"] = CocTileCatalog.facet_count(family)
	return resolved
