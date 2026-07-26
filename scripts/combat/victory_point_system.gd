class_name VictoryPointSystem
extends RefCounted
## Runtime victory-point ownership. Authority-only — mutates map_data.victory_points.

## Chebyshev ("squares") radius for presence / contest.
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
		if not entry.has("capture_elapsed_sec"):
			entry["capture_elapsed_sec"] = 0.0


## Poll ownership. Holder = side with living soldiers in radius and no living enemy contesting.
## `elapsed_sec` stamps capture time for end-of-mission decay awards.
## Returns true if any VP holder changed (so presentation can redraw).
static func update_capture(game_state, elapsed_sec: float = 0.0) -> bool:
	if game_state == null or game_state.map_data == null:
		return false
	if game_state.is_deployment_phase() or game_state.is_ended_phase():
		return false
	var map_data = game_state.map_data
	ensure_holders_initialized(map_data)
	var changed := false
	for entry in map_data.victory_points:
		if not entry is Dictionary:
			continue
		var cell := Vector2i(int(entry.get("x", -999)), int(entry.get("y", -999)))
		if cell.x <= -900:
			continue
		var usa_here := _team_soldier_within(game_state, Team.USA, cell, CAPTURE_RADIUS)
		var ger_here := _team_soldier_within(game_state, Team.GERMANY, cell, CAPTURE_RADIUS)
		## Contested — no ownership change.
		if usa_here and ger_here:
			continue
		var new_holder := ""
		if usa_here:
			new_holder = "USA"
		elif ger_here:
			new_holder = "Germany"
		else:
			continue
		var prev := str(entry.get("holder", entry.get("initial_holder", "Germany")))
		if _same_holder(prev, new_holder):
			continue
		entry["holder"] = new_holder
		entry["capture_elapsed_sec"] = elapsed_sec
		changed = true
		GameLog.log_system(
			"[VictoryPoint] %s captured at %s (was %s) t=%.1fs"
			% [new_holder, cell, prev, elapsed_sec]
		)
	return changed


static func holder_is_usa(holder: String) -> bool:
	var key := holder.strip_edges().to_lower()
	return key == "usa" or key == "us" or key.contains("american")


static func holder_team_id(holder: String) -> int:
	return Team.USA if holder_is_usa(holder) else Team.GERMANY


static func _team_soldier_within(
	game_state,
	team_id: int,
	cell: Vector2i,
	radius: int,
) -> bool:
	var ft = game_state.session.get_fireteam(team_id)
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


static func _same_holder(a: String, b: String) -> bool:
	return holder_is_usa(a) == holder_is_usa(b)


## Legacy helpers kept for call sites.
static func _usa_soldier_within(game_state, cell: Vector2i, radius: int) -> bool:
	return _team_soldier_within(game_state, Team.USA, cell, radius)


static func _holder_is_usa(holder: String) -> bool:
	return holder_is_usa(holder)
