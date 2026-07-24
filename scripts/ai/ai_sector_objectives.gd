class_name AiSectorObjectives
extends RefCounted
## Map-agnostic objective heuristics from spawns / dimensions / victory points.
## Future maps can supply richer metadata without changing AICommander.

const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const AiObjectiveClass := preload("res://scripts/ai/ai_objective.gd")


## Build initial plan objectives for an AI player.
static func objectives_for_plan(
	game_state,
	player_id: int,
	plan_id: String,
	claimed_cells: Array[Vector2i] = [],
) -> Array:
	var out: Array = []
	if game_state == null or game_state.map_data == null or game_state.command_hierarchy == null:
		return out
	var team_id: int = game_state.command_hierarchy.get_team_id(player_id)
	var enemy_team: int = Team.GERMANY if team_id == Team.USA else Team.USA
	var own_anchor := _team_anchor(game_state, team_id)
	var enemy_anchor := _team_anchor(game_state, enemy_team)
	var sectors := _sector_cells(game_state.map_data, own_anchor, enemy_anchor)
	var plan := AiPlanClass.normalize_id(plan_id)

	match plan:
		AiPlanClass.ID_ATTACK_LEFT:
			out.append(_pick("attack_left", "Attack Left", sectors.left, claimed_cells, "sector", 10))
		AiPlanClass.ID_ATTACK_CENTER:
			out.append(_pick("attack_center", "Attack Center", sectors.center, claimed_cells, "sector", 10))
		AiPlanClass.ID_ATTACK_RIGHT:
			out.append(_pick("attack_right", "Attack Right", sectors.right, claimed_cells, "sector", 10))
		AiPlanClass.ID_FLANK:
			## Prefer the weaker-claimed flank (left or right).
			var left_cell: Vector2i = sectors.left[0] if not sectors.left.is_empty() else Vector2i(0, 0)
			var right_cell: Vector2i = sectors.right[0] if not sectors.right.is_empty() else Vector2i(0, 0)
			var left_score := _claim_penalty(left_cell, claimed_cells)
			var right_score := _claim_penalty(right_cell, claimed_cells)
			if left_score <= right_score:
				out.append(_pick("flank_left", "Flank Left", sectors.left, claimed_cells, "sector", 12))
			else:
				out.append(_pick("flank_right", "Flank Right", sectors.right, claimed_cells, "sector", 12))
		AiPlanClass.ID_DEFEND:
			var cover := _nearest_cover_cell(game_state, own_anchor, enemy_anchor, claimed_cells)
			out.append(
				AiObjectiveClass.make("defend_cover", "Defend Cover", cover, "cover", 10)
			)
		_:
			out.append(_pick("attack_center", "Attack Center", sectors.center, claimed_cells, "sector", 5))

	## Optional victory-point objective if authored on the map.
	var vp := _nearest_victory_point(game_state.map_data, enemy_anchor)
	if vp.x > -900:
		out.append(AiObjectiveClass.make("victory_point", "Victory Point", vp, "sector", 8))
	return out


static func retreat_objective(game_state, player_id: int) -> AiObjectiveClass:
	var team_id: int = game_state.command_hierarchy.get_team_id(player_id)
	var own_anchor := _team_anchor(game_state, team_id)
	var cover := _nearest_cover_cell(game_state, own_anchor, own_anchor, [])
	return AiObjectiveClass.make("retreat", "Retreat", cover, "retreat", 20)


static func hold_objective_at(cell: Vector2i) -> AiObjectiveClass:
	return AiObjectiveClass.make("hold", "Hold", cell, "hold", 15)


static func _pick(
	id: String,
	label: String,
	candidates: Array[Vector2i],
	claimed: Array[Vector2i],
	kind: String,
	prio: int,
) -> AiObjectiveClass:
	var best := Vector2i(-999, -999)
	var best_score := 999999
	for cell in candidates:
		var score := _claim_penalty(cell, claimed)
		if score < best_score:
			best_score = score
			best = cell
	if best.x <= -900 and not candidates.is_empty():
		best = candidates[0]
	return AiObjectiveClass.make(id, label, best, kind, prio)


