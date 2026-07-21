class_name Soldier
extends Node2D
## Presentation only: sprites, selection, facing arrow, movement animation.
##
## Does NOT mutate SoldierState. Emits movement signals so ActionResolver can update
## authoritative position via GameState when each animation step completes.

const UsSoldierSpriteFrames := preload("res://scripts/soldiers/us_soldier_sprite_frames.gd")

## OG art uses a 100×100 PNG canvas with transparency — an animation alignment grid,
## not the on-screen soldier height. Same scale for USA and Germany.
const OG_FRAME_SIZE := Vector2(100.0, 100.0)
const OG_SPRITE_SCALE := Vector2(1.6, 1.6)
const _PRONE_SPRITE_SCALE := Vector2(1.15, 0.42)

signal movement_step_reached(team_id: int, soldier_id: int, tile: Vector2i, step_delta: Vector2i)
signal movement_finished(team_id: int, soldier_id: int)

var soldier_id: int = 1
var team_id: int = Team.USA

@export var move_speed := 95.0 / 3.0

var _path: Array[Vector2i] = []
var _path_index: int = 0
var _move_target_world: Vector2 = Vector2.ZERO
var _is_moving: bool = false
var _previous_grid_pos: Vector2i = Vector2i.ZERO
var _is_dead: bool = false
var _speed_multiplier: float = 1.0
var _applied_position_state: int = -1
var _facing_from_cell: Vector2i = Vector2i.ZERO
var _last_applied_facing: Vector2i = FacingDirection.NORTH
var _locomotion_direction: String = "n"
var _locomotion_walking: bool = false
var _configured_team_id: int = -1
var _death_sequence_active: bool = false
var _death_direction: String = "n"
var _corpse_direction_locked: bool = false
var _hit_reaction_active: bool = false
var _hit_semantic: String = ""
var _hit_return_prone: bool = false

## When true, log hit-reaction resolution (semantic, family, directions, frames, FPS).
const DEBUG_HIT_REACTION := true


@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var _selection_marker: Polygon2D = $SelectionMarker
@onready var _facing_arrow: Line2D = $FacingArrow
@onready var _dead_marker: Line2D = $DeadMarker
@onready var _prone_marker: Line2D = $ProneMarker


func _ready() -> void:
	set_process(false)
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_anim.centered = true
	_facing_arrow.position.y = TileSizeConfig.facing_arrow_y()
	_prone_marker.position.y = TileSizeConfig.prone_marker_y()
	_dead_marker.position.y = TileSizeConfig.dead_marker_y()
	_configure_team_visual()
	_anim.animation_finished.connect(_on_anim_animation_finished)


## Apply authoritative gameplay state to this sprite (position, facing, selection).
func sync_from_state(state: SoldierState, is_selected: bool, is_spotted: bool = true) -> void:
	var previous_team := team_id
	soldier_id = state.soldier_id
	team_id = state.team_id
	if previous_team != team_id or _anim.sprite_frames == null:
		_configure_team_visual()
	_is_dead = state.is_dead

	if _death_sequence_active or _hit_reaction_active:
		soldier_id = state.soldier_id
		team_id = state.team_id
		position = IsometricGrid.grid_to_world(state.grid_position)
		return

	if state.is_dead:
		stop_movement()
		position = IsometricGrid.grid_to_world(state.grid_position)
		_facing_from_cell = state.grid_position
		_apply_facing(state.facing_direction, _facing_from_cell)
		_show_dead_static(_corpse_direction_for_state(state))
		return

	_dead_marker.visible = false
	if not _is_moving:
		position = IsometricGrid.grid_to_world(state.grid_position)
	_facing_from_cell = state.grid_position
	_apply_facing(state.facing_direction, _facing_from_cell)
	_apply_position_visual(state)
	_apply_spotted_visual(is_selected, is_spotted)
	set_selected(is_selected)
	if _is_moving and _uses_og_frames() and _path_index < _path.size():
		var step_delta := _path[_path_index] - _previous_grid_pos
		_update_locomotion_visual(step_delta, true)


