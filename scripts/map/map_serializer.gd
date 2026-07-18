class_name MapSerializer
extends RefCounted
## Shared map save that preserves Fortress schema + unknown top-level fields.


static func save_path(map_data: MapData, path: String) -> bool:
	if map_data == null:
		return false
	return MapData.save_to_file(map_data, path)


static func to_json_text(map_data: MapData) -> String:
	if map_data == null:
		return "{}"
	return JSON.stringify(map_data.to_dict(), "\t")
