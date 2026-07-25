class_name VictoryPointSystem
extends RefCounted
## Runtime victory-point capture. Authority-only — mutates map_data.victory_points holder.

## Chebyshev ("squares") radius: US soldier this close flips GE → USA.
const CAPTURE_RADIUS := 5


## Ensure runtime holder is seeded from initial_holder once per match load.
static func ensure_holders_initialized(map_data) -> void:
	if map_data == null:
		return
	for entry in map_data.victory_points:
		if not entry is Dictionary:
			continue
		if str(entry.get("holder", "")).strip_edges().is_empty():
			entry["holder"] = str(entry.get("initial_holder", "Germany"))


## Returns true if any VP holder changed (so presentation can redraw).
static func update_capture(game_state) -> bool:
	if game_state == null or game_state.map_data == null:
		return false
	if game_state.is_deployment_phase():
		return false
	var map_data = game_state.map_data
	ensure_holders_initialized(map_data)
	var changed := false
	for entry in map_data.victory_points:
		if not entry is Dictionary:
			continue
		var holder := str(entry.get("holder", entry.get("initial_holder", "Germany")))
		if _holder_is_usa(holder):
			continue
		var cell := Vector2i(int(entry.get("x", -999)), int(entry.get("y", -999)))
		if cell.x <= -900:
			continue
		if _usa_soldier_within(game_state, cell, CAPTURE_RADIUS):
			entry["holder"] = "USA"
			changed = true
			GameLog.log_system(
				"[VictoryPoint] captured by USA at %s (was %s)" % [cell, holder]
			)
	return changed


static func _usa_soldier_within(game_state, cell: Vector2i, radius: int) -> bool:
	var ft = game_state.session.get_fireteam(Team.USA)
	if ft == null:
		return false
	for soldier in ft.soldiers:
		if soldier == null or soldier.is_dead:
			continue
		var d := maxi(
			absi(soldier.grid_position.x - cell.x),
			absi(soldier.grid_position.y - cell.y),
		)
		if d <= radius:
			return true
	return false


static func _holder_is_usa(holder: String) -> bool:
	var key := holder.strip_edges().to_lower()
	return key == "usa" or key == "us" or key.contains("american")
