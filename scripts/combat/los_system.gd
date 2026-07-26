class_name LOSSystem
extends RefCounted
## Central line-of-sight evaluation for combat and UI preview.
## evaluate() = strict shot LOS (soldiers block). evaluate_spotting() = visibility only.
## Uses MapData obstruction_height / terrain class via CoverSystem.
enum Status { CLEAR, COVER, BLOCKED }

const COLOR_CLEAR := Color(0.25, 0.95, 0.35, 0.90)
const COLOR_COVER := Color(0.95, 0.88, 0.20, 0.90)
const COLOR_BLOCKED := Color(0.95, 0.18, 0.12, 0.90)

## Master switch for verbose [LOS] / [Cover] / [Visibility] traces. Off during normal play.
const DEBUG_LOS := false
const PROJECT_SETTING_LOS_VERBOSE := "debug/combat/los_verbose"

static var debug_logging_enabled: bool = DEBUG_LOS
static var _last_debug_key: String = ""


static func apply_debug_settings() -> void:
	if ProjectSettings.has_setting(PROJECT_SETTING_LOS_VERBOSE):
		debug_logging_enabled = bool(ProjectSettings.get_setting(PROJECT_SETTING_LOS_VERBOSE))
	else:
		debug_logging_enabled = DEBUG_LOS
	_last_debug_key = ""


static func is_debug_logging_enabled() -> bool:
	return debug_logging_enabled


class LossResult extends RefCounted:
	var status: int = Status.CLEAR
	var cover_type: int = CoverSystem.CoverType.NONE
	var cover_source_type: String = ""
	var cover_source_cell: Vector2i = Vector2i(-999, -999)
	var cover_qualifier: int = 0 ## CoverPolicy.Qualifier
	var cover_qualifying_cells: Array[Vector2i] = []
	var blocking_cell: Vector2i = Vector2i(-999, -999)
	var blocking_type: String = ""
	var shooter_using_wall_cover: bool = false
	var target_using_wall_cover: bool = false
	## Offensive corner peek (shot LOS only) — drives PeekLeft / PeekRight presentation.
	var corner_peek: bool = false
	var peek_side: int = CoverSystem.PeekSide.NONE
	var corner_cell: Vector2i = Vector2i(-999, -999)


static func evaluate(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	game_state: GameState = null,
) -> LossResult:
	var result := LossResult.new()
	if map_data == null or not map_data.is_in_bounds(from_cell) or not map_data.is_in_bounds(to_cell):
		result.status = Status.BLOCKED
		_log_evaluation(from_cell, to_cell, map_data, result, game_state)
		return result

	## Rebuild occupancy only when soldier positions changed since last map build.
	if game_state != null:
		game_state.ensure_cell_occupancy()

	## One Bresenham walk shared by wall-cover + blocker scan (was 2–3 full walks).
	var line := CoverSystem.line_cells_between(from_cell, to_cell)
	var wall_usage := CoverSystem.evaluate_wall_cover_usage(from_cell, to_cell, map_data, line)
	result.shooter_using_wall_cover = wall_usage.shooter_using_wall_cover
	result.target_using_wall_cover = wall_usage.target_using_wall_cover

	var block := CoverSystem.find_blocking_tile(
		from_cell, to_cell, map_data, game_state, true, line,
	)
	if block.corner_peek:
		result.corner_peek = true
		result.peek_side = block.peek_side
		result.corner_cell = block.corner_cell
		## Offensive lean around a wall end flanks that cell — it is not hard cover for the target.
		if (
			result.target_using_wall_cover
			and wall_usage.target_cover_cell == result.corner_cell
		):
			result.target_using_wall_cover = false
	if block.blocked:
		result.status = Status.BLOCKED
		result.blocking_cell = block.blocking_cell
		result.blocking_type = block.blocking_type_id
		if result.blocking_type.is_empty():
			result.blocking_type = MapObjectRegistry.DEFAULT_BLOCKED_TYPE
		_log_evaluation(from_cell, to_cell, map_data, result, game_state)
		return result

	## Offensive corner peek with no remaining hard wall = clear shot.
	## Other cover still applies when the target keeps hard protection (e.g. deeper wall).
	if result.corner_peek and not result.target_using_wall_cover:
		result.status = Status.CLEAR
		_log_evaluation(from_cell, to_cell, map_data, result, game_state)
		return result

	var cover := CoverSystem.evaluate_target_cover(from_cell, to_cell, map_data)
	result.cover_type = cover.cover_type
	result.cover_source_type = cover.source_type_id
	result.cover_source_cell = cover.source_cell
	result.cover_qualifier = cover.qualifier
	result.cover_qualifying_cells = cover.qualifying_cells.duplicate()
	if cover.cover_type in [CoverSystem.CoverType.MODERATE, CoverSystem.CoverType.COMPLETE]:
		result.status = Status.COVER
	else:
		result.status = Status.CLEAR

	_log_evaluation(from_cell, to_cell, map_data, result, game_state)
	return result


