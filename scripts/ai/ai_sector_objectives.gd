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
	## Survival GE waves always press the US victory point — not mid-map sector markers.
	if game_state.survival_mode and team_id == Team.GERMANY:
		var us_vp := _nearest_victory_point(game_state.map_data, enemy_anchor)
		if us_vp.x > -900:
			out.append(
				AiObjectiveClass.make("survival_us_vp", "US Objective", us_vp, "sector", 20)
			)
		return out
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
			out.append_array(
				_defend_objectives(game_state, team_id, own_anchor, enemy_anchor, claimed_cells)
			)
		_:
			out.append(_pick("attack_center", "Attack Center", sectors.center, claimed_cells, "sector", 5))

	## Optional victory-point objective if authored on the map.
	## DEFEND handles VP itself (only seize if not already held).
	if plan != AiPlanClass.ID_DEFEND:
		var vp := _nearest_victory_point(game_state.map_data, enemy_anchor)
		if vp.x > -900:
			out.append(AiObjectiveClass.make("victory_point", "Victory Point", vp, "sector", 8))
	return out


## Pick the best option for this fireteam.
## Avoids already-claimed cells first, then prefers higher priority (center over flanks).
static func select_for_claims(options: Array, claimed_cells: Array[Vector2i] = []):
	if options.is_empty():
		return null
	var best = null
	var best_score := 999999999
	for opt in options:
		if opt == null or not opt.is_valid():
			continue
		var claim := _claim_penalty(opt.cell, claimed_cells)
		## Claim dominates so DEFEND lanes spread; priority breaks ties (center=14).
		var score := claim * 100 - int(opt.priority)
		if best == null or score < best_score:
			best = opt
			best_score = score
	return best if best != null else options[0]


## Enemy spawn/approach anchor for facing while holding a defensive post.
static func enemy_approach_cell(game_state, player_id: int) -> Vector2i:
	if game_state == null or game_state.command_hierarchy == null:
		return Vector2i(-999, -999)
	var team_id: int = game_state.command_hierarchy.get_team_id(player_id)
	var enemy_team: int = Team.GERMANY if team_id == Team.USA else Team.USA
	return _team_anchor(game_state, enemy_team)


## How far forward of own lines DEFEND posts sit (never mid-map / enemy-side).
const DEFEND_FORWARD_CELLS := 10
const DEFEND_LATERAL_CELLS := 8
const DEFEND_COVER_RADIUS := 12
## Owned VP must be this close to spawn to count as the dig-in point.
const DEFEND_VP_MAX_DIST := 20


## DEFEND: split left/center/right holds just forward of own lines.
static func _defend_objectives(
	game_state,
	team_id: int,
	own_anchor: Vector2i,
	enemy_anchor: Vector2i,
	claimed_cells: Array[Vector2i],
) -> Array:
	var out: Array = []
	var map_data = game_state.map_data
	var defended := _defended_point(game_state, team_id, own_anchor)
	## Own-line screen — NOT attack corridor mid+toward-enemy (that sent GE to USA spawns).
	var sectors := _defend_sector_cells(map_data, defended, enemy_anchor)
	## Center is the most direct approach — highest priority for a lone fireteam.
	var lanes: Array = [
		{"id": "defend_center", "label": "Defend Center", "cells": sectors.center, "prio": 14},
		{"id": "defend_left", "label": "Defend Left", "cells": sectors.left, "prio": 12},
		{"id": "defend_right", "label": "Defend Right", "cells": sectors.right, "prio": 12},
	]
	## Soft-claim within this emit so left/center/right don't collapse to one stand.
	var lane_claims: Array[Vector2i] = claimed_cells.duplicate()
	for lane in lanes:
		var lane_cells: Array = lane.cells
		if lane_cells.is_empty():
			continue
		var lane_cell: Vector2i = lane_cells[0]
		## Cover near the approach lane, facing the enemy (directional via cover task).
		## Hard-exclude already-emitted stands so lanes don't collapse to one tile.
		var cover := nearest_cover_within(
			game_state, lane_cell, enemy_anchor, DEFEND_COVER_RADIUS, lane_claims, true, true
		)
		if cover.x <= -900:
			cover = _clamp_walkable(map_data, lane_cell)
			## Keep lane posts distinct even without cover objects.
			if cover in lane_claims:
				cover = _offset_unclaimed(map_data, cover, lane_claims)
		out.append(
			AiObjectiveClass.make(
				str(lane.id), str(lane.label), cover, "hold", int(lane.prio)
			)
		)
		if cover.x > -900:
			lane_claims.append(cover)
	## Only chase a VP we do not already control — never abandon cover for a held flag.
	if not _team_controls_victory_point(game_state, team_id):
		var vp := _nearest_victory_point(map_data, defended)
		if vp.x > -900:
			out.append(
				AiObjectiveClass.make("victory_point", "Victory Point", vp, "sector", 6)
			)
	return out