func _apply_spotted_visual(is_selected: bool, is_spotted: bool) -> void:
	if _is_dead:
		return
	if is_spotted:
		if is_selected:
			_anim.modulate = Color(1.14, 1.14, 1.08, 1.0)
		else:
			_anim.modulate = Color.WHITE
	else:
		_anim.modulate = Color(0.55, 0.55, 0.58, 0.45)


func set_selected(is_selected: bool) -> void:
	if _death_sequence_active or _hit_reaction_active:
		_selection_marker.visible = false
		return
	if _is_dead:
		_selection_marker.visible = false
		return
	_selection_marker.visible = is_selected
	_selection_marker.polygon = IsometricGrid.diamond_corners(Vector2.ZERO)
	if not _is_moving and not _death_sequence_active and not _hit_reaction_active:
		_update_locomotion_visual(_last_applied_facing, false)


func _apply_dead_visual(_is_selected: bool) -> void:
	_applied_position_state = PositionState.DOWN
	_facing_arrow.visible = false
	_prone_marker.visible = false
	_dead_marker.visible = false
	_selection_marker.visible = false
	_anim.scale = _prone_sprite_scale()
	_anim.position = Vector2.ZERO
	_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
	_show_dead_static(_death_direction)
	_anim.modulate = Color(0.38, 0.38, 0.38, 0.85)


func _apply_position_visual(state: SoldierState) -> void:
	if not _is_dead and state.position_state == _applied_position_state:
		return
	_applied_position_state = state.position_state
	_anim.position = Vector2.ZERO
	if state.position_state == PositionState.DOWN:
		_anim.scale = _prone_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
		_prone_marker.visible = true
	else:
		_anim.scale = _standing_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_standing_sprite_offset()
		_prone_marker.visible = false
	_sync_facing_arrow_visibility()


func _standing_sprite_scale() -> Vector2:
	return OG_SPRITE_SCALE * TileSizeConfig.SOLDIER_SCALE


func _prone_sprite_scale() -> Vector2:
	var base := OG_SPRITE_SCALE * TileSizeConfig.SOLDIER_SCALE
	return Vector2(base.x * _PRONE_SPRITE_SCALE.x, base.y * _PRONE_SPRITE_SCALE.y)


func is_moving() -> bool:
	return _is_moving


## Recompute world positions after a presentation-only view rotation.
func refresh_movement_visual() -> void:
	if not _is_moving or _path.is_empty():
		return
	var start_index := maxi(_path_index - 1, 0)
	position = IsometricGrid.grid_to_world(_path[start_index])
	if _path_index < _path.size():
		_move_target_world = IsometricGrid.grid_to_world(_path[_path_index])


func stop_movement() -> void:
	var was_moving := _is_moving
	_is_moving = false
	_path.clear()
	_path_index = 0
	set_process(false)
	if was_moving and _uses_og_frames() and not _death_sequence_active and not _hit_reaction_active:
		_play_locomotion(_locomotion_direction, false)


func follow_path(path: Array[Vector2i], speed_multiplier: float = 1.0) -> void:
	## Presentation-only path animation. Authoritative grid_position updates via
	## movement_step_reached → ActionResolver.on_movement_step.
	if _is_dead or _death_sequence_active or _hit_reaction_active or path.size() <= 1:
		return

	_speed_multiplier = speed_multiplier
	_path = path
	_path_index = 1
	_is_moving = true
	_previous_grid_pos = _path[0]
	position = IsometricGrid.grid_to_world(_path[0])
	_move_target_world = IsometricGrid.grid_to_world(_path[_path_index])
	var first_step := _path[1] - _path[0]
	_apply_facing(FacingDirection.from_step(first_step), _previous_grid_pos)
	_update_locomotion_visual(first_step, true)
	set_process(true)


