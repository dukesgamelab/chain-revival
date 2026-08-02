class_name MapCoordinateTransform
extends RefCounted
## Single authoritative presentation transform for CoC maps.
##
## Logical map coordinates and world directions are never mutated in map data.
## Presentation only:
##   1) CoC X-flip: (x,y) → (width-1-x, y)
##   2) camera remap with reversed step order 0,3,2,1 (OG rotate spin)
##   3) isometric project: screen = (vx-vy)·31·s, (vx+vy)·16·s
##   4) facets: display_angle = (world - facet_camera) mod 360
##      Facet camera matches coordinate-remap reversed steps [0,3,2,1]
##      (see IsometricGrid.facet_camera_direction_degrees()).
##      World Direction in map data is unchanged by camera / X-flip.
##      Exterior walls get a selective +180° in CocFacetSelector only
##      (see CocRenderRules.EXTERIOR_OUTWARD_FACE_FAMILIES). Interiors stay identity.
##
## Confirmed vs OG Fortress screenshots:
##   - X-flip restores Woods-left / Hay-right at camera 0°
##   - Reversed camera steps match OG rotate spin
##   - Global +180° on all facets breaks interiors (IWWL dir0@cam0 → w).

enum Candidate {
	CURRENT, ## Authoritative: X-flip + reversed cam steps
	LEGACY_NO_FLIP, ## Pre-fix: no X-flip, CW steps 0,1,2,3
	XFLIP_ONLY, ## X-flip but CW steps (old mistaken bake)
	REFLECT_H, ## screen_x=(y-x)·31
	SWAP_XY, ## project(y,x)
	FLIP_Y, ## (x, h-1-y)
	REFLECT_DIR, ## NE↔SE, NW↔SW after facet select
}

const CANDIDATE_NAMES: PackedStringArray = [
	"A_CURRENT",
	"B_LEGACY_NO_FLIP",
	"C_XFLIP_ONLY",
	"D_REFLECT_H",
	"E_SWAP_XY",
	"F_FLIP_Y",
	"G_REFLECT_DIR",
]

static var active_candidate: int = Candidate.CURRENT


static func candidate_name() -> String:
	var i := posmod(active_candidate, CANDIDATE_NAMES.size())
	return CANDIDATE_NAMES[i]


static func cycle_candidate() -> String:
	active_candidate = posmod(active_candidate + 1, CANDIDATE_NAMES.size())
	return candidate_name()


static func reset_candidate() -> void:
	active_candidate = Candidate.CURRENT


static func uses_reversed_camera() -> bool:
	match active_candidate:
		Candidate.CURRENT, Candidate.REFLECT_H, Candidate.REFLECT_DIR:
			return true
		Candidate.LEGACY_NO_FLIP, Candidate.XFLIP_ONLY, Candidate.SWAP_XY, Candidate.FLIP_Y:
			return false
		_:
			return true


static func uses_coc_x_flip() -> bool:
	match active_candidate:
		Candidate.LEGACY_NO_FLIP, Candidate.SWAP_XY, Candidate.FLIP_Y:
			return false
		Candidate.CURRENT, Candidate.XFLIP_ONLY, Candidate.REFLECT_H, Candidate.REFLECT_DIR:
			return IsometricGrid.use_original_projection
		_:
			return IsometricGrid.use_original_projection


static func camera_step_for_rotation(rotation_index: int) -> int:
	var step := posmod(rotation_index, 4)
	if uses_reversed_camera():
		## Spec caveat: negate camera step when spin is opposite OG.
		return [0, 3, 2, 1][step]
	return step


static func preprocess_logical_cell(cell: Vector2i, map_width: int, map_height: int) -> Vector2i:
	match active_candidate:
		Candidate.SWAP_XY:
			return Vector2i(cell.y, cell.x)
		Candidate.FLIP_Y:
			return Vector2i(cell.x, map_height - 1 - cell.y)
		_:
			if uses_coc_x_flip() and map_width > 0:
				return Vector2i(map_width - 1 - cell.x, cell.y)
			return cell


static func inverse_preprocess_logical_cell(
	cell: Vector2i,
	map_width: int,
	map_height: int,
) -> Vector2i:
	## X-flip / swap / Y-flip are involutions.
	return preprocess_logical_cell(cell, map_width, map_height)


static func project_visual_point(point: Vector2) -> Vector2:
	var x := point.x
	var y := point.y
	if active_candidate == Candidate.REFLECT_H:
		return Vector2((y - x) * 31.0, (x + y) * 16.0)
	return Vector2((x - y) * 31.0, (x + y) * 16.0)


static func unproject_to_visual_point(world: Vector2) -> Vector2:
	var s := float(TileSizeConfig.TILE_WIDTH) / 62.0
	if s <= 0.0:
		return Vector2.ZERO
	var sy := world.y / (16.0 * s)
	var sx := world.x / (31.0 * s)
	if active_candidate == Candidate.REFLECT_H:
		return Vector2((sy - sx) * 0.5, (sx + sy) * 0.5)
	return Vector2((sx + sy) * 0.5, (sy - sx) * 0.5)


static func project_visual_point_scaled(point: Vector2) -> Vector2:
	var s := float(TileSizeConfig.TILE_WIDTH) / 62.0
	return project_visual_point(point) * s


static func presentation_world_direction(world_direction_degrees: int) -> int:
	## Identity — kept as a single hook if a future candidate needs a remap.
	## X-flip is coordinate-only; facet math uses authored world Direction as-is.
	return posmod(world_direction_degrees, 360)


static func reflect_facet_letter(letter: String) -> String:
	if active_candidate != Candidate.REFLECT_DIR:
		return letter
	match letter.to_lower():
		"ne":
			return "se"
		"se":
			return "ne"
		"nw":
			return "sw"
		"sw":
			return "nw"
		_:
			return letter
