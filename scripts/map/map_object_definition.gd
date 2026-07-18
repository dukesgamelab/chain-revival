class_name MapObjectDefinition
extends RefCounted
## Authorable object record (visual + future gameplay metadata).
## Visual identity is family + direction; PNGs resolve via the shared manifest.

var family: String = ""
var direction: int = 0
var image1: String = ""
var z: int = 0
var object_type: String = ""
var comments: String = ""
var tags: PackedStringArray = PackedStringArray()

## Future gameplay fields (editor architecture; gameplay may ignore for now).
var material: String = "" ## stone/wood/brick/sandbags/tree/fence
var height_band: String = "" ## ground/low/waist/wall/roof
var cover_north: bool = false
var cover_south: bool = false
var cover_east: bool = false
var cover_west: bool = false
var movement_cost: String = "" ## walk/run/crawl
var los_mode: String = "" ## opaque/partial/none
var bullet_penetration: String = "" ## none/partial/full
var concealment: float = 0.0
var suppression_modifier: float = 0.0
var blocks_movement: bool = true
var blocks_los: bool = true
var blocks_bullets: bool = true
var provides_cover: bool = true
var cover_type: int = 2 ## CoverSystem.COMPLETE default for walls

var unknown_source: Dictionary = {}


func to_source_dict() -> Dictionary:
	var src := unknown_source.duplicate(true)
	src["image"] = family.to_upper()
	src["direction"] = direction
	src["z"] = z
	if not image1.is_empty():
		src["image1"] = image1.to_upper()
	elif src.has("image1"):
		src.erase("image1")
	if not comments.is_empty():
		src["comments"] = comments
	if not tags.is_empty():
		src["tags"] = Array(tags)
	if not material.is_empty():
		src["material"] = material
	if not height_band.is_empty():
		src["height_band"] = height_band
	if not movement_cost.is_empty():
		src["movement_cost"] = movement_cost
	if not los_mode.is_empty():
		src["los_mode"] = los_mode
	if not bullet_penetration.is_empty():
		src["bullet_penetration"] = bullet_penetration
	src["concealment"] = concealment
	src["suppression_modifier"] = suppression_modifier
	src["cover_faces"] = {
		"n": cover_north,
		"s": cover_south,
		"e": cover_east,
		"w": cover_west,
	}
	return src


static func from_placement(entry: Dictionary) -> MapObjectDefinition:
	var def := MapObjectDefinition.new()
	var source: Dictionary = entry.get("source", {}) if entry.get("source", {}) is Dictionary else {}
	def.unknown_source = source.duplicate(true)
	def.family = str(entry.get("family", source.get("image", ""))).to_upper()
	def.direction = int(entry.get("direction", source.get("direction", 0)))
	def.image1 = str(entry.get("image1", source.get("image1", ""))).to_upper()
	def.z = int(entry.get("z", source.get("z", 0)))
	def.object_type = str(entry.get("object_type", ""))
	def.comments = str(source.get("comments", ""))
	var tags_raw: Variant = source.get("tags", [])
	if tags_raw is Array:
		for t in tags_raw:
			def.tags.append(str(t))
	def.material = str(source.get("material", ""))
	def.height_band = str(source.get("height_band", ""))
	def.movement_cost = str(source.get("movement_cost", ""))
	def.los_mode = str(source.get("los_mode", ""))
	def.bullet_penetration = str(source.get("bullet_penetration", ""))
	def.concealment = float(source.get("concealment", 0.0))
	def.suppression_modifier = float(source.get("suppression_modifier", 0.0))
	var faces: Variant = source.get("cover_faces", {})
	if faces is Dictionary:
		def.cover_north = bool(faces.get("n", false))
		def.cover_south = bool(faces.get("s", false))
		def.cover_east = bool(faces.get("e", false))
		def.cover_west = bool(faces.get("w", false))
	def.blocks_movement = bool(entry.get("blocks_movement", true))
	def.blocks_los = bool(entry.get("blocks_los", true))
	def.provides_cover = bool(entry.get("provides_cover", true))
	def.cover_type = int(entry.get("cover_type", 2))
	def.blocks_bullets = bool(source.get("blocks_bullets", def.blocks_los))
	return def


static func type_id_for_family(family: String) -> String:
	var fam := family.to_upper()
	if fam.is_empty():
		return "coc_prop"
	if fam.begins_with("WH") or fam.ends_with("WIN") or fam == "SWIN" or fam == "WWIN":
		return "coc_window"
	if fam in ["WWAR", "WWAQ", "SWAR", "SWAQ", "WWAI"]:
		return "coc_door_wood"
	if fam.ends_with("COR") or fam.ends_with("ICR"):
		return "coc_wall_corner"
	if fam.begins_with("TR"):
		return "coc_tree"
	if fam.begins_with("BH") or fam.begins_with("CW"):
		return "coc_bush"
	if fam == "WWAL":
		return "coc_wwal"
	if fam == "SWAL":
		return "coc_swal"
	if fam in ["LIHW", "IWWL", "RIHW"]:
		return "coc_wall"
	if CocRenderRules.is_floor_family(fam):
		return "coc_floor"
	if fam == "GRS":
		return "coc_ground"
	return "coc_%s" % fam.to_lower()