## Dig-in point: owned VP near our lines, else own spawn. Never a distant mid-map flag.
static func _defended_point(game_state, team_id: int, own_anchor: Vector2i) -> Vector2i:
	if not _team_controls_victory_point(game_state, team_id):
		return own_anchor
	var vp := _nearest_victory_point(game_state.map_data, own_anchor)
	if vp.x <= -900:
		return own_anchor
	var d := absi(vp.x - own_anchor.x) + absi(vp.y - own_anchor.y)
	if d > DEFEND_VP_MAX_DIST:
		return own_anchor
	return vp


## True when map VP holder (runtime `holder` or `initial_holder`) is this team.
static func _team_controls_victory_point(game_state, team_id: int) -> bool:
	if game_state == null or game_state.map_data == null:
		return false
	var team_names: Array[String] = []
	if team_id == Team.USA:
		team_names = ["usa", "us", "american", "americans"]
	else:
		team_names = ["germany", "german", "axis"]
	for entry in game_state.map_data.victory_points:
		if not entry is Dictionary:
			continue
		var holder := str(entry.get("holder", entry.get("initial_holder", ""))).strip_edges().to_lower()
		if holder.is_empty():
			continue
		for name in team_names:
			if holder == name or holder.contains(name):
				return true
	return false


static func retreat_objective(game_state, player_id: int) -> AiObjectiveClass:
	var team_id: int = game_state.command_hierarchy.get_team_id(player_id)
	var own_anchor := _team_anchor(game_state, team_id)
	var cover := _nearest_cover_cell(game_state, own_anchor, own_anchor, [])
	return AiObjectiveClass.make("retreat", "Retreat", cover, "retreat", 20)


static func hold_objective_at(cell: Vector2i) -> AiObjectiveClass:
	return AiObjectiveClass.make("hold", "Hold", cell, "hold", 15)


## Enemy spawn-anchor cell (walkable). Used by DIAGNOSTIC_SIMPLE_RUSH.
static func enemy_deployment_objective(game_state, player_id: int) -> AiObjectiveClass:
	if game_state == null or game_state.map_data == null or game_state.command_hierarchy == null:
		return AiObjectiveClass.make("enemy_deploy", "Enemy Deployment", Vector2i(-999, -999), "sector", 1)
	var team_id: int = game_state.command_hierarchy.get_team_id(player_id)
	var enemy_team: int = Team.GERMANY if team_id == Team.USA else Team.USA
	var enemy_anchor := _team_anchor(game_state, enemy_team)
	var cell := _clamp_walkable(game_state.map_data, enemy_anchor)
	return AiObjectiveClass.make("enemy_deploy", "Enemy Deployment", cell, "sector", 1)


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
	## Deterministic micro tie-break (never RNG — keeps MP/AI replays stable).
	penalty += absi(cell.x * 3 + cell.y * 7) % 4
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


## DEFEND screen: short forward offset from own lines + left/right spread.
## Must stay on our half — attack `_sector_cells` mid+0.35*toward lands on enemy spawns.
static func _defend_sector_cells(
	map_data,
	own_anchor: Vector2i,
	enemy_anchor: Vector2i,
) -> Dictionary:
	var dx := enemy_anchor.x - own_anchor.x
	var dy := enemy_anchor.y - own_anchor.y
	var flen := maxf(1.0, sqrt(float(dx * dx + dy * dy)))
	## Cap by corridor length so short test maps do not overshoot into enemy lines.
	var forward := mini(DEFEND_FORWARD_CELLS, maxi(2, int(round(flen * 0.2))))
	var lateral := mini(DEFEND_LATERAL_CELLS, maxi(2, forward))
	var fx := int(round(float(dx) / flen * float(forward)))
	var fy := int(round(float(dy) / flen * float(forward)))
	var px := -dy
	var py := dx
	var plen := maxf(1.0, sqrt(float(px * px + py * py)))
	var ox := int(round(float(px) / plen * float(lateral)))
	var oy := int(round(float(py) / plen * float(lateral)))
	var base := own_anchor + Vector2i(fx, fy)
	var center := _clamp_walkable(map_data, base)
	var left := _clamp_walkable(map_data, base + Vector2i(ox, oy))
	var right := _clamp_walkable(map_data, base - Vector2i(ox, oy))
	return {
		"left": [left] as Array[Vector2i],
		"center": [center] as Array[Vector2i],
		"right": [right] as Array[Vector2i],
	}


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
	## Radius-limited — full-map object scans were a 2v2 hitch on every DEFEND replan.
	return nearest_cover_within(game_state, near_cell, _face_toward, 24, claimed)


