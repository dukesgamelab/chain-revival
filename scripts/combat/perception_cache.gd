class_name PerceptionCache
extends RefCounted
## Incremental observer↔target perception cache.
## Spotting scores and shot-LOS results persist until endpoint signatures change.
## Dirty pairs are processed with a deterministic per-tick budget (close threats first).

## Max pairs recomputed per simulation tick (grows with backlog; still deterministic).
const PAIRS_PER_TICK := 32
const PAIRS_PER_TICK_MAX := 128
## Combat-scan flush budget (still deterministic; drains queue).
const PAIRS_PER_COMBAT_FLUSH := 256
## Spatial filter — pairs beyond this Manhattan distance are not enqueued.
const MAX_PAIR_RANGE := 48
## Close threats always compute immediately on cache miss (gameplay-critical).
const CLOSE_FORCE_DIST := 14
## Hard cap — prevents unbounded dirty growth / sort death-spiral while armies march.
const MAX_DIRTY := 384
## Lightweight spatial buckets (optional candidate aid; never rebuilt per mover).
const SPATIAL_BUCKET := 8

## pair_key -> { "score": float, "sig": int }
static var _spot_cache: Dictionary = {}
## pair_key -> { "blocked": bool, "status": int, "cover_type": int, "sig": int }
static var _shot_cache: Dictionary = {}
## pair_key -> priority (Manhattan dist); presence means dirty.
static var _dirty: Dictionary = {}
## "team:bx:by" -> Array of soldier_id (int). Rebuilt lazily, not per step.
static var _spatial: Dictionary = {}
static var _spatial_built: bool = false

## Rolling profiler counters (reset each second by Main).
static var los_evals: int = 0
static var spot_cache_hits: int = 0
static var spot_cache_misses: int = 0
static var shot_cache_hits: int = 0
static var shot_cache_misses: int = 0
static var dirty_enqueued: int = 0
static var dirty_processed: int = 0
static var deferred_far: int = 0
static var dirty_dropped: int = 0
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
	_spatial.clear()
	_spatial_built = false


static func reset_counters() -> void:
	los_evals = 0
	spot_cache_hits = 0
	spot_cache_misses = 0
	shot_cache_hits = 0
	shot_cache_misses = 0
	dirty_enqueued = 0
	dirty_processed = 0
	deferred_far = 0
	dirty_dropped = 0
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
	## Do NOT hash is_moving — it flips every halt/step and thrashed the cache while armies marched.
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


## Deterministic per-tick budget that scales with backlog (no randomness).
static func tick_budget() -> int:
	var backlog := _dirty.size()
	if backlog <= PAIRS_PER_TICK:
		return PAIRS_PER_TICK
	return mini(PAIRS_PER_TICK_MAX, PAIRS_PER_TICK + backlog / 4)


static func _bucket_coord(cell: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(cell.x) / float(SPATIAL_BUCKET))),
		int(floor(float(cell.y) / float(SPATIAL_BUCKET))),
	)


static func _spatial_key(team_id: int, bucket: Vector2i) -> String:
	return "%d:%d:%d" % [team_id, bucket.x, bucket.y]


## Rebuild spatial index (lazy / explicit only — never from per-step dirty marks).
static func rebuild_spatial(game_state) -> void:
	_spatial.clear()
	_spatial_built = false
	if game_state == null or game_state.session == null:
		return
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			if state == null or state.is_dead:
				continue
			var b := _bucket_coord(state.grid_position)
			var key := _spatial_key(state.team_id, b)
			if not _spatial.has(key):
				_spatial[key] = []
			(_spatial[key] as Array).append(state.soldier_id)
	_spatial_built = true


## Mark in-range pairs involving this soldier dirty (both directions).
## Uses a direct enemy-fireteam scan (≤28) — cheaper and safer than rebuilding spatial per step.
static func mark_soldier_dirty(game_state, soldier, _rebuild: bool = true) -> void:
	if game_state == null or soldier == null or game_state.session == null:
		return
	var t0 := Time.get_ticks_usec()
	var enemy_team: int = Team.GERMANY if soldier.team_id == Team.USA else Team.USA
	var enemy_ft = game_state.session.get_fireteam(enemy_team)
	if enemy_ft == null:
		return
	var cell: Vector2i = soldier.grid_position
	## Spatial stale after moves — invalidate so optional lookups refresh later.
	_spatial_built = false
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
				mark_soldier_dirty(game_state, state, false)