func _process(delta: float) -> void:
	# Interpolates Node2D.position only; does not write SoldierState.grid_position.
	if not _is_moving or _is_dead or _death_sequence_active or _hit_reaction_active:
		return

	var to_target := _move_target_world - position
	var distance := to_target.length()
	var step_delta := _path[_path_index] - _previous_grid_pos
	_apply_facing(FacingDirection.from_step(step_delta), _previous_grid_pos)
	_update_locomotion_visual(step_delta, true)

	if distance <= 0.001:
		_advance_path_step()
		return

	var move_amount := move_speed * _speed_multiplier * delta
	if move_amount >= distance:
		position = _move_target_world
		_advance_path_step()
	else:
		position += to_target.normalized() * move_amount


func _advance_path_step() -> void:
	var step_delta := _path[_path_index] - _previous_grid_pos
	position = _move_target_world
	movement_step_reached.emit(team_id, soldier_id, _path[_path_index], step_delta)
	_previous_grid_pos = _path[_path_index]
	_path_index += 1

	if _path_index >= _path.size():
		_is_moving = false
		set_process(false)
		_update_locomotion_visual(step_delta, false)
		movement_finished.emit(team_id, soldier_id)
	else:
		_move_target_world = IsometricGrid.grid_to_world(_path[_path_index])
		var next_step := _path[_path_index] - _previous_grid_pos
		_update_locomotion_visual(next_step, true)


func _apply_facing(facing: Vector2i, from_cell: Vector2i = Vector2i.ZERO) -> void:
	_last_applied_facing = facing
	_facing_from_cell = from_cell
	if not _is_moving and not _death_sequence_active and not _hit_reaction_active:
		_update_locomotion_visual(facing, false)
	if _facing_arrow != null and _show_facing_arrow():
		_facing_arrow.rotation_degrees = IsometricGrid.grid_facing_to_degrees(facing, from_cell)
	_sync_facing_arrow_visibility()


func _show_facing_arrow() -> bool:
	## OG frames encode facing for both factions — keep the debug arrow hidden.
	return false


func _sync_facing_arrow_visibility() -> void:
	if _facing_arrow == null:
		return
	if _is_dead or not _show_facing_arrow():
		_facing_arrow.visible = false
		return
	_facing_arrow.visible = _applied_position_state != PositionState.DOWN


func _uses_og_frames() -> bool:
	return team_id == Team.USA or team_id == Team.GERMANY


func _configure_team_visual() -> void:
	if _anim == null:
		return
	if _configured_team_id == team_id and _anim.sprite_frames != null:
		return
	_configured_team_id = team_id
	if team_id == Team.USA:
		_anim.sprite_frames = UsSoldierSpriteFrames.get_usa_sprite_frames()
	elif team_id == Team.GERMANY:
		_anim.sprite_frames = UsSoldierSpriteFrames.get_germany_sprite_frames()
	_anim.scale = _standing_sprite_scale()
	_anim.offset = TileSizeConfig.soldier_standing_sprite_offset()


func _update_locomotion_visual(step: Vector2i, walking: bool) -> void:
	if _anim == null or _death_sequence_active or _hit_reaction_active:
		return
	if _uses_og_frames():
		_play_locomotion(UsSoldierSpriteFrames.direction_from_step(step), walking)


func _play_locomotion(direction: String, walking: bool) -> void:
	if _anim.sprite_frames == null:
		return
	if walking and _locomotion_direction == direction and _locomotion_walking:
		if not _anim.is_playing():
			_anim.play("walk_%s" % direction)
		return
	if not walking and _locomotion_direction == direction and not _locomotion_walking:
		return
	_locomotion_direction = direction
	_locomotion_walking = walking

	var anim_name := "walk_%s" % direction
	if not _anim.sprite_frames.has_animation(anim_name):
		push_warning("Soldier: missing animation %s" % anim_name)
		return

	_anim.play(anim_name)
	if walking:
		return
	_anim.pause()
	_anim.frame = 0