static func _claim_penalty(cell: Vector2i, claimed: Array[Vector2i]) -> int:
	var penalty := 0
	for other in claimed:
		penalty += absi(cell.x - other.x) + absi(cell.y - other.y)
		## Soft-avoid exact duplicates.
		if cell == other:
			penalty += 40
	## Slight GameRandom jitter so coordination is imperfect.
	penalty += GameRandom.randi_range(0, 3)
	return penalty


static func _team_anchor(game_state, team_id: int) -> Vector2i:
	var map_data = game_state.map_data
	var points: Array = []
	if team_id == Team.USA:
		points = map_data.team_1_spawn_points
	else:
		points = map_data.team_2_spawn_points
	if points.is_empty():
		## Fall back to soldier positions for this player's team.
		var ft = game_state.session.get_fireteam(team_id)
		if ft != null:
			for state in ft.soldiers:
				if state != null and not state.is_dead:
					points.append(state.grid_position)
	if points.is_empty():
		return Vector2i(map_data.width / 2, map_data.height / 2)
	var sx := 0
	var sy := 0
	for p in points:
		sx += int(p.x)
		sy += int(p.y)
	return Vector2i(sx / points.size(), sy / points.size())


## Left / center / right approach cells along the attack corridor.
static func _sector_cells(map_data, own_anchor: Vector2i, enemy_anchor: Vector2i) -> Dictionary:
	var mid := Vector2i(
		int(round((own_anchor.x + enemy_anchor.x) * 0.5)),
		int(round((own_anchor.y + enemy_anchor.y) * 0.5)),
	)
	var dx := enemy_anchor.x - own_anchor.x
	var dy := enemy_anchor.y - own_anchor.y
	## Perpendicular offset for left/right sectors.
	var px := -dy
	var py := dx
	var plen := maxf(1.0, sqrt(float(px * px + py * py)))
	var ox := int(round(float(px) / plen * 8.0))
	var oy := int(round(float(py) / plen * 8.0))
	## Push slightly toward the enemy for attack posts.
	var toward := Vector2i(
		int(round(float(dx) * 0.35)),
		int(round(float(dy) * 0.35)),
	)
	var center := _clamp_walkable(map_data, mid + toward)
	var left := _clamp_walkable(map_data, mid + toward + Vector2i(ox, oy))
	var right := _clamp_walkable(map_data, mid + toward - Vector2i(ox, oy))
	return {"left": [left] as Array[Vector2i], "center": [center] as Array[Vector2i], "right": [right] as Array[Vector2i]}


static func _clamp_walkable(map_data, cell: Vector2i) -> Vector2i:
	var c := Vector2i(
		clampi(cell.x, 0, map_data.width - 1),
		clampi(cell.y, 0, map_data.height - 1),
	)
	if map_data.is_walkable(c):
		return c
	## Spiral search for nearest walkable.
	for radius in range(1, 12):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var n := c + Vector2i(dx, dy)
				if map_data.is_in_bounds(n) and map_data.is_walkable(n):
					return n
	return c


static func _nearest_cover_cell(
	game_state,
	near_cell: Vector2i,
	_face_toward: Vector2i,
	claimed: Array[Vector2i],
) -> Vector2i:
	var map_data = game_state.map_data
	var best := near_cell
	var best_score := 999999
	for cell in map_data.get_object_cells():
		var def = map_data.get_object_def(cell)
		if def == null or not def.provides_cover:
			continue
		## Prefer adjacent walkable tile to stand behind cover.
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var stand: Vector2i = cell + offset
			if not map_data.is_walkable(stand):
				continue
			var score := absi(stand.x - near_cell.x) + absi(stand.y - near_cell.y)
			score += _claim_penalty(stand, claimed)
			if score < best_score:
				best_score = score
				best = stand
	return _clamp_walkable(map_data, best)


static func _nearest_victory_point(map_data, near_cell: Vector2i) -> Vector2i:
	var best := Vector2i(-999, -999)
	var best_d := 999999
	for entry in map_data.victory_points:
		if not entry is Dictionary:
			continue
		var cell := Vector2i(int(entry.get("x", -999)), int(entry.get("y", -999)))
		if cell.x <= -900:
			continue
		var d := absi(cell.x - near_cell.x) + absi(cell.y - near_cell.y)
		if d < best_d:
			best_d = d
			best = _clamp_walkable(map_data, cell)
	return best
