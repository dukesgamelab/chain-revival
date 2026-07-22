class_name CocRenderRules
extends RefCounted
## Recovered CoC render rules from the Fortress handoff (shared by game + future editor).

## Footage-verified floor display mapping (non-original archive literalism).
## SFLO/WFLO archive art is green-moss / raised footing; reference previews use flat tan
## SFL5_w / WFL5_w. Enabled by default so the game matches supplied v2 references.
const USE_FOOTAGE_FLOOR_ART := true

const FLOOR_FAMILIES := {
	"SFLO": true,
	"WFLO": true,
	"SFR2": true,
	"SFL5": true,
	"WFL5": true,
}

## Families that receive Image1 / half-diamond underlays (from reference_renderer WALLISH).
const WALLISH_FAMILIES := {
	"IWWL": true,
	"IWAL": true,
	"IWDR": true,
	"RIHW": true,
	"LIHW": true,
	"SWAL": true,
	"WWAL": true,
	"WH01": true,
	"WH02": true,
	"WH09": true,
	"SCRS": true,
	"SWIN": true,
	"WWIN": true,
	"IWCR": true,
	"IWCL": true,
	"WCOR": true,
	"SCOR": true,
	"SICR": true,
	"WICR": true,
	"WWAR": true,
	"WWAQ": true,
	"SWAQ": true,
	"SWAR": true,
	"SWAI": true,
	"SI04": true,
	"WI04": true,
	"WWAI": true,
	"WH11": true,
	"WH00": true,
	"SDOR": true,
	"WDOR": true,
}

## Exterior walls: under CoC X-flip, facet world dir needs +180 so the textured /
## outward face matches OG. Interior families (IWWL, IWCR, LIHW, …) stay identity
## so dir0@cam0 keeps the clean interior face (not opposite/burned archive art).
const EXTERIOR_OUTWARD_FACE_FAMILIES := {
	"SWAL": true,
	"SCOR": true,
	"SICR": true,
	"SWIN": true,
	"SWAQ": true,
	"SWAR": true,
	"SWAI": true,
	"SI04": true,
	"SDOR": true,
	"WWAL": true,
	"WCOR": true,
	"WICR": true,
	"WWIN": true,
	"WWAR": true,
	"WWAQ": true,
	"WWAI": true,
	"WI04": true,
	"WDOR": true,
	"WH01": true,
	"WH02": true,
	"WH09": true,
	"WH11": true,
	"WH00": true,
	"SCRS": true,
}

## Cardinal neighbor → screen-space half-diamond direction (source pitch units).
## Values assume presentation without CoC X-flip. Use neighbor_screen_dirs().
const NEIGHBOR_DIRS: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(-1, 0),
]
const NEIGHBOR_SCREEN: Array[Vector2] = [
	Vector2(-31, 16),
	Vector2(31, 16),
	Vector2(31, -16),
	Vector2(-31, -16),
]
## After authoritative CoC X-flip, logical ±X neighbors land on the opposite screen diagonal.
const NEIGHBOR_SCREEN_XFLIP: Array[Vector2] = [
	Vector2(-31, 16),
	Vector2(-31, -16),
	Vector2(31, -16),
	Vector2(31, 16),
]


static func neighbor_screen_dirs() -> Array[Vector2]:
	if MapCoordinateTransform.uses_coc_x_flip():
		return NEIGHBOR_SCREEN_XFLIP
	return NEIGHBOR_SCREEN


static func is_floor_family(family: String) -> bool:
	return FLOOR_FAMILIES.has(family.to_upper())


static func is_wallish_family(family: String) -> bool:
	return WALLISH_FAMILIES.has(family.to_upper())


static func uses_outward_face_remap(family: String) -> bool:
	return EXTERIOR_OUTWARD_FACE_FAMILIES.has(family.to_upper())


## Resolve the sprite used when drawing a floor family (authored floors / Image1 / underlay).
static func resolve_floor_display(family: String, direction: int = 0) -> Dictionary:
	var fam := family.to_upper()
	var resolved: Dictionary = {}
	var letter := "e"
	if USE_FOOTAGE_FLOOR_ART:
		match fam:
			"SFLO", "SFR2", "SFL5":
				letter = "w"
				resolved = CocTileCatalog.resolve("SFL5", "w")
			"WFLO", "WFL5":
				letter = "w"
				resolved = CocTileCatalog.resolve("WFL5", "w")
			_:
				return CocFacetSelector.resolve_draw(fam, direction)
	else:
		return CocFacetSelector.resolve_draw(fam, direction)
	if resolved.is_empty():
		return {
			"family": fam,
			"letter": letter,
			"path": "",
			"hotspot": CocTileCatalog.DEFAULT_HOTSPOT,
			"missing": true,
		}
	resolved["letter"] = letter
	resolved["missing"] = false
	resolved["display_angle"] = 0
	resolved["facet_count"] = 1
	return resolved


static func ground_hash(cell: Vector2i, variant_count: int) -> int:
	## Well-mixed hash from the handoff reference renderer (stable across camera rotation).
	if variant_count <= 0:
		return 0
	var x: int = (cell.x * 73856093) ^ (cell.y * 19349663) ^ ((cell.x + cell.y) * 83492791)
	x = (x ^ (x >> 13)) * 0x5bd1e995
	return posmod(x ^ (x >> 15), variant_count)


static func is_unusable_sprite(resolved: Dictionary) -> bool:
	## Skip archive placeholder strips (e.g. LIHW_w 300×22 solid cyan) without inventing art.
	if resolved.is_empty() or bool(resolved.get("missing", false)):
		return true
	var size: Vector2 = resolved.get("size", Vector2.ZERO)
	if size.x >= 200.0 and size.y <= 40.0:
		return true
	var path := str(resolved.get("path", ""))
	if path.is_empty():
		return true
	return false