## Survivable flinch. US uses hit_standing / hit_prone; never falls back to idle/walk frames.
func play_hit_reaction(threat_step: Vector2i, position_state: int = PositionState.UP) -> void:
	if not _uses_og_frames() or _death_sequence_active or _hit_reaction_active or _is_dead:
		return
	if _corpse_direction_locked:
		return

	_hit_reaction_active = true
	_hit_return_prone = position_state == PositionState.DOWN
	_death_direction = UsSoldierSpriteFrames.direction_from_threat(threat_step)
	_hit_semantic = _hit_semantic_for(position_state)
	_selection_marker.visible = false
	_apply_hit_reaction_scale(position_state)
	stop_movement()

	var anim_name := "%s_%s" % [_hit_semantic, _death_direction]
	if not _play_hit_animation(anim_name, position_state, false):
		_hit_reaction_active = false
		return


## Fatal hit → stance hit reaction → fall → dead. Never returns to idle.
func play_death_sequence(
	threat_step: Vector2i,
	position_state: int = PositionState.UP,
) -> void:
	if not _uses_og_frames() or _death_sequence_active or _corpse_direction_locked:
		return
	_hit_reaction_active = false
	_death_sequence_active = true
	_is_dead = true
	_death_direction = UsSoldierSpriteFrames.direction_from_threat(threat_step)
	_corpse_direction_locked = true
	_hit_semantic = _hit_semantic_for(position_state)
	_hit_return_prone = position_state == PositionState.DOWN
	_facing_arrow.visible = false
	_prone_marker.visible = false
	_selection_marker.visible = false
	## Keep the living stance scale for the hit reaction (corpse scale applies after fall).
	_apply_hit_reaction_scale(position_state)
	stop_movement()

	var anim_name := "%s_%s" % [_hit_semantic, _death_direction]
	if not _play_hit_animation(anim_name, position_state, true):
		## Missing hit frames must not invent idle; skip straight to fall if available.
		_play_animation("fall_%s" % _death_direction)


func _hit_semantic_for(position_state: int) -> String:
	## US verified families: standing/kneeling → AHTFA; prone → AHTLA.
	## German keeps legacy hit_* (GHTLA) until those families are wired.
	if team_id == Team.USA:
		if position_state == PositionState.DOWN:
			return "hit_prone"
		return "hit_standing"
	return "hit"


func _apply_hit_reaction_scale(position_state: int) -> void:
	_anim.position = Vector2.ZERO
	if position_state == PositionState.DOWN:
		_applied_position_state = PositionState.DOWN
		_anim.scale = _prone_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
	else:
		_applied_position_state = PositionState.UP
		_anim.scale = _standing_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_standing_sprite_offset()


func _play_hit_animation(anim_name: String, position_state: int, fatal: bool) -> bool:
	if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(anim_name):
		push_error(
			"Soldier: missing hit-reaction animation %s (team=%d soldier=%d stance=%s fatal=%s)"
			% [anim_name, team_id, soldier_id, PositionState.display_name(position_state), fatal]
		)
		_log_hit_reaction(anim_name, position_state, fatal, [], "MISSING_ANIMATION")
		return false

	var frame_count := _anim.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		push_error("Soldier: hit-reaction animation %s has zero frames" % anim_name)
		_log_hit_reaction(anim_name, position_state, fatal, [], "EMPTY_FRAMES")
		return false

	_anim.play(anim_name)
	_log_hit_reaction(anim_name, position_state, fatal, _ordered_frame_paths_for_log(), "PLAY")
	return true


func _on_anim_animation_finished() -> void:
	if not _uses_og_frames():
		return

	var anim_name := str(_anim.animation)

	if _hit_reaction_active and not _death_sequence_active:
		_finish_survivable_hit_reaction(anim_name)
		return

	if not _death_sequence_active:
		return

	if _is_hit_reaction_anim(anim_name):
		_log_hit_completion(anim_name, "→ fall_%s" % _death_direction)
		_play_animation("fall_%s" % _death_direction)
	elif anim_name.begins_with("fall_"):
		_log_hit_completion(anim_name, "→ dead_%s" % _death_direction)
		_finish_death_sequence()