static func _enqueue_pair(
	obs_team: int,
	obs_id: int,
	tgt_team: int,
	tgt_id: int,
	dist: int,
) -> void:
	var key := pair_key(obs_team, obs_id, tgt_team, tgt_id)
	if _dirty.has(key):
		_dirty[key] = mini(int(_dirty[key]), dist)
		_spot_cache.erase(key)
		_shot_cache.erase(key)
		return
	## Under pressure: only accept close pairs so the queue cannot grow without bound.
	if _dirty.size() >= MAX_DIRTY and dist > CLOSE_FORCE_DIST:
		dirty_dropped += 1
		return
	if _dirty.size() >= MAX_DIRTY:
		if not _drop_one_farthest_dirty():
			dirty_dropped += 1
			return
	dirty_enqueued += 1
	_dirty[key] = dist
	_spot_cache.erase(key)
	_shot_cache.erase(key)


## Drop one farthest dirty pair (deterministic: max dist, then key order).
static func _drop_one_farthest_dirty() -> bool:
	if _dirty.is_empty():
		return false
	var worst_key := ""
	var worst_dist := -1
	for key in _dirty.keys():
		var d: int = int(_dirty[key])
		var ks := str(key)
		if d > worst_dist or (d == worst_dist and (worst_key.is_empty() or ks > worst_key)):
			worst_dist = d
			worst_key = ks
	if worst_key.is_empty():
		return false
	_dirty.erase(worst_key)
	dirty_dropped += 1
	return true


## Read cached score without computing. Returns NAN if missing/stale.
static func peek_spot_score(observer, target) -> float:
	if observer == null or target == null:
		return NAN
	var key := pair_key(observer.team_id, observer.soldier_id, target.team_id, target.soldier_id)
	var sig := pair_sig(observer, target)
	var entry: Variant = _spot_cache.get(key)
	if entry is Dictionary and int(entry.get("sig", -1)) == sig:
		return float(entry.get("score", -1.0))
	return NAN


## Cached spotting score. Far misses may defer (enqueue dirty, return -1) unless force.
static func get_or_compute_spot(
	observer,
	target,
	compute: Callable,
	force_immediate: bool = false,
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
	var dist: int = (
		absi(observer.grid_position.x - target.grid_position.x)
		+ absi(observer.grid_position.y - target.grid_position.y)
	)
	if not force_immediate and dist > CLOSE_FORCE_DIST:
		## Spread first-contact spikes — close pairs still compute now.
		spot_cache_misses += 1
		deferred_far += 1
		## Avoid re-enqueue thrash if already waiting.
		if not _dirty.has(key):
			_enqueue_pair(
				observer.team_id, observer.soldier_id,
				target.team_id, target.soldier_id,
				dist,
			)
		return -1.0
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


## Process dirty spotting pairs with a budget. Close pairs first; no full-queue sort.
static func process_dirty_budget(
	game_state,
	budget: int,
	resolve_soldiers: Callable,
	compute_pair: Callable,
) -> int:
	if budget <= 0 or _dirty.is_empty() or game_state == null:
		return 0
	var t0 := Time.get_ticks_usec()
	## Partition then sort partitions (avoids O(n log n) on a multi-thousand backlog).
	var close_keys: Array = []
	var far_keys: Array = []
	for key in _dirty.keys():
		var d: int = int(_dirty[key])
		if d <= CLOSE_FORCE_DIST:
			close_keys.append(key)
		else:
			far_keys.append(key)
	close_keys.sort()
	far_keys.sort()
	var ordered: Array = []
	ordered.append_array(close_keys)
	ordered.append_array(far_keys)
	var processed := 0
	for key in ordered:
		if processed >= budget:
			break
		if not _dirty.has(key):
			continue
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
		"LOS=%d spotHit=%d spotMiss=%d shotHit=%d shotMiss=%d dirtyQ=%d dirtyDone=%d deferFar=%d drop=%d perc_us=%d pathReq=%d pathHit=%d moves=%d dedupe=%d stuck=%d"
		% [
			los_evals,
			spot_cache_hits,
			spot_cache_misses,
			shot_cache_hits,
			shot_cache_misses,
			_dirty.size(),
			dirty_processed,
			deferred_far,
			dirty_dropped,
			perception_usec,
			path_requests,
			path_cache_hits,
			move_commands,
			duplicate_commands_skipped,
			stuck_events,
		]
	)