## Spotting visibility: map blockers only — living/dead soldiers never block.
## Wall-cover peek flags are unused by spotting scores — skipped for performance.
## Prefer passing known prone flags (`resolve_prone=false`) on the hot observers×enemies path.
static func evaluate_spotting(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	game_state: GameState = null,
	observer_prone: bool = false,
	target_prone: bool = false,
	resolve_prone: bool = true,
) -> LossResult:
	var result := LossResult.new()
	if map_data == null or not map_data.is_in_bounds(from_cell) or not map_data.is_in_bounds(to_cell):
		result.status = Status.BLOCKED
		return result

	if resolve_prone and game_state != null:
		game_state.ensure_cell_occupancy()
		observer_prone = CoverSystem._cell_occupant_prone(from_cell, game_state)
		target_prone = CoverSystem._cell_occupant_prone(to_cell, game_state)

	var block := CoverSystem.find_spotting_blocking_tile(
		from_cell, to_cell, map_data, null, [], observer_prone, target_prone,
	)
	if block.blocked:
		result.status = Status.BLOCKED
		result.blocking_cell = block.blocking_cell
		result.blocking_type = block.blocking_type_id
		if result.blocking_type.is_empty():
			result.blocking_type = MapObjectRegistry.DEFAULT_BLOCKED_TYPE
		return result

	var cover := CoverSystem.evaluate_target_cover(from_cell, to_cell, map_data)
	result.cover_type = cover.cover_type
	result.cover_source_type = cover.source_type_id
	result.cover_source_cell = cover.source_cell
	result.cover_qualifier = cover.qualifier
	result.cover_qualifying_cells = cover.qualifying_cells.duplicate()
	if cover.cover_type == CoverSystem.CoverType.MODERATE:
		result.status = Status.COVER
	else:
		result.status = Status.CLEAR

	return result


## True when the spotting ray is blocked (no cover evaluation).
static func is_spotting_line_blocked(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	observer_prone: bool = false,
	target_prone: bool = false,
) -> bool:
	if map_data == null or not map_data.is_in_bounds(from_cell) or not map_data.is_in_bounds(to_cell):
		return true
	return CoverSystem.find_spotting_blocking_tile(
		from_cell, to_cell, map_data, null, [], observer_prone, target_prone,
	).blocked


static func is_spotting_blocked(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	game_state: GameState = null,
) -> bool:
	return evaluate_spotting(from_cell, to_cell, map_data, game_state).status == Status.BLOCKED


static func is_shot_blocked(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	game_state: GameState = null,
) -> bool:
	return evaluate(from_cell, to_cell, map_data, game_state).status == Status.BLOCKED


static func status_color(status: int) -> Color:
	match status:
		Status.COVER:
			return COLOR_COVER
		Status.BLOCKED:
			return COLOR_BLOCKED
		_:
			return COLOR_CLEAR


static func status_label(status: int, cover_type: int = CoverSystem.CoverType.NONE) -> String:
	match status:
		Status.COVER:
			if cover_type == CoverSystem.CoverType.COMPLETE:
				return "Complete cover"
			return "Moderate cover"
		Status.BLOCKED:
			return "Blocked"
		_:
			return "Clear"