func _finish_survivable_hit_reaction(anim_name: String) -> void:
	_hit_reaction_active = false
	var transition := "→ prone idle" if _hit_return_prone else "→ standing idle"
	_log_hit_completion(anim_name, transition)
	## Resume stance idle (paused walk frame). Never invent a substitute hit sprite.
	if _hit_return_prone:
		_applied_position_state = PositionState.DOWN
		_anim.scale = _prone_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
		_prone_marker.visible = true
	else:
		_applied_position_state = PositionState.UP
		_anim.scale = _standing_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_standing_sprite_offset()
		_prone_marker.visible = false
	_locomotion_walking = true ## force idle refresh
	_play_locomotion(_locomotion_direction if not _locomotion_direction.is_empty() else _death_direction, false)
	_sync_facing_arrow_visibility()


func _is_hit_reaction_anim(anim_name: String) -> bool:
	return anim_name.begins_with("hit_")


func _finish_death_sequence() -> void:
	_death_sequence_active = false
	_hit_reaction_active = false
	_apply_dead_visual(false)


func _show_dead_static(direction: String) -> void:
	_death_direction = direction
	_play_animation("dead_%s" % direction)
	_anim.pause()
	_anim.frame = 0


func _corpse_direction_for_state(state: SoldierState) -> String:
	if _corpse_direction_locked:
		return _death_direction
	return UsSoldierSpriteFrames.direction_from_step(state.facing_direction)


func _play_animation(anim_name: String) -> void:
	if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(anim_name):
		push_warning("Soldier: missing animation %s" % anim_name)
		return
	_anim.play(anim_name)


func _source_family_for_semantic(semantic: String) -> String:
	match semantic:
		"hit_standing":
			return "AHTFA"
		"hit_prone":
			return "AHTLA"
		"hit":
			return "GHTLA" if team_id == Team.GERMANY else "AHTLA"
		_:
			return "?"


func _ordered_frame_paths_for_log() -> Array[String]:
	var paths: Array[String] = []
	if team_id != Team.USA or _hit_semantic.is_empty() or _death_direction.is_empty():
		return paths
	var family_id := UsSoldierSpriteFrames.DB_FAMILY_USA
	var packed := AnimationDatabase.get_direction_frames(family_id, _hit_semantic, _death_direction)
	for path in packed:
		paths.append(str(path))
	return paths


func _log_hit_reaction(
	anim_name: String,
	position_state: int,
	fatal: bool,
	frame_paths: Array[String],
	status: String,
) -> void:
	if not DEBUG_HIT_REACTION:
		return
	var cam_rot := IsometricGrid.camera_direction_degrees()
	var world_dir := _death_direction
	var display_dir := AnimationDatabase.display_direction(world_dir, cam_rot)
	var fps := 0.0
	if _anim.sprite_frames != null and _anim.sprite_frames.has_animation(anim_name):
		fps = _anim.sprite_frames.get_animation_speed(anim_name)
	var meta := AnimationDatabase.resolve_anim_meta(
		UsSoldierSpriteFrames.DB_FAMILY_USA if team_id == Team.USA else UsSoldierSpriteFrames.DB_FAMILY_GERMANY,
		_hit_semantic,
	)
	if float(meta.get("fps", 0.0)) > 0.0:
		fps = float(meta.get("fps", fps))
	GameLog.log_system(
		"[HitReaction] status=%s semantic=%s family=%s anim=%s stance=%s fatal=%s world_dir=%s cam_rot=%d resolved_dir=%s fps=%.1f frames=%d"
		% [
			status,
			_hit_semantic,
			_source_family_for_semantic(_hit_semantic),
			anim_name,
			PositionState.display_name(position_state),
			fatal,
			world_dir,
			cam_rot,
			display_dir,
			fps,
			frame_paths.size(),
		]
	)
	if not frame_paths.is_empty():
		GameLog.log_system(
			"[HitReaction] ordered_frames=%s ... %s"
			% [frame_paths[0], frame_paths[frame_paths.size() - 1]]
		)


func _log_hit_completion(anim_name: String, transition: String) -> void:
	if not DEBUG_HIT_REACTION:
		return
	GameLog.log_system(
		"[HitReaction] complete anim=%s transition=%s"
		% [anim_name, transition]
	)
