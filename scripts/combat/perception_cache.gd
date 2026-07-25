class_name PerceptionCache
extends RefCounted
## Incremental observer↔target perception cache.
## Spotting scores and shot-LOS results persist until endpoint signatures change.
## Dirty pairs are processed with a deterministic per-tick budget (close threats first).

## Max pairs recomputed per simulation tick (remainder carries forward).
const PAIRS_PER_TICK := 32
## Combat-scan flush budget (still deterministic; drains queue).
const PAIRS_PER_COMBAT_FLUSH := 512
## Spatial filter — pairs beyond this Manhattan distance are not enqueued.
const MAX_PAIR_RANGE := 48

## pair_key -> { "score": float, "sig": int }
static var _spot_cache: Dictionary = {}
## pair_key -> { "blocked": bool, "status": int, "cover_type": int, "sig": int }
static var _shot_cache: Dictionary = {}
## pair_key -> priority (Manhattan dist); presence means dirty.
static var _dirty: Dictionary = {}

## Rolling profiler counters (reset each second by Main).
static var los_evals: int = 0
static var spot_cache_hits: int = 0
static var spot_cache_misses: int = 0
static var shot_cache_hits: int = 0
static var shot_cache_misses: int = 0
static var dirty_enqueued: int = 0
static var dirty_processed: int = 0
static var perception_usec: int = 0
static var stuck_events: int = 0
static var move_commands: int = 0
static var duplicate_commands_skipped: int = 0
static var path_requests: int = 0
static var path_cache_hits: int = 0


static func clear_all() -> void:
	_spot_cache.clear()
	_shot_cache.clear()
	_dirty.clear()


static func reset_counters() -> void:
	los_evals = 0
	spot_cache_hits = 0
	spot_cache_misses = 0
	shot_cache_hits = 0
	shot_cache_misses = 0
	dirty_enqueued = 0
	dirty_processed = 0
	perception_usec = 0
	stuck_events = 0
	move_commands = 0
	duplicate_commands_skipped = 0
	path_requests = 0
	path_cache_hits = 0


static func pair_key(obs_team: int, obs_id: int, tgt_team: int, tgt_id: int) -> String:
	return "%d:%d>%d:%d" % [obs_team, obs_id, tgt_team, tgt_id]


static func endpoint_sig(soldier) -> int:
	if soldier == null:
		return 0
	var cell: Vector2i = soldier.grid_position
	var h := 17
	h = _mix(h, cell.x)
	h = _mix(h, cell.y)
	h = _mix(h, soldier.facing_direction.x)
	h = _mix(h, soldier.facing_direction.y)
	h = _mix(h, int(soldier.is_dead))
	h = _mix(h, int(soldier.position_state))
	h = _mix(h, int(soldier.is_moving))
	h = _mix(h, int(soldier.movement_mode))
	## Bucket recently-fired so score bonuses invalidate without per-msec churn.
	var fired_bucket := int(soldier.last_fired_msec / 500) if soldier.last_fired_msec > 0 else 0
	h = _mix(h, fired_bucket)
	h = _mix(h, hash(str(soldier.weapon_id)))
	return h


static func pair_sig(observer, target) -> int:
	return _mix(endpoint_sig(observer), endpoint_sig(target))


static func dirty_count() -> int:
	return _dirty.size()


## Mark all in-range pairs involving this soldier dirty (both directions).
static func mark_soldier_dirty(game_state, soldier) -> void:
	if game_state == null or soldier == null or game_state.session == null:
		return
	var t0 := Time.get_ticks_usec()
	var enemy_team: int = Team.GERMANY if soldier.team_id == Team.USA else Team.USA
	var enemy_ft = game_state.session.get_fireteam(enemy_team)
	if enemy_ft == null:
		return
	var cell: Vector2i = soldier.grid_position
	for other_state in enemy_ft.soldiers:
		var other = other_state
		if other == null or other.is_dead:
			continue
		var dist: int = absi(cell.x - other.grid_position.x) + absi(cell.y - other.grid_position.y)
		if dist > MAX_PAIR_RANGE:
			continue
		_enqueue_pair(soldier.team_id, soldier.soldier_id, other.team_id, other.soldier_id, dist)
		_enqueue_pair(other.team_id, other.soldier_id, soldier.team_id, soldier.soldier_id, dist)
	perception_usec += Time.get_ticks_usec() - t0


static func mark_all_dirty(game_state) -> void:
	if game_state == null or game_state.session == null:
		return
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			if state != null and not state.is_dead:
				mark_soldier_dirty(game_state, state)


static func _enqueue_pair(
	obs_team: int,
	obs_id: int,
	tgt_team: int,
	tgt_id: int,
	dist: int,
) -> void:
	var key := pair_key(obs_team, obs_id, tgt_team, tgt_id)
	if not _dirty.has(key):
		dirty_enqueued += 1
	var prev: int = int(_dirty.get(key, 999999))
	_dirty[key] = mini(prev, dist)
	_spot_cache.erase(key)
	_shot_cache.erase(key)