static func status_name(status: int) -> String:
	match status:
		Status.COVER:
			return "COVER"
		Status.BLOCKED:
			return "BLOCKED"
		_:
			return "CLEAR"


static func preview_line_color(preview) -> Color:
	if preview == null or not preview.targetable:
		return COLOR_BLOCKED
	if preview.los == null:
		return COLOR_BLOCKED
	return status_color(preview.los.status)


static func _log_evaluation(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	result: LossResult,
	game_state: GameState = null,
) -> void:
	if not is_debug_logging_enabled():
		return

	var debug_key := "%s>%s>%s" % [from_cell, to_cell, result.status]
	if debug_key == _last_debug_key:
		return
	_last_debug_key = debug_key

	var lines: PackedStringArray = []
	lines.append("[LOS] %s -> %s" % [from_cell, to_cell])
	lines.append(
		"[Cover] Shooter using wall cover: %s"
		% ("true" if result.shooter_using_wall_cover else "false")
	)
	lines.append(
		"[Cover] Target using wall cover: %s"
		% ("true" if result.target_using_wall_cover else "false")
	)
	for entry in CoverSystem.trace_line_of_sight(from_cell, to_cell, map_data, game_state):
		if entry.type_id.is_empty():
			lines.append("  tile %s: (empty)" % entry.cell)
		else:
			lines.append(
				"  tile %s: %s blocks_los=%s blocks_line=%s peek_skip=%s wall_skip=%s soldier_block=%s soldier_pass=%s"
				% [
					entry.cell,
					entry.type_id,
					entry.blocks_los,
					entry.blocks_line,
					entry.peek_skipped,
					CoverSystem.wall_skip_reason_name(entry.wall_skip_reason),
					entry.soldier_blocks,
					entry.soldier_pass_through,
				]
			)
			if entry.soldier_pass_through:
				lines.append(
					"  [Cover] Soldier at %s ignored — dead or prone, not blocking"
					% entry.cell
				)
			if entry.wall_skip_reason == CoverSystem.WallSkipReason.SHOOTER_PEEK:
				lines.append(
					"  [Cover] Wall at %s skipped — shooter peeking over/around %s"
					% [entry.cell, entry.type_id]
				)
			elif entry.wall_skip_reason == CoverSystem.WallSkipReason.TARGET_COVER:
				lines.append(
					"  [Cover] Wall at %s skipped — target using %s as complete cover"
					% [entry.cell, entry.type_id]
				)
	if result.status == Status.BLOCKED:
		if result.blocking_type == "soldier":
			lines.append(
				"[LOS] Result: BLOCKED"
			)
			lines.append(
				"[LOS] Result detail: standing soldier at %s"
				% result.blocking_cell
			)
		elif _is_wall_blocker(result.blocking_type):
			lines.append("[LOS] Result: BLOCKED")
			lines.append(
				"[LOS] Result detail: wall at %s (%s)"
				% [result.blocking_cell, result.blocking_type]
			)
		else:
			lines.append("[LOS] Result: BLOCKED")
			lines.append(
				"[LOS] Result detail: obstacle at %s (%s)"
				% [result.blocking_cell, result.blocking_type]
			)
	elif result.status == Status.COVER:
		lines.append("[LOS] Result: COVER")
		if result.cover_type == CoverSystem.CoverType.COMPLETE:
			lines.append(
				"[Cover] Target receives COMPLETE cover from %s at %s"
				% [result.cover_source_type, result.cover_source_cell]
			)
		else:
			lines.append(
				"[Cover] Target in moderate cover from %s at %s"
				% [result.cover_source_type, result.cover_source_cell]
			)
	else:
		lines.append("[LOS] Result: CLEAR")
	GameLog.log_system("\n".join(lines))


static func _is_wall_blocker(blocking_type: String) -> bool:
	var def := MapObjectRegistry.get_def(blocking_type)
	return def != null and def.cover_type == CoverSystem.CoverType.COMPLETE