## True when standing at `stand` puts cover BETWEEN that cell and `threat`
## (same CoverPolicy geometry combat uses: threat = shooter, stand = target).
static func stand_covered_vs_threat(stand: Vector2i, threat: Vector2i, map_data) -> bool:
	if map_data == null or threat.x <= -900 or stand == threat:
		return false
	var check = GameplayPolicies.cover.cover_check(threat, stand, map_data)
	return check != null and bool(check.in_cover)


## True when an adjacent cover object sits closer to the threat than `stand`
## (soldier is on the far / "behind" side of that object).
static func stand_is_directly_behind(stand: Vector2i, threat: Vector2i, map_data) -> bool:
	if map_data == null or threat.x <= -900:
		return false
	var stand_d := absi(stand.x - threat.x) + absi(stand.y - threat.y)
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var obj_cell: Vector2i = stand + offset
		var def = map_data.get_object_def(obj_cell)
		if def == null or not def.provides_cover:
			continue
		var obj_d := absi(obj_cell.x - threat.x) + absi(obj_cell.y - threat.y)
		if obj_d < stand_d:
			return true
	return false


## Cover_check calls in the current AI think (reset by AiCommander.tick).
static var cover_checks_this_think: int = 0
## Hard cap — even with O(1) height lookups, unbounded directional scans are wasteful.
const MAX_COVER_CHECKS_PER_QUERY := 96

## Cover stand-tile within max_dist of near_cell. Returns (-999,-999) if none.
## When face_toward is a real threat (≠ near_cell), only stands that pass
## CoverPolicy.cover_check vs that threat are eligible.
## reject_claimed: skip exact claimed cells (DEFEND lane emit).
## prefer_behind: favor stands on the far side of cover from the threat (defend dig-in).
##
## IMPORTANT: evaluate nearest distance bands first and return early. Checking every
## cover stand on ff_farm (~500 cover objects) with cover_check was an AI hitch.
static func nearest_cover_within(
	game_state,
	near_cell: Vector2i,
	face_toward: Vector2i,
	max_dist: int,
	claimed: Array[Vector2i] = [],
	reject_claimed: bool = false,
	prefer_behind: bool = false,
) -> Vector2i:
	var map_data = game_state.map_data
	var none := Vector2i(-999, -999)
	if map_data == null or max_dist < 0:
		return none
	## Directional filter when we have a distinct threat axis (not retreat/any-cover).
	var require_dir := (
		face_toward.x > -900
		and face_toward != near_cell
	)
	## Bucket candidates by Manhattan distance, then scan nearest→farthest.
	var by_dist: Dictionary = {} ## dist -> Array[Vector2i]
	for stand in map_data.get_cover_stand_cells():
		var dist: int = absi(stand.x - near_cell.x) + absi(stand.y - near_cell.y)
		if dist > max_dist or dist <= 0:
			continue
		if reject_claimed and stand in claimed:
			continue
		if not by_dist.has(dist):
			by_dist[dist] = [] as Array[Vector2i]
		(by_dist[dist] as Array).append(stand)
	if by_dist.is_empty():
		return none
	var distances: Array = by_dist.keys()
	distances.sort()
	var best := none
	var best_score := 999999
	var checks_this_query := 0
	for i in range(distances.size()):
		var dist: int = int(distances[i])
		var stands: Array = by_dist[dist]
		stands.sort_custom(func(a, b) -> bool:
			if a.x != b.x:
				return a.x < b.x
			return a.y < b.y
		)
		for stand in stands:
			if require_dir:
				if checks_this_query >= MAX_COVER_CHECKS_PER_QUERY:
					break
				checks_this_query += 1
				cover_checks_this_think += 1
				if not stand_covered_vs_threat(stand, face_toward, map_data):
					continue
			var score: int = dist + _claim_penalty(stand, claimed)
			if prefer_behind and require_dir:
				if stand_is_directly_behind(stand, face_toward, map_data):
					score -= 20
				else:
					## Soft-penalize side-of-cover stands when digging in to defend.
					score += 6
			if score < best_score:
				best_score = score
				best = stand
		## Farther bands cannot beat a nearer best when scores are dist-dominated.
		## Skip early-out when prefer_behind — a farther "true behind" can win.
		if best.x > -900 and not prefer_behind:
			var next_min := 999999
			if i + 1 < distances.size():
				next_min = int(distances[i + 1])
			if best_score <= next_min:
				return _clamp_walkable(map_data, best)
		if checks_this_query >= MAX_COVER_CHECKS_PER_QUERY:
			break
	if best.x <= -900:
		return none
	return _clamp_walkable(map_data, best)


static func _offset_unclaimed(
	map_data,
	cell: Vector2i,
	claimed: Array[Vector2i],
) -> Vector2i:
	if cell not in claimed:
		return cell
	for radius in range(1, 8):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var n := cell + Vector2i(dx, dy)
				if n in claimed:
					continue
				if map_data.is_in_bounds(n) and map_data.is_walkable(n):
					return n
	return cell


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