## Cached spotting score. compute: Callable() -> float (no args; closes over obs/tgt).
static func get_or_compute_spot(
	observer,
	target,
	compute: Callable,
) -> float:
	if observer == null or target == null:
		return -1.0
	var key := pair_key(observer.team_id, observer.soldier_id, target.team_id, target.soldier_id)
	var sig := pair_sig(observer, target)
	var entry: Variant = _spot_cache.get(key)
	if entry is Dictionary and int(entry.get("sig", -1)) == sig:
		spot_cache_hits += 1
		_dirty.erase(key)
		return float(entry.get("score", -1.0))
	spot_cache_misses += 1
	los_evals += 1
	var score: float = float(compute.call())
	_spot_cache[key] = {"score": score, "sig": sig}
	_dirty.erase(key)
	return score


## Cached shot-LOS. compute: Callable() -> Dictionary {blocked, status, cover_type}
static func get_or_compute_shot(
	observer,
	target,
	compute: Callable,
) -> Dictionary:
	var empty := {"blocked": true, "status": 0, "cover_type": 0}
	if observer == null or target == null:
		return empty
	var key := pair_key(observer.team_id, observer.soldier_id, target.team_id, target.soldier_id)
	var sig := pair_sig(observer, target)
	var entry: Variant = _shot_cache.get(key)
	if entry is Dictionary and int(entry.get("sig", -1)) == sig:
		shot_cache_hits += 1
		return entry as Dictionary
	shot_cache_misses += 1
	los_evals += 1
	var result: Dictionary = compute.call()
	result["sig"] = sig
	_shot_cache[key] = result
	return result


## Process dirty spotting pairs with a budget. compute_pair: Callable(obs, tgt) -> float
static func process_dirty_budget(
	game_state,
	budget: int,
	resolve_soldiers: Callable,
	compute_pair: Callable,
) -> int:
	if budget <= 0 or _dirty.is_empty() or game_state == null:
		return 0
	var t0 := Time.get_ticks_usec()
	var keys: Array = _dirty.keys()
	keys.sort_custom(func(a, b) -> bool:
		var da: int = int(_dirty.get(a, 999999))
		var db: int = int(_dirty.get(b, 999999))
		if da != db:
			return da < db
		return str(a) < str(b)
	)
	var processed := 0
	for key in keys:
		if processed >= budget:
			break
		var parts := _parse_pair_key(str(key))
		if parts.is_empty():
			_dirty.erase(key)
			continue
		var pair: Variant = resolve_soldiers.call(
			parts.obs_team, parts.obs_id, parts.tgt_team, parts.tgt_id
		)
		if not (pair is Dictionary):
			_dirty.erase(key)
			_spot_cache.erase(key)
			continue
		var pair_dict: Dictionary = pair
		var observer = pair_dict.get("observer")
		var target = pair_dict.get("target")
		if observer == null or target == null or observer.is_dead or target.is_dead:
			_dirty.erase(key)
			_spot_cache.erase(key)
			continue
		los_evals += 1
		var score: float = float(compute_pair.call(observer, target))
		_spot_cache[str(key)] = {"score": score, "sig": pair_sig(observer, target)}
		_dirty.erase(key)
		processed += 1
		dirty_processed += 1
	perception_usec += Time.get_ticks_usec() - t0
	return processed


static func flush_dirty(
	game_state,
	resolve_soldiers: Callable,
	compute_pair: Callable,
) -> int:
	return process_dirty_budget(game_state, PAIRS_PER_COMBAT_FLUSH, resolve_soldiers, compute_pair)


static func _parse_pair_key(key: String) -> Dictionary:
	var sides := key.split(">")
	if sides.size() != 2:
		return {}
	var left := sides[0].split(":")
	var right := sides[1].split(":")
	if left.size() < 2 or right.size() < 2:
		return {}
	return {
		"obs_team": int(left[0]),
		"obs_id": int(left[1]),
		"tgt_team": int(right[0]),
		"tgt_id": int(right[1]),
	}


static func _mix(h: int, value: int) -> int:
	return int((h * 31 + value) & 0x7fffffff)


static func debug_summary() -> String:
	return (
		"LOS=%d spotHit=%d spotMiss=%d shotHit=%d shotMiss=%d dirtyQ=%d dirtyDone=%d perc_us=%d pathReq=%d pathHit=%d moves=%d dedupe=%d stuck=%d"
		% [
			los_evals,
			spot_cache_hits,
			spot_cache_misses,
			shot_cache_hits,
			shot_cache_misses,
			_dirty.size(),
			dirty_processed,
			perception_usec,
			path_requests,
			path_cache_hits,
			move_commands,
			duplicate_commands_skipped,
			stuck_events,
		]
	)
