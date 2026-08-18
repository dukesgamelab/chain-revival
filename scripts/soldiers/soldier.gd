class_name Soldier
extends Node2D
## Presentation only: sprites, selection, facing arrow, movement interpolation.
##
## Does NOT mutate SoldierState. Authoritative movement advances on simulation ticks;
## this node only lerps toward the current sim cell / next path cell.

const UsSoldierSpriteFrames := preload("res://scripts/soldiers/us_soldier_sprite_frames.gd")

## Fog-of-war presentation. Gameplay spotting is separate — this is display only.
enum FogVisual {
	REVEALED, ## Full sprite (in LOS / own side).
	GHOST, ## Translucent silhouette (1v1 intel when out of LOS).
	HIDDEN, ## Not drawn (2v2 fog).
}

const GHOST_MODULATE := Color(0.62, 0.72, 0.92, 0.58)

## OG art uses a 100×100 PNG canvas with transparency — an animation alignment grid,
## not the on-screen soldier height. Same scale for USA and Germany.
const OG_FRAME_SIZE := Vector2(100.0, 100.0)
const OG_SPRITE_SCALE := Vector2(1.6, 1.6)
## Prone/crawl art is already drawn lying down — do NOT squash Y (that flattened
## sprites and made roster markers look like dashes).

signal movement_step_reached(team_id: int, soldier_id: int, tile: Vector2i, step_delta: Vector2i)
signal movement_finished(team_id: int, soldier_id: int)
## Fired once when configured release frame is reached (presentation → gameplay hook).
signal grenade_release_reached(team_id: int, soldier_id: int)
## Fired when stand↔prone transition anim completes (clears pending presentation gate).
signal stance_transition_finished(team_id: int, soldier_id: int, target_position_state: int)
## Fired when a transition is interrupted; gameplay should drop pending_position_state.
signal stance_transition_cancelled(team_id: int, soldier_id: int)

var soldier_id: int = 1
var team_id: int = Team.USA

@export var move_speed := 95.0 / 3.0 ## Keep in sync with MovementPolicy.BASE_WORLD_SPEED

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
## World-facing anim letter for the static corpse (authoritative facing at death).
var _corpse_world_direction: String = "n"
## Selected dead_static family code from SoldierState (e.g. ADFUS). Stable across camera/sync.
var _death_sprite_family: String = ""
var _corpse_direction_locked: bool = false
var _dead_static_logged: bool = false
var _fog_visual: int = FogVisual.REVEALED
var _hit_reaction_active: bool = false
var _hit_semantic: String = ""
var _hit_return_prone: bool = false
var _throw_grenade_active: bool = false
var _throw_world_direction: String = "n"
var _throw_release_fired: bool = false
var _throw_return_prone: bool = false
var _fire_active: bool = false
var _fire_return_prone: bool = false
var _fire_semantic: String = "fire_standing"
var _fire_peek_side: int = CoverSystem.PeekSide.NONE
## Target cell for shooter→target fire facing (−999 = none).
var _fire_target_cell: Vector2i = Vector2i(-999, -999)
var _idle_peek_side: int = CoverSystem.PeekSide.NONE
var _played_idle_peek_side: int = CoverSystem.PeekSide.NONE
## Cover-relative corner cell for lean offset (OG BehindCorner geometry).
var _cover_corner_cell: Vector2i = Vector2i(-999, -999)
## Mirrored movement mode for corner lean run-factor (0.7 while Running).
var _presentation_movement_mode: int = MovementMode.RUN
var _fire_visual_shot_logged: bool = false
## Open standing/prone: hold aim_* pose while status is Aiming (between shots).
var _fire_aim_hold_active: bool = false
## Playing aim_standing (ASAPA/GSAPA) oneshot before aim_standing_hold.
var _fire_aim_enter_active: bool = false
## Last engaged target seen while aiming (presentation grace across clear→re-acquire).
var _aim_hold_last_target_team_id: int = -1
var _aim_hold_last_target_soldier_id: int = -1
## SimulationClock msec when is_engaged() last went false (−1 = currently engaged / never).
var _aim_hold_disengage_msec: int = -1
## At most one queued restart if a new shot arrives mid-sequence.
var _fire_restart_pending: bool = false
## Presentation-only corner cover phases (not authoritative combat state).
enum CornerPresPhase { NONE, IDLE, PEEKING_OUT, AIMING, FIRING, PEEKING_IN }
var _corner_phase: int = CornerPresPhase.NONE
var _corner_peek_side: int = CoverSystem.PeekSide.NONE
var _corner_semantic: String = ""
var _corner_fire_pending: bool = false
var _stance_transition_active: bool = false
var _stance_transition_semantic: String = ""
var _stance_transition_target: int = PositionState.UP
var _stance_transition_world_direction: String = "n"
## Presentation-only standing fidget (OG: rare oneshot, then back to held pose A).
var _idle_fidget_active: bool = false
var _idle_fidget_semantic: String = ""
var _idle_rng := RandomNumberGenerator.new()
## Seconds remaining until next fidget roll (−1 = inactive). Ticked in _process.
var _idle_wait_remaining_sec: float = -1.0
## Mirrored from SoldierState for idle pose selection (stress / hold-fire / post-shot).
var _presentation_stress: float = 0.0
var _presentation_fire_control: int = FireControlState.FIRE_AT_WILL
## Mirrored from SoldierState.is_stunned() — true while sim stun is active.
var _presentation_stunned: bool = false
## Stage 2 stun chain: knockdown → normal idle hold → recover.
enum StunPresPhase { NONE, KNOCKDOWN, HOLD, RECOVER }
var _stun_phase: int = StunPresPhase.NONE
var _stun_world_direction: String = "n"
## Seconds remaining on brief ADHPA/GDHPA kneel-aim hold after an open standing shot.
var _post_shot_crouch_remaining: float = 0.0

## When true, log hit-reaction resolution (semantic, family, directions, frames, FPS).
const DEBUG_HIT_REACTION := false
const DEBUG_THROW_GRENADE := false
const DEBUG_FIRE_ANIM := false
## TEMP: log arm/play/cancel so fidget timing is visible in the console.
const DEBUG_IDLE_STANDING := false
const DEBUG_STANCE_TRANSITION := false
const DEBUG_FACING := false
const DEBUG_DEAD_STATIC := false
## TEMP: diagnose aim-hold failure at camera 0°/180° — remove after fix.
const DEBUG_AIM_HOLD := true


## Cropped roster icons — index 0 = soldier 1 (1 mark), …, index 3 = soldier 4 (4 marks).
const DOT_TEXTURE_PATHS := [
	"res://assets/sprites/coc_soldiers/id_markers/DOT1.png",
	"res://assets/sprites/coc_soldiers/id_markers/DOT2.png",
	"res://assets/sprites/coc_soldiers/id_markers/DOT3.png",
	"res://assets/sprites/coc_soldiers/id_markers/DOT4.png",
]
const DTT_TEXTURE_PATHS := [
	"res://assets/sprites/coc_soldiers/id_markers/DTT1.png",
	"res://assets/sprites/coc_soldiers/id_markers/DTT2.png",
	"res://assets/sprites/coc_soldiers/id_markers/DTT3.png",
	"res://assets/sprites/coc_soldiers/id_markers/DTT4.png",
]
const ID_MARKER_SCALE := Vector2(2.0, 2.0)

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var _selection_marker: Polygon2D = $SelectionMarker
@onready var _id_marker: Sprite2D = $IdMarker
@onready var _name_label: Label = $NameLabel
@onready var _facing_arrow: Line2D = $FacingArrow
@onready var _dead_marker: Line2D = $DeadMarker
@onready var _prone_marker: Line2D = $ProneMarker

var _show_id_marker: bool = false
## Non-empty → show text overhead (AI / other players); local human uses DOT sprites instead.
var _id_label_text: String = ""
var _dot_textures: Array[Texture2D] = []
var _dtt_textures: Array[Texture2D] = []


func _ready() -> void:
	set_process(false)
	_idle_rng.randomize()
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_anim.centered = true
	_facing_arrow.position.y = TileSizeConfig.facing_arrow_y()
	_prone_marker.position.y = TileSizeConfig.prone_marker_y()
	## APRIS/GPRIS idle art replaces the old yellow prone rectangle indicator.
	_prone_marker.visible = false
	_dead_marker.position.y = TileSizeConfig.dead_marker_y()
	_configure_team_visual()
	_load_id_marker_textures()
	_configure_id_marker_node()
	_configure_name_label_node()
	_anim.animation_finished.connect(_on_anim_animation_finished)
	_anim.frame_changed.connect(_on_anim_frame_changed)


func _load_id_marker_textures() -> void:
	_dot_textures.clear()
	_dtt_textures.clear()
	for path in DOT_TEXTURE_PATHS:
		_dot_textures.append(load(path) as Texture2D)
	for path in DTT_TEXTURE_PATHS:
		_dtt_textures.append(load(path) as Texture2D)


func _configure_id_marker_node() -> void:
	if _id_marker == null:
		return
	_id_marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_id_marker.centered = true
	_id_marker.offset = Vector2.ZERO
	_id_marker.scale = ID_MARKER_SCALE
	_id_marker.modulate = Color.WHITE
	_id_marker.visible = false


func _configure_name_label_node() -> void:
	if _name_label == null:
		return
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.visible = false


## Map soldier_id (1–4) or roster index (0–3) → texture slot 0–3 (1–4 marks).
static func roster_marker_index(soldier_id: int) -> int:
	if soldier_id >= 1 and soldier_id <= 4:
		return soldier_id - 1
	return clampi(soldier_id, 0, 3)



func _blocks_action_override() -> bool:
	## Priority: death → stun chain → hit → throw → fire/corner → stance → idle.
	return (
		_death_sequence_active
		or _stun_phase != StunPresPhase.NONE
		or _hit_reaction_active
		or _throw_grenade_active
		or _fire_active
		or _corner_phase_blocks_locomotion()
		or _stance_transition_active
	)


func _corner_phase_blocks_locomotion() -> bool:
	return (
		_corner_phase == CornerPresPhase.PEEKING_OUT
		or _corner_phase == CornerPresPhase.AIMING
		or _corner_phase == CornerPresPhase.FIRING
		or _corner_phase == CornerPresPhase.PEEKING_IN
	)


## Apply authoritative gameplay state to this sprite (position, facing, selection).
## fire_aim_cell: engaged / Fire-At aim cell so hold facing matches play_fire.
func sync_from_state(
	state: SoldierState,
	is_selected: bool,
	fog_visual: int = FogVisual.REVEALED,
	show_id_marker: bool = false,
	idle_peek_side: int = CoverSystem.PeekSide.NONE,
	idle_corner_cell: Vector2i = Vector2i(-999, -999),
	id_label_text: String = "",
	fire_aim_cell: Vector2i = Vector2i(-999, -999),
) -> void:
	var previous_team := team_id
	soldier_id = state.soldier_id
	team_id = state.team_id
	_show_id_marker = show_id_marker
	_id_label_text = id_label_text
	_idle_peek_side = idle_peek_side
	_cover_corner_cell = idle_corner_cell
	if fire_aim_cell.x > -900:
		_fire_target_cell = fire_aim_cell
	_presentation_stress = state.stress
	_presentation_fire_control = state.fire_control_state
	_presentation_movement_mode = state.movement_mode
	if previous_team != team_id or _anim.sprite_frames == null:
		_configure_team_visual()
	_is_dead = state.is_dead
	if state.is_dead:
		state.ensure_death_sprite_family()
		_death_sprite_family = state.death_sprite_family
		_clear_stun_presentation()

	## Corner aim hold ends when authoritative peek geometry is lost.
	if (
		_corner_phase == CornerPresPhase.AIMING
		and (
			idle_peek_side == CoverSystem.PeekSide.NONE
			or idle_peek_side != _corner_peek_side
		)
	):
		_start_corner_peek_exit()

	## Death wins over stun presentation.
	if state.is_dead:
		stop_movement()
		visible = true
		_cover_corner_cell = Vector2i(-999, -999)
		_set_world_position_from_cell(state.grid_position)
		_facing_from_cell = state.grid_position
		_apply_facing(state.facing_direction, _facing_from_cell)
		_corpse_world_direction = UsSoldierSpriteFrames.direction_from_step(state.facing_direction)
		_show_dead_static(_corpse_world_direction)
		_refresh_id_marker(state)
		return

	## Stun chain: rising edge starts knockdown; falling edge starts recover.
	## While is_stunned(), stay in knockdown/prone-hold — never stand or crouch.
	var want_stunned := state.is_stunned()
	if want_stunned and _stun_phase == StunPresPhase.NONE:
		_enter_stun_presentation()
	elif want_stunned:
		_presentation_stunned = true
		## Re-assert normal idle hold if something knocked us out of stunned visuals.
		if _stun_phase == StunPresPhase.HOLD:
			if not _is_stun_hold_anim(str(_anim.animation)):
				_play_stun_hold_pose()
	elif (
		_stun_phase == StunPresPhase.KNOCKDOWN
		or _stun_phase == StunPresPhase.HOLD
		or _presentation_stunned
	):
		_presentation_stunned = false
		## Sim decides stand vs stay prone; never play hit/death (AHTBA) on recover.
		_end_stun_presentation(state.position_state)
	else:
		_presentation_stunned = false

	if _stun_phase != StunPresPhase.NONE:
		soldier_id = state.soldier_id
		team_id = state.team_id
		stop_movement()
		_set_world_position_from_cell(state.grid_position)
		_facing_from_cell = state.grid_position
		## Facing refresh must not restart knockdown / overwrite stun hold.
		_last_applied_facing = FacingDirection.normalize(state.facing_direction)
		_apply_fog_visual(fog_visual, is_selected)
		set_selected(is_selected)
		_refresh_id_marker(state)
		return

	if _blocks_action_override():
		soldier_id = state.soldier_id
		team_id = state.team_id
		_set_world_position_from_cell(state.grid_position)
		_apply_fog_visual(fog_visual, is_selected)
		_refresh_id_marker(state)
		## Corner CAS between shots must not block Stage 1 open aim hold.
		if (
			not _fire_active
			and _corner_phase == CornerPresPhase.AIMING
			and not _is_dead
			and not _presentation_stunned
		):
			_sync_fire_aim_hold(state)
		return

	_dead_marker.visible = false
	if state.is_moving:
		sync_movement_chase_from_state(state)
	elif _is_moving:
		## Presentation settle only (sim already stopped). Snap — never block aim hold
		## across camera rotates when world projection jumps.
		_path.clear()
		_path_index = 0
		_is_moving = false
		_set_world_position_from_cell(state.grid_position)
	else:
		_set_world_position_from_cell(state.grid_position)
	_facing_from_cell = state.grid_position
	## Aim hold before selection/idle locomotion so CIS cannot win the frame.
	_sync_fire_aim_hold(state)
	_apply_facing(state.facing_direction, _facing_from_cell)
	_apply_position_visual(state)
	_apply_fog_visual(fog_visual, is_selected)
	set_selected(is_selected)
	_refresh_id_marker(state)
	## Re-assert after facing — _apply_facing may have run before hold latched.
	_sync_fire_aim_hold(state)
	## Do not force walk=true here — sync_movement_chase_from_state already chose
	## walk vs idle based on remaining distance (avoids run-in-place on full sync).


func _set_world_position_from_cell(cell: Vector2i) -> void:
	_facing_from_cell = cell
	position = IsometricGrid.grid_to_world(cell) + _corner_lean_world_offset()


func _corner_lean_world_offset() -> Vector2:
	## Presentation-only lean toward the corner cell while corner phase is active.
	if _cover_corner_cell.x <= -999:
		return Vector2.ZERO
	var side := (
		_corner_peek_side
		if _corner_peek_side != CoverSystem.PeekSide.NONE
		else _idle_peek_side
	)
	if side == CoverSystem.PeekSide.NONE and _corner_phase == CornerPresPhase.NONE:
		return Vector2.ZERO
	if (
		_corner_phase == CornerPresPhase.NONE
		and side == CoverSystem.PeekSide.NONE
	):
		return Vector2.ZERO
	## Active lean: any corner phase, or CIS idle via idle_peek.
	var blend := _corner_lean_blend()
	if blend <= 0.001:
		return Vector2.ZERO
	var tiles := GameplayPolicies.fire_anim.corner_offset_tiles_for_side(side)
	if tiles <= 0.0:
		return Vector2.ZERO
	if _presentation_movement_mode == MovementMode.RUN and (_is_moving or _locomotion_walking):
		tiles *= GameplayPolicies.fire_anim.corner_offset_run_factor
	var step := UsSoldierSpriteFrames.snap_step_to_eight_way(_cover_corner_cell - _facing_from_cell)
	if step == Vector2i.ZERO:
		return Vector2.ZERO
	var one_tile := IsometricGrid.grid_facing_to_screen(step, _facing_from_cell)
	return one_tile * tiles * blend


func _corner_lean_blend() -> float:
	## Ease with peek enter/exit; full lean while idle/aim/fire.
	match _corner_phase:
		CornerPresPhase.NONE:
			## Standing CIS idle without an active phase still leans.
			return 1.0 if _idle_peek_side != CoverSystem.PeekSide.NONE else 0.0
		CornerPresPhase.IDLE, CornerPresPhase.AIMING, CornerPresPhase.FIRING:
			return 1.0
		CornerPresPhase.PEEKING_OUT, CornerPresPhase.PEEKING_IN:
			if _anim == null or _anim.sprite_frames == null:
				return 0.5
			var anim_name := str(_anim.animation)
			if not _anim.sprite_frames.has_animation(anim_name):
				return 0.5
			var count := maxi(_anim.sprite_frames.get_frame_count(anim_name), 1)
			var t := clampf(float(_anim.frame + 1) / float(count), 0.0, 1.0)
			if _corner_phase == CornerPresPhase.PEEKING_IN:
				return 1.0 - t
			return t
		_:
			return 0.0


func _refresh_corner_lean_offset() -> void:
	## Keep lean applied after phase/frame changes without snapping the grid cell.
	if _is_moving and _has_active_chase():
		return
	position = IsometricGrid.grid_to_world(_facing_from_cell) + _corner_lean_world_offset()


func _refresh_id_marker(state: SoldierState) -> void:
	if _id_marker != null:
		_id_marker.visible = false
	if _name_label != null:
		_name_label.visible = false
	if state == null or state.is_dead or _fog_visual == FogVisual.HIDDEN:
		return
	var crouched := state.position_state == PositionState.DOWN
	var label_y := TileSizeConfig.id_marker_y(crouched)
	## Other players (AI / remote): text name. Local human: DOT sprites (revealed only).
	if not _id_label_text.is_empty():
		if _name_label == null:
			return
		_name_label.text = _id_label_text
		_name_label.position = Vector2(-64.0, label_y - 8.0)
		_name_label.size = Vector2(128.0, 16.0)
		_name_label.visible = true
		return
	if not _show_id_marker or _fog_visual == FogVisual.GHOST or _id_marker == null:
		return
	if _dot_textures.is_empty() or _dtt_textures.is_empty():
		_load_id_marker_textures()
	var idx := roster_marker_index(state.soldier_id)
	## Always use DOT* roster icons. DTT* are horizontally flattened OG variants that
	## read as "dashes" once prone art is shown at full scale.
	if idx < 0 or idx >= _dot_textures.size() or _dot_textures[idx] == null:
		return
	_id_marker.texture = _dot_textures[idx]
	_id_marker.scale = ID_MARKER_SCALE
	_id_marker.offset = Vector2.ZERO
	_id_marker.modulate = Color.WHITE
	_id_marker.position = Vector2(0.0, label_y)
	_id_marker.visible = true


func _apply_spotted_visual(is_selected: bool, is_spotted: bool) -> void:
	_apply_fog_visual(FogVisual.REVEALED if is_spotted else FogVisual.GHOST, is_selected)


## Presentation fog: revealed / ghost / hidden. Does not affect gameplay LOS.
func apply_fog_visual(mode: int, is_selected: bool = false) -> void:
	_apply_fog_visual(mode, is_selected)


func _apply_fog_visual(mode: int, is_selected: bool = false) -> void:
	_fog_visual = mode
	if _is_dead:
		visible = true
		return
	match mode:
		FogVisual.HIDDEN:
			visible = false
			if _id_marker != null:
				_id_marker.visible = false
			if _name_label != null:
				_name_label.visible = false
			return
		FogVisual.GHOST:
			visible = true
			_anim.modulate = GHOST_MODULATE
			## Ghosts are intel silhouettes — no facing chrome; name labels still show.
			if _facing_arrow != null:
				_facing_arrow.visible = false
			if _prone_marker != null:
				_prone_marker.visible = false
			if _id_marker != null:
				_id_marker.visible = false
			if _name_label != null and not _id_label_text.is_empty():
				_name_label.text = _id_label_text
				_name_label.visible = true
			elif _name_label != null:
				_name_label.visible = false
		_:
			visible = true
			if is_selected:
				_anim.modulate = Color(1.14, 1.14, 1.08, 1.0)
			else:
				_anim.modulate = Color.WHITE


## Fog-of-war only — used by Main on combat scans to avoid full sync_from_state.
func apply_spotting_only(is_selected: bool, fog_visual: int) -> void:
	_apply_fog_visual(fog_visual, is_selected)
	## Keep name labels in sync when fog flips without a full state sync.
	if _name_label == null:
		return
	if (
		_is_dead
		or fog_visual == FogVisual.HIDDEN
		or _id_label_text.is_empty()
	):
		_name_label.visible = false
		return
	_name_label.text = _id_label_text
	_name_label.visible = true


## Cheap stress / hold-fire idle pose update without full sync_from_state.
func apply_idle_pose_inputs(
	stress: float,
	fire_control_state: int,
	state: SoldierState = null,
	fire_aim_cell: Vector2i = Vector2i(-999, -999),
) -> void:
	var prev_semantic := _idle_standing_semantic()
	_presentation_stress = stress
	_presentation_fire_control = fire_control_state
	if fire_aim_cell.x > -900:
		_fire_target_cell = fire_aim_cell
	## Combat-tick light refresh must re-assert aim — full sync_from_state is rare.
	if state != null and not _is_dead and not _presentation_stunned:
		_sync_fire_aim_hold(state)
	if (
		_is_dead
		or _presentation_stunned
		or _stun_phase != StunPresPhase.NONE
		or _blocks_action_override()
		or _is_moving
		or _fire_aim_hold_active
		or _fire_aim_enter_active
	):
		return
	if _applied_position_state == PositionState.DOWN:
		return
	var next_semantic := _idle_standing_semantic()
	if (
		next_semantic == prev_semantic
		and str(_anim.animation).begins_with("%s_" % next_semantic)
	):
		return
	_locomotion_walking = true
	var dir := _locomotion_direction
	if dir.is_empty():
		dir = UsSoldierSpriteFrames.direction_from_step(_last_applied_facing)
	_play_locomotion(dir if not dir.is_empty() else "n", false)


func set_selected(is_selected: bool) -> void:
	## Red diamond is reserved for the run-to destination overlay — never under the soldier.
	_selection_marker.visible = false
	if _is_dead or _blocks_action_override():
		return
	## Aim owns the pose — selection refresh must not route through idle/corner CIS.
	if _fire_aim_hold_active or _fire_aim_enter_active:
		return
	if not _is_moving:
		_update_locomotion_visual(_last_applied_facing, false)


func _apply_dead_visual(_is_selected: bool) -> void:
	_applied_position_state = PositionState.DOWN
	_facing_arrow.visible = false
	_prone_marker.visible = false
	_dead_marker.visible = false
	_selection_marker.visible = false
	if _id_marker != null:
		_id_marker.visible = false
	if _name_label != null:
		_name_label.visible = false
	_anim.scale = _prone_sprite_scale()
	_anim.position = Vector2.ZERO
	_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
	## Prefer authoritative world facing for the static corpse; fall used threat dir.
	if _corpse_world_direction.is_empty():
		_corpse_world_direction = UsSoldierSpriteFrames.direction_from_step(_last_applied_facing)
	_show_dead_static(_corpse_world_direction)
	_anim.modulate = Color.WHITE


func _apply_position_visual(state: SoldierState) -> void:
	## Stun chain owns posture/scale until recover finishes.
	if _stun_phase != StunPresPhase.NONE:
		_applied_position_state = PositionState.DOWN
		_facing_arrow.visible = false
		return
	## Transition anim owns applied stance until it finishes.
	if _stance_transition_active:
		return
	## Pending means a stance order will play this frame / is in flight — don't snap past it.
	if state != null and state.pending_position_state >= 0:
		return
	if not _is_dead and state.position_state == _applied_position_state:
		return
	_applied_position_state = state.position_state
	_anim.position = Vector2.ZERO
	if state.position_state == PositionState.DOWN:
		_anim.scale = _prone_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
		_prone_marker.visible = false
	else:
		_anim.scale = _standing_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_standing_sprite_offset()
		_prone_marker.visible = false
	_sync_facing_arrow_visibility()


func _standing_sprite_scale() -> Vector2:
	return OG_SPRITE_SCALE * TileSizeConfig.SOLDIER_SCALE


func _prone_sprite_scale() -> Vector2:
	## Same uniform scale as standing — APRNA/APMOA/idle_prone frames supply the pose.
	return _standing_sprite_scale()


func is_moving() -> bool:
	return _is_moving


## Presentation chase fingerprint for stuck-movement diagnostics.
func debug_chase_fingerprint() -> Dictionary:
	var dest := Vector2i(-999, -999)
	if _has_active_chase():
		dest = _path[_path_index]
	return {
		"view_moving": _is_moving,
		"path_len": _path.size(),
		"path_index": _path_index,
		"dest_cell": dest,
		"chase_active": _has_active_chase(),
		"dist_to_target": position.distance_to(_move_target_world),
		"fire_active": _fire_active,
		"stance_transition": _stance_transition_active,
	}


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
	if was_moving:
		_interrupt_standing_idle_for_action()
	if was_moving and _uses_og_frames() and not _blocks_action_override():
		## Idle arm keeps _process on for the standing fidget wait.
		_play_locomotion(_locomotion_direction, false)
	elif _idle_wait_remaining_sec > 0.0 or _idle_fidget_active:
		## Halt/stuck-heal must not freeze an already-armed fidget countdown.
		set_process(true)
	else:
		set_process(false)


func _finish_presentation_move() -> void:
	## Arrived at the final chase cell after sim already cleared is_moving.
	if not _is_moving:
		return
	_is_moving = false
	_path.clear()
	_path_index = 0
	if _uses_og_frames() and not _blocks_action_override():
		## Idle arm / ensure keeps _process on for the standing fidget wait.
		_update_locomotion_visual(_last_applied_facing, false)
	elif _idle_wait_remaining_sec > 0.0 or _idle_fidget_active:
		set_process(true)
	else:
		set_process(false)


func follow_path(path: Array[Vector2i], speed_multiplier: float = 1.0) -> void:
	## Presentation-only path chase. Authoritative grid_position advances on sim ticks.
	_interrupt_standing_idle_for_action()
	_cancel_stance_transition_visual(false)
	## Movement cancels corner peek/aim/fire presentation immediately.
	_cancel_fire_visual(false)
	_clear_corner_presentation(false)
	if _is_dead or _blocks_action_override() or path.size() <= 1:
		return

	_speed_multiplier = speed_multiplier
	_path = path
	_path_index = 1
	_is_moving = true
	_previous_grid_pos = _path[0]
	position = IsometricGrid.grid_to_world(_path[0])
	## Chase the next authoritative cell; sync_from_state keeps this aligned with sim.
	_move_target_world = IsometricGrid.grid_to_world(_path[_path_index])
	var first_step := _path[1] - _path[0]
	_apply_facing(FacingDirection.from_step(first_step), _previous_grid_pos)
	_update_locomotion_visual(first_step, true)
	set_process(true)


func _process(delta: float) -> void:
	## Standing fidget wait is presentation-only and must tick even when not translating.
	_tick_standing_idle_wait(delta)
	_tick_post_shot_crouch(delta)
	_maybe_arm_standing_idle_timer()
	if not _is_moving or _is_dead or _blocks_action_override():
		var idle_work_active := (
			_idle_wait_remaining_sec > 0.0
			or _idle_fidget_active
			or _post_shot_crouch_remaining > 0.0
		)
		if not idle_work_active and not _is_moving:
			set_process(false)
		return

	var to_target := _move_target_world - position
	var distance := to_target.length()
	## Only play walk while still chasing a sim path cell. After sim finishes we clear
	## _path and settle to the final cell — do not keep looping the run anim in place.
	var chasing_path := _path_index < _path.size() and not _path.is_empty()

	if distance <= 0.001:
		position = _move_target_world
		if not chasing_path:
			_finish_presentation_move()
		else:
			## Arrived early at the next sim cell — pause run anim (no run-in-place).
			var step_delta := _path[_path_index] - _previous_grid_pos
			_apply_facing(FacingDirection.from_step(step_delta), _previous_grid_pos)
			_update_locomotion_visual(step_delta, false)
		return

	if chasing_path:
		var step_delta := _path[_path_index] - _previous_grid_pos
		_apply_facing(FacingDirection.from_step(step_delta), _previous_grid_pos)
		_update_locomotion_visual(step_delta, true)

	var move_amount := move_speed * _speed_multiplier * delta
	if move_amount >= distance:
		position = _move_target_world
		if not chasing_path:
			_finish_presentation_move()
	else:
		position += to_target.normalized() * move_amount


## Align visual chase target with authoritative simulation state (presentation only).
func sync_movement_chase_from_state(state: SoldierState) -> void:
	if state == null or _is_dead or _blocks_action_override():
		return
	_speed_multiplier = state.move_speed_mult if state.move_speed_mult > 0.0 else _speed_multiplier
	if state.is_moving and state.current_path.size() > state.path_index and state.path_index > 0:
		_interrupt_standing_idle_for_action()
		_path = state.current_path.duplicate()
		_path_index = state.path_index
		_previous_grid_pos = state.grid_position
		_move_target_world = IsometricGrid.grid_to_world(state.current_path[state.path_index])
		_is_moving = true
		var step_delta := state.current_path[state.path_index] - state.grid_position
		_apply_facing(FacingDirection.from_step(step_delta), state.grid_position)
		## Only play run while actually translating — early arrivals stay idle (no run-in-place).
		var need_translate := position.distance_to(_move_target_world) > 0.5
		_update_locomotion_visual(step_delta, need_translate)
		## Depth via parent DepthSorted y_sort only — do not set z_index from Y
		## (different z_index among siblings disables Y-sort vs walls).
		set_process(true)
		return
	## Path finished in sim — clear path chase and settle onto the final cell, then idle.
	_path.clear()
	_path_index = 0
	_move_target_world = IsometricGrid.grid_to_world(state.grid_position)
	if position.distance_to(_move_target_world) <= 0.5:
		position = _move_target_world
		_finish_presentation_move()
	else:
		## Settle lerp — never leave the run loop playing while sliding to the cell.
		_is_moving = true
		_update_locomotion_visual(_last_applied_facing, false)
		set_process(true)


func _has_active_chase() -> bool:
	return not _path.is_empty() and _path_index < _path.size()


func _apply_facing(facing: Vector2i, from_cell: Vector2i = Vector2i.ZERO) -> void:
	var step := facing
	if _fire_aim_hold_active or _fire_aim_enter_active:
		step = _resolve_fire_facing_step(facing, _fire_target_cell)
	if step == Vector2i.ZERO:
		step = FacingDirection.normalize(facing)
	var changed := step != _last_applied_facing
	if changed and not _is_moving:
		_interrupt_standing_idle_for_action()
	elif (
		not _is_moving
		and _idle_fidget_active
		and _idle_peek_side != _played_idle_peek_side
	):
		_interrupt_standing_idle_for_action()
	_commit_sprite_facing_from_step(step, from_cell)
	if not _is_moving and not _blocks_action_override():
		_update_locomotion_visual(step, false)
	if _facing_arrow != null and _show_facing_arrow():
		_facing_arrow.rotation_degrees = IsometricGrid.grid_facing_to_degrees(_last_applied_facing, from_cell)
	_sync_facing_arrow_visibility()
	if changed:
		_log_facing_debug("APPLY")


## Manual / debug validation snapshot for 8-way facing + camera remap.
func dump_facing_validation() -> Dictionary:
	var world := FacingDirection.normalize(_last_applied_facing)
	var cam := _presentation_camera_degrees()
	var anim_dir := UsSoldierSpriteFrames.direction_from_step(world)
	var display_dir := AnimationDatabase.display_direction(anim_dir, cam)
	var anim_name := str(_anim.animation) if _anim != null else ""
	return {
		"world_facing": world,
		"direction_name": FacingDirection.direction_name(world),
		"camera_rotation": cam,
		"anim_suffix_world": FacingDirection.to_anim_suffix(world),
		"resolved_anim_direction": display_dir,
		"active_animation": anim_name,
	}


func _log_facing_debug(status: String) -> void:
	if not DEBUG_FACING:
		return
	var info := dump_facing_validation()
	GameLog.log_system(
		"facing | %s | world=%s %s | cam=%d | anim_dir=%s | display=%s | anim=%s"
		% [
			status,
			info.world_facing,
			info.direction_name,
			info.camera_rotation,
			info.anim_suffix_world,
			info.resolved_anim_direction,
			info.active_animation,
		]
	)


func _show_facing_arrow() -> bool:
	## OG frames encode facing for both factions — keep the debug arrow hidden.
	return false


func _sync_facing_arrow_visibility() -> void:
	if _facing_arrow == null:
		return
	if (
		_is_dead
		or not _show_facing_arrow()
		or _fog_visual == FogVisual.GHOST
		or _fog_visual == FogVisual.HIDDEN
	):
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
	if _anim == null or _blocks_action_override():
		return
	if _uses_og_frames():
		_play_locomotion(_world_direction_from_step(step), walking)


func _play_locomotion(direction: String, walking: bool) -> void:
	if _anim.sprite_frames == null:
		return
	## Presentation-only: prone locomotion uses crawl_* (APMOA/GPMOA). No root motion.
	## `direction` is world letter; sprites use camera-remapped display letter.
	if _fire_active and not walking:
		_locomotion_direction = direction
		_locomotion_walking = false
		return
	if (_fire_aim_hold_active or _fire_aim_enter_active) and not walking:
		_clear_fire_aim_hold(false, "locomotion_stale_hold")
	_clear_stale_open_fire_pose()
	if DEBUG_AIM_HOLD and (_fire_aim_hold_active or _fire_aim_enter_active) and walking:
		GameLog.log_system(
			(
				"[AIM_HOLD] phase=STOMP_WALK soldier=%d rot_idx=%d facet_deg=%d "
				+ "dir=%s anim_before=%s"
			)
			% [
				soldier_id,
				IsometricGrid.current_view_rotation,
				IsometricGrid.facet_camera_direction_degrees(),
				direction,
				str(_anim.animation) if _anim != null else "",
			]
		)
	var move_prefix := _locomotion_move_prefix()
	var display_dir := _idle_display_direction(direction)
	if walking and _locomotion_direction == direction and _locomotion_walking:
		## Do not restart crawl/walk while stance, logical anim, and facing are unchanged.
		if str(_anim.animation).begins_with("%s_" % move_prefix):
			if not _anim.is_playing():
				_anim.play("%s_%s" % [move_prefix, display_dir])
			return
	if not walking and _locomotion_direction == direction and not _locomotion_walking:
		## Stun owns the pose — never keep standing idle / fidget / aim hold.
		if _presentation_stunned:
			pass
		## Keep an in-flight standing fidget until it finishes or is cancelled.
		elif _idle_fidget_active:
			if (
				walking
				or _locomotion_direction != direction
				or _idle_peek_side != _played_idle_peek_side
			):
				_interrupt_standing_idle_for_action()
			else:
				return
		## Already stationary in this world facing — keep current idle pose
		## unless peek side changed or we still need to start the correct idle.
		elif _applied_position_state != PositionState.DOWN:
			var idle_semantic := _idle_standing_semantic()
			var idle_anim_name := "%s_%s" % [idle_semantic, display_dir]
			if (
				_idle_peek_side == _played_idle_peek_side
				and str(_anim.animation) == idle_anim_name
			):
				## Sync/facing refresh must not drop a stopped idle timer.
				if idle_semantic == "idle_standing":
					_ensure_standing_idle_timer()
				elif idle_semantic == "idle_crouch":
					_cancel_standing_idle(false)
				return
		elif (
			not _presentation_stunned
			and _applied_position_state == PositionState.DOWN
		):
			var prone_anim_name := "idle_prone_%s" % display_dir
			if (
				_anim.sprite_frames.has_animation(prone_anim_name)
				and str(_anim.animation) == prone_anim_name
			):
				return
			if not _anim.sprite_frames.has_animation(prone_anim_name):
				var crawl_name := "%s_%s" % [_locomotion_move_prefix(), display_dir]
				if str(_anim.animation) == crawl_name:
					return

	if walking:
		_interrupt_standing_idle_for_action()

	_locomotion_direction = direction
	_locomotion_walking = walking

	if walking:
		var move_name := "%s_%s" % [move_prefix, display_dir]
		if not _anim.sprite_frames.has_animation(move_name) and move_prefix == "crawl":
			## Fallback if a family still has an empty crawl stub.
			move_name = "walk_%s" % display_dir
		if not _anim.sprite_frames.has_animation(move_name):
			push_warning("Soldier: missing animation %s" % move_name)
			return
		_anim.play(move_name)
		return

	## Stationary: stunned hold, prone idle, or standing open/corner CIS idle.
	if (
		_presentation_stunned
		and _stun_phase != StunPresPhase.KNOCKDOWN
		and _stun_phase != StunPresPhase.RECOVER
	):
		_stun_world_direction = direction if not direction.is_empty() else _stun_world_direction
		_play_stun_hold_pose()
		return
	if _applied_position_state == PositionState.DOWN:
		_play_idle_prone(direction)
		return

	_play_idle_standing(direction)


func _locomotion_move_prefix() -> String:
	## Authoritative stance may already be committed; presentation uses applied stance.
	if _applied_position_state == PositionState.DOWN:
		return "crawl"
	return "walk"


## Presentation camera for soldier sprites — same facet cam walls/windows use.
func _presentation_camera_degrees() -> int:
	return IsometricGrid.facet_camera_direction_degrees()


## Walk / fire / aim share one pipeline: grid step → world letter → camera display suffix.
func _world_direction_from_step(step: Vector2i) -> String:
	var letter := UsSoldierSpriteFrames.direction_from_step(step)
	return letter if not letter.is_empty() else "n"


func _body_world_direction() -> String:
	var from_facing := _world_direction_from_step(_last_applied_facing)
	if not from_facing.is_empty():
		return from_facing
	return _locomotion_direction if not _locomotion_direction.is_empty() else "n"


## Authoritative world letter for open standing idle + fidgets (matches held ABRLA pose).
func _standing_idle_world_direction() -> String:
	return _world_direction_from_step(_last_applied_facing)


func _display_direction_for_world(world_direction: String) -> String:
	return AnimationDatabase.display_direction(
		world_direction.to_lower(),
		_presentation_camera_degrees(),
	)


func _idle_display_direction(world_direction: String) -> String:
	return _display_direction_for_world(world_direction)


func _sprite_anim_name(semantic: String, world_direction: String) -> String:
	return "%s_%s" % [semantic, _display_direction_for_world(world_direction)]


func _commit_sprite_facing_from_step(step: Vector2i, from_cell: Vector2i = Vector2i.ZERO) -> void:
	if step == Vector2i.ZERO:
		step = FacingDirection.NORTH
	_facing_from_cell = from_cell
	_last_applied_facing = FacingDirection.from_step(step)
	_locomotion_direction = _world_direction_from_step(step)


func _commit_combat_facing(
	facing_direction: Vector2i,
	target_cell: Vector2i,
	from_cell: Vector2i = Vector2i(-999, -999),
) -> Vector2i:
	if from_cell.x > -900:
		_facing_from_cell = from_cell
	var step := _resolve_fire_facing_step(facing_direction, target_cell)
	_commit_sprite_facing_from_step(step, _facing_from_cell)
	return step


func _remap_animation_preserving_progress(anim_name: String, force_pause: bool = false) -> bool:
	if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(anim_name):
		return false
	if str(_anim.animation) == anim_name:
		return true
	var frame := _anim.frame
	var progress := _anim.frame_progress
	var was_playing := _anim.is_playing()
	_anim.play(anim_name)
	var max_frame := maxi(_anim.sprite_frames.get_frame_count(anim_name) - 1, 0)
	_anim.frame = mini(frame, max_frame)
	_anim.frame_progress = progress
	if force_pause or not was_playing:
		_anim.pause()
	return true


func _idle_standing_semantic() -> String:
	return GameplayPolicies.idle_anim.semantic_for(
		_idle_peek_side,
		_applied_position_state,
		_presentation_stress,
		_presentation_fire_control,
		_post_shot_crouch_remaining > 0.0,
	)


func _idle_source_family() -> String:
	var want_crouch := GameplayPolicies.idle_anim.should_use_crouch(
		_applied_position_state,
		_idle_peek_side,
		_presentation_stress,
		_presentation_fire_control,
		_post_shot_crouch_remaining > 0.0,
	)
	return GameplayPolicies.idle_anim.source_family_for(
		team_id, _idle_peek_side, _applied_position_state, want_crouch
	)


func _prone_idle_source_family() -> String:
	return "GPRIS" if team_id == Team.GERMANY else "APRIS"


func _play_idle_standing(world_direction: String) -> void:
	var display_dir := _idle_display_direction(world_direction)
	var semantic := _idle_standing_semantic()
	var anim_name := "%s_%s" % [semantic, display_dir]
	if not _anim.sprite_frames.has_animation(anim_name):
		## Fall back: crouch → standing; corner → standing.
		if semantic != "idle_standing":
			semantic = "idle_standing"
			anim_name = "%s_%s" % [semantic, display_dir]
	if not _anim.sprite_frames.has_animation(anim_name):
		push_error(
			"Soldier: missing idle animation %s (team=%d soldier=%d family=%s)"
			% [anim_name, team_id, soldier_id, _idle_source_family()]
		)
		_log_idle_standing(anim_name, "MISSING_ANIMATION")
		return
	var frame_count := _anim.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		push_error("Soldier: idle animation %s has zero frames" % anim_name)
		_log_idle_standing(anim_name, "EMPTY_FRAMES")
		return
	## Already on the held standing / crouch / CIS pose — do not restart the wait timer.
	if str(_anim.animation) == anim_name and not _idle_fidget_active:
		_played_idle_peek_side = _idle_peek_side
		if semantic == "idle_standing":
			if _anim.is_playing():
				_anim.pause()
				_anim.frame = 0
			_ensure_standing_idle_timer()
			return
		if semantic == "idle_crouch":
			## ADHPA/GDHPA A–B loop — keep playing; no fidgets while kneeling.
			_cancel_standing_idle(false)
			if not _anim.is_playing():
				_anim.play(anim_name)
			return
		if semantic.begins_with("corner_idle_"):
			_corner_phase = CornerPresPhase.IDLE
			_corner_peek_side = _idle_peek_side
			if frame_count <= 1 and _anim.is_playing():
				_anim.pause()
				_anim.frame = 0
			_refresh_corner_lean_offset()
			return
	_anim.play(anim_name)
	if semantic == "idle_standing":
		## Held ABRLA/GBRLA frame A — never loop continuous idle.
		_anim.pause()
		_anim.frame = 0
		if _corner_phase == CornerPresPhase.IDLE:
			_clear_corner_presentation(false)
		_played_idle_peek_side = _idle_peek_side
		## Facing/camera remaps must not reset an already-running wait.
		_ensure_standing_idle_timer()
		set_process(true)
		_log_idle_standing(anim_name, "HOLD_POSE")
		return
	if semantic == "idle_crouch":
		## Kneel-aim loop (ADHPA/GDHPA) — no fidgets while crouched.
		_cancel_standing_idle(false)
		if _corner_phase == CornerPresPhase.IDLE:
			_clear_corner_presentation(false)
		_played_idle_peek_side = _idle_peek_side
		_log_idle_standing(anim_name, "LOOP_CROUCH")
		return
	if semantic.begins_with("corner_idle_"):
		_cancel_standing_idle(false)
		_corner_phase = CornerPresPhase.IDLE
		_corner_peek_side = _idle_peek_side
		_corner_semantic = semantic
		if frame_count <= 1:
			_anim.pause()
			_anim.frame = 0
		_refresh_corner_lean_offset()
	elif _corner_phase == CornerPresPhase.IDLE:
		_clear_corner_presentation(false)
	_played_idle_peek_side = _idle_peek_side
	_log_idle_standing(anim_name, "PLAY")


func _play_idle_prone(world_direction: String) -> void:
	_interrupt_standing_idle_for_action()
	var display_dir := _idle_display_direction(world_direction)
	var anim_name := "idle_prone_%s" % display_dir
	if _anim.sprite_frames.has_animation(anim_name):
		var frame_count := _anim.sprite_frames.get_frame_count(anim_name)
		if frame_count <= 0:
			push_error("Soldier: idle_prone animation %s has zero frames" % anim_name)
			return
		## One-frame APRIS/GPRIS hold — do not restart on refresh.
		if str(_anim.animation) == anim_name:
			if _anim.is_playing() and frame_count <= 1:
				_anim.pause()
				_anim.frame = 0
			return
		_anim.play(anim_name)
		if frame_count <= 1:
			_anim.pause()
			_anim.frame = 0
		_log_stance_transition(anim_name, "IDLE_PRONE")
		return
	## Legacy fallback if DB entry missing: paused first walk frame.
	var prone_idle := "walk_%s" % world_direction
	if not _anim.sprite_frames.has_animation(prone_idle):
		push_warning("Soldier: missing animation %s" % prone_idle)
		return
	_anim.play(prone_idle)
	_anim.pause()
	_anim.frame = 0


## Preserve throw/fire/idle/stance progress across camera rotation; remaps visual direction only.
func refresh_action_visual_for_camera() -> void:
	if _anim == null or _anim.sprite_frames == null:
		return
	if _is_dead and not _death_sequence_active:
		_remap_dead_for_camera()
		return
	if _throw_grenade_active:
		_remap_throw_for_camera()
		return
	if _fire_active:
		_remap_fire_for_camera()
		return
	if (
		_corner_phase == CornerPresPhase.PEEKING_OUT
		or _corner_phase == CornerPresPhase.AIMING
		or _corner_phase == CornerPresPhase.PEEKING_IN
	):
		_remap_corner_presentation_for_camera()
		return
	if _stance_transition_active:
		_remap_stance_transition_for_camera()
		return
	if _hit_reaction_active or _death_sequence_active:
		_remap_hit_or_fall_for_camera()
		return
	if _stun_phase != StunPresPhase.NONE:
		_remap_stun_for_camera()
		return
	if _idle_fidget_active:
		_remap_standing_idle_fidget_for_camera()
		return
	if _fire_aim_hold_active or _fire_aim_enter_active:
		_remap_fire_aim_hold_for_camera()
		return
	if _blocks_action_override():
		return
	if _is_moving or _locomotion_walking:
		_remap_locomotion_for_camera()
		return
	if _applied_position_state == PositionState.DOWN:
		_remap_idle_prone_for_camera()
		return
	_remap_idle_standing_for_camera()


func _remap_locomotion_for_camera() -> void:
	var world_dir := _body_world_direction()
	var anim_name := _sprite_anim_name(_locomotion_move_prefix(), world_dir)
	if not _remap_animation_preserving_progress(anim_name):
		if _locomotion_move_prefix() == "crawl":
			_remap_animation_preserving_progress(_sprite_anim_name("walk", world_dir))


func _remap_fire_aim_hold_for_camera() -> void:
	if not _fire_aim_hold_active:
		return
	var world_dir := _body_world_direction()
	if _fire_aim_enter_active:
		var enter_anim := _sprite_anim_name("aim_standing", world_dir)
		if _anim.sprite_frames != null and _anim.sprite_frames.has_animation(enter_anim):
			_remap_animation_preserving_progress(enter_anim)
		return
	var hold_semantic := _aim_hold_semantic(_applied_position_state)
	var hold_anim := _sprite_anim_name(hold_semantic, world_dir)
	if not _anim.sprite_frames.has_animation(hold_anim):
		return
	var aim_frame := _fire_aim_hold_frame(hold_anim)
	if str(_anim.animation) == hold_anim and not _anim.is_playing() and _anim.frame == aim_frame:
		return
	_anim.play(hold_anim)
	_anim.pause()
	_anim.frame = aim_frame


func _remap_hit_or_fall_for_camera() -> void:
	var world_dir := _death_direction if not _death_direction.is_empty() else "n"
	var display_dir := _idle_display_direction(world_dir)
	var anim_name := str(_anim.animation)
	var semantic := ""
	if anim_name.begins_with("fall_"):
		semantic = "fall"
	elif not _hit_semantic.is_empty() and anim_name.begins_with("%s_" % _hit_semantic):
		semantic = _hit_semantic
	elif anim_name.begins_with("hit_"):
		## hit_standing_n / hit_prone_n — first two tokens
		var parts := anim_name.split("_")
		if parts.size() >= 3:
			semantic = "%s_%s" % [parts[0], parts[1]]
	if semantic.is_empty():
		return
	var remapped := "%s_%s" % [semantic, display_dir]
	if not _anim.sprite_frames.has_animation(remapped):
		return
	var frame := _anim.frame
	var progress := _anim.frame_progress
	var was_playing := _anim.is_playing()
	_anim.play(remapped)
	_anim.frame = mini(frame, maxi(_anim.sprite_frames.get_frame_count(remapped) - 1, 0))
	_anim.frame_progress = progress
	if not was_playing:
		_anim.pause()


func _remap_stun_for_camera() -> void:
	var world_dir := _stun_world_direction if not _stun_world_direction.is_empty() else "n"
	var display_dir := _idle_display_direction(world_dir)
	if _stun_phase == StunPresPhase.HOLD:
		if _applied_position_state == PositionState.DOWN:
			_remap_idle_prone_for_camera()
		else:
			_remap_idle_standing_for_camera()
		return
	var semantic := ""
	match _stun_phase:
		StunPresPhase.KNOCKDOWN:
			semantic = "stun_knockdown"
		StunPresPhase.RECOVER:
			semantic = "transition_prone_to_standing"
		_:
			return
	var remapped := "%s_%s" % [semantic, display_dir]
	if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(remapped):
		return
	var frame := _anim.frame
	var progress := _anim.frame_progress
	var was_playing := _anim.is_playing()
	_anim.play(remapped)
	_anim.frame = mini(frame, maxi(_anim.sprite_frames.get_frame_count(remapped) - 1, 0))
	_anim.frame_progress = progress
	if not was_playing:
		_anim.pause()


func _remap_idle_standing_for_camera() -> void:
	var world_dir := _locomotion_direction if not _locomotion_direction.is_empty() else "n"
	var display_dir := _idle_display_direction(world_dir)
	var semantic := _idle_standing_semantic()
	var anim_name := "%s_%s" % [semantic, display_dir]
	if not _anim.sprite_frames.has_animation(anim_name) and semantic != "idle_standing":
		semantic = "idle_standing"
		anim_name = "%s_%s" % [semantic, display_dir]
	if not _anim.sprite_frames.has_animation(anim_name):
		push_error("Soldier: missing idle on camera rotate: %s" % anim_name)
		return
	if str(_anim.animation) == anim_name:
		return
	var was_playing := _anim.is_playing()
	var saved_frame := _anim.frame
	_anim.play(anim_name)
	## Held standing pose — frame A after camera remap. Crouch keeps its loop.
	if semantic == "idle_standing":
		_anim.pause()
		_anim.frame = 0
	elif semantic == "idle_crouch":
		var max_frame := maxi(_anim.sprite_frames.get_frame_count(anim_name) - 1, 0)
		_anim.frame = mini(saved_frame, max_frame)
		if not was_playing:
			_anim.play(anim_name)
	_played_idle_peek_side = _idle_peek_side
	_log_idle_standing(anim_name, "CAMERA_REMAP frame=%d" % _anim.frame)


func _remap_standing_idle_fidget_for_camera() -> void:
	if _idle_fidget_semantic.is_empty():
		return
	var world_dir := _standing_idle_world_direction()
	var anim_name := "%s_%s" % [_idle_fidget_semantic, _idle_display_direction(world_dir)]
	if not _remap_animation_preserving_progress(anim_name):
		if DEBUG_IDLE_STANDING:
			GameLog.log_system(
				"[IdleFidget] fidget camera remap missing team=%d soldier=%d anim=%s"
				% [team_id, soldier_id, anim_name]
			)
		return
	_log_idle_standing(anim_name, "FIDGET_CAMERA_REMAP frame=%d" % _anim.frame)


func _remap_idle_prone_for_camera() -> void:
	var world_dir := _locomotion_direction if not _locomotion_direction.is_empty() else "n"
	var display_dir := _idle_display_direction(world_dir)
	var anim_name := "idle_prone_%s" % display_dir
	if not _anim.sprite_frames.has_animation(anim_name):
		return
	if str(_anim.animation) == anim_name:
		return
	_anim.play(anim_name)


func _remap_stance_transition_for_camera() -> void:
	var world_dir := (
		_stance_transition_world_direction
		if not _stance_transition_world_direction.is_empty()
		else _locomotion_direction
	)
	if world_dir.is_empty():
		world_dir = "n"
	var saved_frame := _anim.frame
	var display_dir := _idle_display_direction(world_dir)
	var anim_name := "%s_%s" % [_stance_transition_semantic, display_dir]
	if not _anim.sprite_frames.has_animation(anim_name):
		push_error("Soldier: missing stance transition on camera rotate: %s" % anim_name)
		return
	if str(_anim.animation) == anim_name:
		return
	var max_frame := maxi(_anim.sprite_frames.get_frame_count(anim_name) - 1, 0)
	_anim.play(anim_name)
	_anim.frame = mini(saved_frame, max_frame)
	_log_stance_transition(anim_name, "CAMERA_REMAP frame=%d" % _anim.frame)


## Survivable flinch. US uses hit_standing / hit_prone; never falls back to idle/walk frames.
func play_hit_reaction(threat_step: Vector2i, position_state: int = PositionState.UP) -> void:
	_interrupt_standing_idle_for_action()
	if not _uses_og_frames() or _death_sequence_active or _hit_reaction_active or _is_dead:
		return
	if _corpse_direction_locked:
		return
	## Priority: death → hit → throw → fire → stance. Hit cancels lower-priority actions.
	_cancel_stance_transition_visual(false)
	_cancel_throw_grenade_visual(false)
	_cancel_fire_visual(false)

	_hit_reaction_active = true
	_hit_return_prone = position_state == PositionState.DOWN
	_death_direction = UsSoldierSpriteFrames.direction_from_threat(threat_step)
	_hit_semantic = _hit_semantic_for(position_state)
	_selection_marker.visible = false
	_apply_hit_reaction_scale(position_state)
	stop_movement()

	var anim_name := "%s_%s" % [_hit_semantic, _idle_display_direction(_death_direction)]
	if not _play_hit_animation(anim_name, position_state, false):
		_hit_reaction_active = false
		return


## Fatal hit → stance hit reaction → fall → dead. Never returns to idle.
func play_death_sequence(
	threat_step: Vector2i,
	position_state: int = PositionState.UP,
	death_sprite_family: String = "",
) -> void:
	if not _uses_og_frames() or _death_sequence_active or _corpse_direction_locked:
		return
	## Death wins outright over any stun chain.
	_clear_stun_presentation()
	_interrupt_standing_idle_for_action()
	_cancel_stance_transition_visual(false)
	_cancel_throw_grenade_visual(false)
	_cancel_fire_visual(false)
	_hit_reaction_active = false
	_death_sequence_active = true
	_is_dead = true
	_dead_static_logged = false
	if not death_sprite_family.is_empty():
		_death_sprite_family = death_sprite_family.strip_edges().to_upper()
	## Fall/hit use threat-away direction; static corpse uses authoritative world facing.
	_death_direction = UsSoldierSpriteFrames.direction_from_threat(threat_step)
	_corpse_world_direction = UsSoldierSpriteFrames.direction_from_step(_last_applied_facing)
	if _corpse_world_direction.is_empty():
		_corpse_world_direction = "n"
	_corpse_direction_locked = true
	_hit_semantic = _hit_semantic_for(position_state)
	_hit_return_prone = position_state == PositionState.DOWN
	_facing_arrow.visible = false
	_prone_marker.visible = false
	_selection_marker.visible = false
	## Keep the living stance scale for the hit reaction (corpse scale applies after fall).
	_apply_hit_reaction_scale(position_state)
	stop_movement()

	var hit_display := _idle_display_direction(_death_direction)
	var anim_name := "%s_%s" % [_hit_semantic, hit_display]
	if not _play_hit_animation(anim_name, position_state, true):
		## Missing hit frames must not invent idle; skip straight to fall if available.
		_play_animation("fall_%s" % hit_display)


## Presentation-only grenade throw (ASTGA / GSPRA). Does not consume inventory or arm fuse.
## Optional facing_direction overrides the last synced world facing (authoritative SoldierState).
func play_throw_grenade(
	position_state: int = PositionState.UP,
	facing_direction: Vector2i = Vector2i.ZERO,
) -> void:
	if not _uses_og_frames() or _is_dead or _death_sequence_active or _corpse_direction_locked:
		return
	if _presentation_stunned or _stun_phase != StunPresPhase.NONE:
		return
	if _hit_reaction_active:
		return
	if _throw_grenade_active:
		return
	## Throw outranks firing and stance transition.
	_interrupt_standing_idle_for_action()
	_cancel_stance_transition_visual(false)
	_cancel_fire_visual(false)

	_throw_grenade_active = true
	_throw_release_fired = false
	_throw_return_prone = position_state == PositionState.DOWN
	if facing_direction != Vector2i.ZERO:
		_last_applied_facing = facing_direction
	_throw_world_direction = UsSoldierSpriteFrames.direction_from_step(_last_applied_facing)
	if _throw_world_direction.is_empty():
		_throw_world_direction = "n"
	_selection_marker.visible = false
	_apply_hit_reaction_scale(position_state)
	stop_movement()

	var display_dir := _throw_display_direction()
	var anim_name := "throw_grenade_%s" % display_dir
	if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(anim_name):
		push_error(
			"Soldier: missing throw_grenade animation %s (team=%d soldier=%d family=%s)"
			% [anim_name, team_id, soldier_id, _throw_source_family()]
		)
		_log_throw_grenade(anim_name, "MISSING_ANIMATION")
		_throw_grenade_active = false
		return
	var frame_count := _anim.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		push_error("Soldier: throw_grenade animation %s has zero frames" % anim_name)
		_log_throw_grenade(anim_name, "EMPTY_FRAMES")
		_throw_grenade_active = false
		return

	_anim.play(anim_name)
	_log_throw_grenade(anim_name, "PLAY")
	## If release is disabled (-1), gameplay already armed the fuse on command accept.
	if not GameplayPolicies.grenade.is_throw_release_enabled_for_team(team_id):
		_throw_release_fired = true


## Presentation-only rifle fire (standing / prone / corner peek). One sequence per accepted shot.
## `target_cell` (when valid) wins over locomotion `facing_direction` for fire sprite facing.
func play_fire(
	position_state: int = PositionState.UP,
	facing_direction: Vector2i = Vector2i.ZERO,
	peek_side: int = CoverSystem.PeekSide.NONE,
	target_cell: Vector2i = Vector2i(-999, -999),
	corner_cell: Vector2i = Vector2i(-999, -999),
) -> void:
	if not _uses_og_frames() or _is_dead or _death_sequence_active or _corpse_direction_locked:
		return
	if _presentation_stunned or _stun_phase != StunPresPhase.NONE:
		return
	if _hit_reaction_active or _throw_grenade_active:
		return
	_interrupt_standing_idle_for_action()
	if target_cell.x > -900:
		_fire_target_cell = target_cell
	if corner_cell.x > -900:
		_cover_corner_cell = corner_cell
	var fire_facing := _resolve_fire_facing_step(facing_direction, target_cell)
	## Mid-sequence shot: queue at most one restart. Do not stop_movement / restart now.
	if _fire_active or _corner_phase == CornerPresPhase.FIRING:
		_fire_restart_pending = true
		_fire_return_prone = position_state == PositionState.DOWN
		## Keep locked corner side during an active peek sequence.
		if _corner_peek_side != CoverSystem.PeekSide.NONE:
			_fire_peek_side = _corner_peek_side
		else:
			_fire_peek_side = peek_side
		if fire_facing != Vector2i.ZERO:
			_commit_sprite_facing_from_step(fire_facing, _facing_from_cell)
		_log_fire_anim("queued", "RESTART_QUEUED")
		return

	## Fire blocks _process — must clear presentation move first. Otherwise a settle/chase
	## left _is_moving true, sustained fire froze the sprite, and _finish_fire_idle replayed
	## the run anim in place for the whole engagement (the running-in-place bug).
	stop_movement()
	_cancel_stance_transition_visual(false)

	## Standing corner: CIS → CPA enter → CAS → CFA (enter once per engagement).
	if (
		position_state != PositionState.DOWN
		and peek_side != CoverSystem.PeekSide.NONE
	):
		_request_corner_fire(position_state, fire_facing, peek_side)
		return

	_clear_corner_presentation(false)
	_begin_fire_sequence(position_state, fire_facing, peek_side)


## Stand↔prone transition. Gameplay stance is already committed; this is presentation only.
func play_stance_transition(
	target_position_state: int,
	facing_direction: Vector2i = Vector2i.ZERO,
) -> void:
	if not _uses_og_frames() or _is_dead or _death_sequence_active or _corpse_direction_locked:
		## No anim — still clear the pending presentation gate.
		stance_transition_finished.emit(team_id, soldier_id, target_position_state)
		return
	if _presentation_stunned or _stun_phase != StunPresPhase.NONE:
		## Stun owns posture; clear the pending gate without a transition anim.
		stance_transition_finished.emit(team_id, soldier_id, target_position_state)
		return
	if _hit_reaction_active or _throw_grenade_active or _fire_active:
		stance_transition_finished.emit(team_id, soldier_id, target_position_state)
		return
	if _stance_transition_active:
		return
	_interrupt_standing_idle_for_action()
	## Stance change must never leave aim-hold latched.
	_clear_fire_aim_hold(false, "stance_transition")
	## Drop/stand even if we were chasing a path — sim already halted.
	if _is_moving:
		stop_movement()
	if _corner_phase_blocks_locomotion():
		_cancel_fire_visual(false)

	var from_prone := _applied_position_state == PositionState.DOWN
	var to_prone := target_position_state == PositionState.DOWN
	if from_prone == to_prone:
		## Already showing the destination stance (e.g. sync snapped) — clear pending.
		stance_transition_finished.emit(team_id, soldier_id, target_position_state)
		return

	_stance_transition_active = true
	_clear_corner_presentation(false)
	_stance_transition_target = target_position_state
	_stance_transition_semantic = (
		"transition_standing_to_prone" if to_prone else "transition_prone_to_standing"
	)
	if facing_direction != Vector2i.ZERO:
		_last_applied_facing = facing_direction
	_stance_transition_world_direction = UsSoldierSpriteFrames.direction_from_step(_last_applied_facing)
	if _stance_transition_world_direction.is_empty():
		_stance_transition_world_direction = (
			_locomotion_direction if not _locomotion_direction.is_empty() else "n"
		)
	if to_prone:
		## Go down immediately — play the drop anim from the prone footprint.
		_applied_position_state = PositionState.DOWN
		_anim.scale = _prone_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
		_prone_marker.visible = false
	else:
		## Keep prone footprint until stand-up frames finish.
		_apply_hit_reaction_scale(PositionState.DOWN)
	_selection_marker.visible = false
	_sync_facing_arrow_visibility()

	var display_dir := _idle_display_direction(_stance_transition_world_direction)
	var anim_name := "%s_%s" % [_stance_transition_semantic, display_dir]
	if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(anim_name):
		push_error(
			"Soldier: missing stance transition %s (team=%d soldier=%d)"
			% [anim_name, team_id, soldier_id]
		)
		_log_stance_transition(anim_name, "MISSING_ANIMATION")
		_stance_transition_active = false
		## Still notify gameplay so pending stance gate can clear.
		stance_transition_finished.emit(team_id, soldier_id, target_position_state)
		return
	var frame_count := _anim.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		push_error("Soldier: stance transition %s has zero frames" % anim_name)
		_log_stance_transition(anim_name, "EMPTY_FRAMES")
		_stance_transition_active = false
		stance_transition_finished.emit(team_id, soldier_id, target_position_state)
		return

	_anim.play(anim_name)
	_log_stance_transition(anim_name, "PLAY")


func _request_corner_fire(
	position_state: int,
	facing_direction: Vector2i,
	peek_side: int,
) -> void:
	_fire_return_prone = position_state == PositionState.DOWN
	_commit_combat_facing(facing_direction, _fire_target_cell)

	## Lock peek side for the whole enter/aim/fire/exit chain.
	if (
		_corner_phase == CornerPresPhase.NONE
		or _corner_phase == CornerPresPhase.IDLE
		or _corner_peek_side == CoverSystem.PeekSide.NONE
	):
		_corner_peek_side = peek_side
	_fire_peek_side = _corner_peek_side

	if _corner_phase == CornerPresPhase.PEEKING_OUT:
		_corner_fire_pending = true
		_log_fire_anim("corner_enter", "SHOT_PENDING_ENTER")
		return

	if _corner_phase == CornerPresPhase.AIMING:
		_begin_fire_sequence(position_state, facing_direction, _corner_peek_side)
		return

	if _corner_phase == CornerPresPhase.PEEKING_IN:
		## Re-acquire during exit — restart enter after canceling exit pose.
		_corner_fire_pending = true
		_start_corner_peek_enter()
		return

	## From CIS / open: peek out once, then fire.
	_corner_fire_pending = true
	_start_corner_peek_enter()


func _corner_side_token() -> String:
	return "left" if _corner_peek_side == CoverSystem.PeekSide.LEFT else "right"


func _start_corner_peek_enter() -> void:
	_interrupt_standing_idle_for_action()
	if _corner_peek_side == CoverSystem.PeekSide.NONE:
		_corner_fire_pending = false
		return
	_corner_phase = CornerPresPhase.PEEKING_OUT
	_corner_semantic = "corner_peek_enter_%s" % _corner_side_token()
	var display_dir := _idle_display_direction(_body_world_direction())
	var anim_name := "%s_%s" % [_corner_semantic, display_dir]
	if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(anim_name):
		push_warning("Soldier: missing %s — skipping to aim hold" % anim_name)
		_start_corner_aim_hold()
		return
	_anim.play(anim_name)
	_refresh_corner_lean_offset()
	_log_fire_anim(anim_name, "CORNER_ENTER")


func _start_corner_aim_hold() -> void:
	if _corner_peek_side == CoverSystem.PeekSide.NONE:
		_clear_corner_presentation(true)
		return
	_corner_phase = CornerPresPhase.AIMING
	_fire_active = false
	_corner_semantic = "corner_aim_%s" % _corner_side_token()
	var display_dir := _idle_display_direction(_body_world_direction())
	var anim_name := "%s_%s" % [_corner_semantic, display_dir]
	if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(anim_name):
		push_warning("Soldier: missing %s" % anim_name)
	else:
		_anim.play(anim_name)
		## One-frame CAS hold — pause so refreshes do not replay.
		if _anim.sprite_frames.get_frame_count(anim_name) <= 1:
			_anim.pause()
			_anim.frame = 0
		_log_fire_anim(anim_name, "CORNER_AIM_HOLD")
	_refresh_corner_lean_offset()

	if _corner_fire_pending:
		_corner_fire_pending = false
		var stance := PositionState.DOWN if _fire_return_prone else PositionState.UP
		_begin_fire_sequence(stance, _last_applied_facing, _corner_peek_side)


func _start_corner_peek_exit() -> void:
	if _corner_peek_side == CoverSystem.PeekSide.NONE:
		_clear_corner_presentation(true)
		return
	_corner_phase = CornerPresPhase.PEEKING_IN
	_corner_fire_pending = false
	_fire_active = false
	_fire_restart_pending = false
	_corner_semantic = "corner_peek_exit_%s" % _corner_side_token()
	var display_dir := _idle_display_direction(_body_world_direction())
	var anim_name := "%s_%s" % [_corner_semantic, display_dir]
	if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(anim_name):
		push_warning("Soldier: missing %s — snap to corner idle" % anim_name)
		_finish_corner_peek_exit()
		return
	_anim.play(anim_name)
	_refresh_corner_lean_offset()
	_log_fire_anim(anim_name, "CORNER_EXIT")


func _finish_corner_peek_exit() -> void:
	var peek := _corner_peek_side
	_corner_phase = CornerPresPhase.NONE
	_corner_semantic = ""
	_corner_fire_pending = false
	_fire_peek_side = CoverSystem.PeekSide.NONE
	## Return to CIS if still at that corner; otherwise open idle.
	if _idle_peek_side == peek and peek != CoverSystem.PeekSide.NONE:
		_corner_phase = CornerPresPhase.IDLE
		_corner_peek_side = peek
	else:
		_corner_peek_side = CoverSystem.PeekSide.NONE
		if _idle_peek_side == CoverSystem.PeekSide.NONE:
			_cover_corner_cell = Vector2i(-999, -999)
	_finish_fire_idle()
	_refresh_corner_lean_offset()


func _clear_corner_presentation(_resume_idle: bool) -> void:
	_corner_phase = CornerPresPhase.NONE
	_corner_peek_side = CoverSystem.PeekSide.NONE
	_corner_semantic = ""
	_corner_fire_pending = false
	## Drop lean when leaving corner presentation (idle peek may re-apply on sync).
	if _idle_peek_side == CoverSystem.PeekSide.NONE:
		_cover_corner_cell = Vector2i(-999, -999)
	_refresh_corner_lean_offset()


func _sync_fire_aim_hold(state: SoldierState) -> void:
	## Clear stale open aim-hold latch only. Idle / engagement never drive ASAPA/ASAIS —
	## those belong to fire and corner peek pipelines, not the standing idle family.
	if _idle_fidget_active:
		_interrupt_standing_idle_for_action()
	if state == null or _fire_active or _is_dead or _presentation_stunned:
		if _fire_aim_hold_active and (
			_fire_active or _is_dead or _presentation_stunned
		):
			var block_reason := (
				"sync_blocked_fire" if _fire_active
				else "sync_blocked_dead" if _is_dead
				else "sync_blocked_stunned"
			)
			_clear_fire_aim_hold(false, block_reason)
		return
	if _is_moving and state.is_moving:
		if _fire_aim_hold_active:
			_clear_fire_aim_hold(false, "sync_blocked_moving")
		return
	if (
		_corner_phase == CornerPresPhase.PEEKING_OUT
		or _corner_phase == CornerPresPhase.PEEKING_IN
		or _corner_phase == CornerPresPhase.FIRING
	):
		if _fire_aim_hold_active:
			_clear_fire_aim_hold(false, "sync_corner_phase_%d" % _corner_phase)
		return
	if state.is_engaged():
		_aim_hold_last_target_team_id = state.engaged_target_team_id
		_aim_hold_last_target_soldier_id = state.engaged_target_soldier_id
		_aim_hold_disengage_msec = -1
	elif _aim_hold_disengage_msec < 0:
		_aim_hold_disengage_msec = SimulationClock.get_ticks_msec()
	if _fire_aim_hold_active or _fire_aim_enter_active:
		_clear_fire_aim_hold(true, "sync_idle_no_aim")
	if not state.is_engaged():
		_fire_target_cell = Vector2i(-999, -999)
	_clear_stale_open_fire_pose()


func _aim_hold_firing_posture(state: SoldierState) -> bool:
	return (
		state != null
		and (
			state.fire_control_state == FireControlState.FIRE_AT_WILL
			or state.is_sustained_fire()
		)
	)


func _aim_hold_should_persist(state: SoldierState) -> bool:
	## Survive clear→re-acquire: short grace, or whole HUD Aiming cycle (fire_ready).
	if not _aim_hold_firing_posture(state):
		return false
	if state.fire_ready_after_msec > SimulationClock.get_ticks_msec():
		return true
	if _aim_hold_disengage_msec < 0:
		return false
	var grace_sec := GameplayPolicies.fire_anim.aim_hold_disengage_grace_sec
	if grace_sec <= 0.0:
		return false
	var elapsed_msec := SimulationClock.get_ticks_msec() - _aim_hold_disengage_msec
	return elapsed_msec < int(grace_sec * 1000.0)


## Cancel competing presentation and start knockdown → idle hold → recover (Stage 2).
func _enter_stun_presentation() -> void:
	_presentation_stunned = true
	_interrupt_standing_idle_for_action()
	_clear_fire_aim_hold(false, "stun_enter")
	_cancel_fire_visual(false)
	_cancel_throw_grenade_visual(false)
	_cancel_stance_transition_visual(false)
	_clear_corner_presentation(false)
	_hit_reaction_active = false
	_cover_corner_cell = Vector2i(-999, -999)
	_idle_peek_side = CoverSystem.PeekSide.NONE
	_played_idle_peek_side = CoverSystem.PeekSide.NONE
	stop_movement()
	_stun_world_direction = UsSoldierSpriteFrames.direction_from_step(_last_applied_facing)
	if _stun_world_direction.is_empty():
		_stun_world_direction = "n"
	## Fall authored at standing scale; DOWN stance is already committed in sim.
	_applied_position_state = PositionState.DOWN
	_anim.position = Vector2.ZERO
	_anim.scale = _standing_sprite_scale()
	_anim.offset = TileSizeConfig.soldier_standing_sprite_offset()
	_prone_marker.visible = false
	_facing_arrow.visible = false
	_stun_phase = StunPresPhase.KNOCKDOWN
	var display_dir := _idle_display_direction(_stun_world_direction)
	var anim_name := "stun_knockdown_%s" % display_dir
	if _anim.sprite_frames != null and _anim.sprite_frames.has_animation(anim_name):
		_anim.play(anim_name)
		return
	## Fallback: skip straight to normal idle hold if DB entry missing.
	_play_stun_hold_pose()


func _clear_stun_presentation() -> void:
	_stun_phase = StunPresPhase.NONE
	_presentation_stunned = false
	_stun_world_direction = "n"


func _play_stun_hold_pose() -> void:
	## Stunned hold uses the same standing/prone idle as normal play — not stun_idle.
	_stun_phase = StunPresPhase.HOLD
	_presentation_stunned = true
	_prone_marker.visible = false
	_facing_arrow.visible = false
	var world_dir := _stun_world_direction if not _stun_world_direction.is_empty() else "n"
	if _applied_position_state == PositionState.DOWN:
		_anim.position = Vector2.ZERO
		_anim.scale = _prone_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
		_play_idle_prone(world_dir)
	else:
		_applied_position_state = PositionState.UP
		_anim.position = Vector2.ZERO
		_anim.scale = _standing_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_standing_sprite_offset()
		_play_idle_standing(world_dir)


func _is_stun_hold_anim(anim_name: String) -> bool:
	return (
		anim_name.begins_with("idle_prone_")
		or anim_name.begins_with("idle_crouch_")
		or anim_name.begins_with("idle_standing_")
		or anim_name.begins_with("stun_knockdown_")
	)


func _end_stun_presentation(post_stun_position: int) -> void:
	## Stun expired. Stand up with the normal prone→stand clip, or stay lying.
	if _death_sequence_active or _is_dead:
		_clear_stun_presentation()
		return
	if post_stun_position == PositionState.DOWN:
		_clear_stun_presentation()
		_applied_position_state = PositionState.DOWN
		_anim.position = Vector2.ZERO
		_anim.scale = _prone_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
		_facing_arrow.visible = false
		_play_idle_prone(
			_stun_world_direction if not _stun_world_direction.is_empty() else "n"
		)
		return
	_begin_stun_recover()


func _begin_stun_recover() -> void:
	## Stand-up only — uses transition_prone_to_standing (APRNA/GPRNA), not AHTBA hit.
	if _stun_phase == StunPresPhase.RECOVER or _death_sequence_active or _is_dead:
		return
	if _presentation_stunned:
		_play_stun_hold_pose()
		return
	_stun_phase = StunPresPhase.RECOVER
	## Keep prone footprint until stand-up frames finish (same as play_stance_transition).
	_applied_position_state = PositionState.DOWN
	_anim.position = Vector2.ZERO
	_anim.scale = _prone_sprite_scale()
	_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
	_facing_arrow.visible = false
	var display_dir := _idle_display_direction(_stun_world_direction)
	var anim_name := "transition_prone_to_standing_%s" % display_dir
	if _anim.sprite_frames != null and _anim.sprite_frames.has_animation(anim_name):
		_anim.play(anim_name)
		return
	_finish_stun_recover()


func _finish_stun_knockdown() -> void:
	if _death_sequence_active or _is_dead:
		_clear_stun_presentation()
		return
	## Hold prone for the rest of the sim stun. Recover only when sync clears the latch.
	if _presentation_stunned:
		_play_stun_hold_pose()
	else:
		_begin_stun_recover()


func _finish_stun_recover() -> void:
	_clear_stun_presentation()
	_applied_position_state = PositionState.UP
	_anim.position = Vector2.ZERO
	_anim.scale = _standing_sprite_scale()
	_anim.offset = TileSizeConfig.soldier_standing_sprite_offset()
	_sync_facing_arrow_visibility()
	_locomotion_walking = true
	var dir := (
		_stun_world_direction
		if not _stun_world_direction.is_empty()
		else UsSoldierSpriteFrames.direction_from_step(_last_applied_facing)
	)
	_play_locomotion(dir if not dir.is_empty() else "n", false)


## reason is DEBUG_AIM_HOLD-only (call sites may omit).
func _clear_fire_aim_hold(resume_idle: bool = false, reason: String = "") -> void:
	if not _fire_aim_hold_active and not _fire_aim_enter_active:
		_aim_hold_disengage_msec = -1
		return
	if DEBUG_AIM_HOLD:
		GameLog.log_system(
			(
				"[AIM_HOLD] phase=CLEAR soldier=%d rot_idx=%d facet_deg=%d "
				+ "resume_idle=%s reason=%s anim_before=%s hold_was=%s enter_was=%s "
				+ "moving=%s corner_phase=%d"
			)
			% [
				soldier_id,
				IsometricGrid.current_view_rotation,
				IsometricGrid.facet_camera_direction_degrees(),
				resume_idle,
				reason if not reason.is_empty() else "unspecified",
				str(_anim.animation) if _anim != null else "",
				_fire_aim_hold_active,
				_fire_aim_enter_active,
				_is_moving,
				_corner_phase,
			]
		)
	_fire_aim_hold_active = false
	_fire_aim_enter_active = false
	_aim_hold_disengage_msec = -1
	## Keep last-target ids across fire oneshots so post-shot clear→re-acquire
	## grace still recognizes a prior engagement. Wipe only when lowering the rifle.
	if resume_idle:
		_aim_hold_last_target_team_id = -1
		_aim_hold_last_target_soldier_id = -1
	if (
		resume_idle
		and not _is_moving
		and not _blocks_action_override()
		and not _is_dead
	):
		_play_locomotion(_body_world_direction(), false)


func _aim_hold_semantic(position_state: int) -> String:
	return "aim_prone_hold" if position_state == PositionState.DOWN else "aim_standing_hold"


func _fire_aim_hold_frame(anim_name: String) -> int:
	## Dedicated aim holds are single-frame (ASAIS/APAIS). Fire clips are not idle holds.
	if anim_name.begins_with("aim_standing_hold_") or anim_name.begins_with("aim_prone_hold_"):
		return 0
	return 0


func _resolve_fire_facing_step(
	facing_direction: Vector2i,
	target_cell: Vector2i,
) -> Vector2i:
	## Prefer shooter→target bearing; fall back to caller facing / last applied.
	if target_cell.x > -900:
		var delta := target_cell - _facing_from_cell
		var toward := UsSoldierSpriteFrames.snap_step_to_eight_way(delta)
		if toward != Vector2i.ZERO:
			return toward
	if facing_direction != Vector2i.ZERO:
		return FacingDirection.normalize(facing_direction)
	return _last_applied_facing


func _begin_fire_aim_hold(position_state: int) -> void:
	## Engaged + aiming: ASAPA enter (standing), then ASAIS/APAIS hold.
	## Uses the same step → _locomotion_direction → display suffix path as walk/crawl.
	if _idle_fidget_active:
		_interrupt_standing_idle_for_action()
	else:
		_cancel_standing_idle()
	_post_shot_crouch_remaining = 0.0
	if (
		_corner_phase == CornerPresPhase.IDLE
		or _corner_phase == CornerPresPhase.AIMING
	):
		_clear_corner_presentation(false)
	var hold_facing := _commit_combat_facing(_last_applied_facing, _fire_target_cell)
	var world_dir := _body_world_direction()
	var hold_semantic := _aim_hold_semantic(position_state)
	var hold_anim := _sprite_anim_name(hold_semantic, world_dir)
	var enter_anim := _sprite_anim_name("aim_standing", world_dir)
	var display_dir := _display_direction_for_world(world_dir)
	var has_hold := (
		_anim.sprite_frames != null and _anim.sprite_frames.has_animation(hold_anim)
	)
	var has_enter := (
		_anim.sprite_frames != null and _anim.sprite_frames.has_animation(enter_anim)
	)
	if _anim.sprite_frames == null:
		_log_aim_hold_diag(
			position_state, hold_facing, display_dir, hold_anim, enter_anim, false, false, "NULL_SF"
		)
		return
	if not has_hold:
		_log_aim_hold_diag(
			position_state, hold_facing, display_dir, hold_anim, enter_anim, false, has_enter,
			"MISSING_HOLD"
		)
		return
	var current := str(_anim.animation)
	var current_is_hold := (
		current.begins_with("aim_standing_hold_") or current.begins_with("aim_prone_hold_")
	)
	if (
		_fire_aim_hold_active
		and not _fire_aim_enter_active
		and current_is_hold
		and current == hold_anim
		and not _anim.is_playing()
		and _anim.frame == _fire_aim_hold_frame(hold_anim)
	):
		_log_aim_hold_diag(
			position_state, hold_facing, display_dir, hold_anim, enter_anim, has_hold, has_enter,
			"KEEP"
		)
		return
	## Let ASAPA oneshot finish; sync must not restart it every tick.
	## Exclude aim_standing_hold_* (also begins with aim_standing_).
	## If enter finished without the finished signal, or camera/target changed the
	## display letter, fall through and snap to the correct hold (Camera 90° latch).
	if (
		_fire_aim_enter_active
		and current.begins_with("aim_standing_")
		and not current.begins_with("aim_standing_hold_")
		and _anim.is_playing()
		and current == enter_anim
	):
		_log_aim_hold_diag(
			position_state, hold_facing, display_dir, hold_anim, enter_anim, has_hold, has_enter,
			"ENTER_WAIT"
		)
		return
	## Enter oneshot ended but hold latch missed — snap ASAIS instead of replaying ASAPA.
	if (
		_fire_aim_enter_active
		and current.begins_with("aim_standing_")
		and not current.begins_with("aim_standing_hold_")
		and not _anim.is_playing()
	):
		_fire_aim_enter_active = false
	var from_fire := (
		current.begins_with("fire_standing_")
		or current.begins_with("fire_prone_")
		or current.begins_with("corner_fire_")
	)
	var have_combat_aim := (
		_fire_target_cell.x > -900
		or _aim_hold_last_target_team_id >= 0
	)
	## ASAPA only for untargeted raise; engaged / between-shot always latch ASAIS (matches fire).
	var want_enter := (
		position_state != PositionState.DOWN
		and not from_fire
		and not _fire_aim_hold_active
		and not _fire_aim_enter_active
		and not have_combat_aim
	)
	_fire_aim_hold_active = true
	_fire_aim_enter_active = false
	_fire_semantic = hold_semantic
	_apply_hit_reaction_scale(position_state)
	if want_enter and has_enter:
		_fire_aim_enter_active = true
		_fire_semantic = "aim_standing"
		_anim.play(enter_anim)
		_log_fire_anim(enter_anim, "AIM_ENTER")
		_log_aim_hold_diag(
			position_state, hold_facing, display_dir, hold_anim, enter_anim, has_hold, has_enter,
			"ENTER"
		)
		return
	_play_fire_aim_hold_pose(hold_anim)
	_log_aim_hold_diag(
		position_state, hold_facing, display_dir, hold_anim, enter_anim, has_hold, has_enter,
		"HOLD"
	)


func _log_aim_hold_diag(
	position_state: int,
	hold_facing: Vector2i,
	display_dir: String,
	hold_anim: String,
	enter_anim: String,
	has_hold: bool,
	has_enter: bool,
	phase: String,
) -> void:
	if not DEBUG_AIM_HOLD:
		return
	var rot_idx := IsometricGrid.current_view_rotation
	var facet_deg := IsometricGrid.facet_camera_direction_degrees()
	var coord_deg := IsometricGrid.camera_direction_degrees()
	var pure_world := FacingDirection.to_anim_suffix(_last_applied_facing)
	GameLog.log_system(
		(
			"[AIM_HOLD] phase=%s soldier=%d rot_idx=%d facet_deg=%d coord_deg=%d "
			+ "from_cell=%s target_cell=%s hold_facing=%s last_facing=%s "
			+ "pure_world_letter=%s fire_world_dir=%s display_dir=%s "
			+ "hold_anim=%s has_hold=%s enter_anim=%s has_enter=%s "
			+ "hold_active=%s enter_active=%s anim_after=%s stance=%d"
		)
		% [
			phase,
			soldier_id,
			rot_idx,
			facet_deg,
			coord_deg,
			_facing_from_cell,
			_fire_target_cell,
			hold_facing,
			_last_applied_facing,
			pure_world,
			_locomotion_direction,
			display_dir,
			hold_anim,
			has_hold,
			enter_anim,
			has_enter,
			_fire_aim_hold_active,
			_fire_aim_enter_active,
			str(_anim.animation) if _anim != null else "",
			position_state,
		]
	)


func _play_fire_aim_hold_pose(hold_anim: String) -> void:
	_fire_aim_enter_active = false
	if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(hold_anim):
		return
	var aim_frame := _fire_aim_hold_frame(hold_anim)
	_anim.play(hold_anim)
	_anim.pause()
	_anim.frame = aim_frame
	_log_fire_anim(hold_anim, "AIM_HOLD")


func _begin_fire_sequence(
	position_state: int,
	facing_direction: Vector2i,
	peek_side: int = CoverSystem.PeekSide.NONE,
) -> void:
	_interrupt_standing_idle_for_action()
	_clear_fire_aim_hold(false, "begin_fire_sequence")
	_fire_active = true
	_fire_restart_pending = false
	_fire_visual_shot_logged = false
	_fire_return_prone = position_state == PositionState.DOWN
	_fire_peek_side = peek_side
	if peek_side != CoverSystem.PeekSide.NONE:
		_corner_phase = CornerPresPhase.FIRING
		_corner_peek_side = peek_side
	_fire_semantic = GameplayPolicies.fire_anim.semantic_for(position_state, peek_side)
	_commit_combat_facing(facing_direction, _fire_target_cell)
	_apply_hit_reaction_scale(position_state)

	var world_dir := _body_world_direction()
	var anim_name := _sprite_anim_name(_fire_semantic, world_dir)
	if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(anim_name):
		push_error(
			"Soldier: missing fire animation %s (team=%d soldier=%d family=%s)"
			% [anim_name, team_id, soldier_id, _fire_source_family()]
		)
		_log_fire_anim(anim_name, "MISSING_ANIMATION")
		_fire_active = false
		if peek_side != CoverSystem.PeekSide.NONE:
			_corner_phase = CornerPresPhase.AIMING
		return
	var frame_count := _anim.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		push_error("Soldier: fire animation %s has zero frames" % anim_name)
		_log_fire_anim(anim_name, "EMPTY_FRAMES")
		_fire_active = false
		if peek_side != CoverSystem.PeekSide.NONE:
			_corner_phase = CornerPresPhase.AIMING
		return

	GameplayPolicies.fire_anim.note_visual_firing_trigger()
	_anim.play(anim_name)
	if peek_side != CoverSystem.PeekSide.NONE:
		_refresh_corner_lean_offset()
	_log_fire_anim(anim_name, "PLAY")


func _remap_throw_for_camera() -> void:
	var saved_frame := _anim.frame
	var display_dir := _throw_display_direction()
	var anim_name := "throw_grenade_%s" % display_dir
	if not _anim.sprite_frames.has_animation(anim_name):
		push_error("Soldier: missing throw_grenade animation on camera rotate: %s" % anim_name)
		return
	if str(_anim.animation) == anim_name:
		return
	var max_frame := maxi(_anim.sprite_frames.get_frame_count(anim_name) - 1, 0)
	_anim.play(anim_name)
	_anim.frame = mini(saved_frame, max_frame)
	_log_throw_grenade(anim_name, "CAMERA_REMAP frame=%d" % _anim.frame)


func _remap_fire_for_camera() -> void:
	var anim_name := _sprite_anim_name(_fire_semantic, _body_world_direction())
	if not _remap_animation_preserving_progress(anim_name):
		push_error("Soldier: missing fire animation on camera rotate: %s" % anim_name)
		return
	_log_fire_anim(anim_name, "CAMERA_REMAP frame=%d" % _anim.frame)


func _remap_corner_presentation_for_camera() -> void:
	if _corner_semantic.is_empty():
		return
	var saved_frame := _anim.frame
	var world_dir := _body_world_direction()
	var display_dir := _idle_display_direction(world_dir)
	var anim_name := "%s_%s" % [_corner_semantic, display_dir]
	if not _anim.sprite_frames.has_animation(anim_name):
		return
	if str(_anim.animation) == anim_name:
		return
	var max_frame := maxi(_anim.sprite_frames.get_frame_count(anim_name) - 1, 0)
	_anim.play(anim_name)
	_anim.frame = mini(saved_frame, max_frame)
	if _corner_phase == CornerPresPhase.AIMING and max_frame <= 0:
		_anim.pause()
		_anim.frame = 0
	_log_fire_anim(anim_name, "CORNER_CAMERA_REMAP frame=%d" % _anim.frame)


## Developer validation snapshot for active or last throw resolution.
func dump_throw_grenade_validation() -> Dictionary:
	var display_dir := _throw_display_direction() if _throw_grenade_active else AnimationDatabase.display_direction(
		_throw_world_direction if not _throw_world_direction.is_empty() else "n",
		IsometricGrid.facet_camera_direction_degrees(),
	)
	var anim_name := "throw_grenade_%s" % display_dir
	var family_id := (
		UsSoldierSpriteFrames.DB_FAMILY_USA
		if team_id == Team.USA
		else UsSoldierSpriteFrames.DB_FAMILY_GERMANY
	)
	var frame_paths := AnimationDatabase.get_direction_frames(family_id, "throw_grenade", display_dir)
	var frame_idx := _anim.frame if _anim != null else -1
	var frame_letter := "?"
	if frame_idx >= 0 and frame_idx < 26:
		frame_letter = String.chr(ord("A") + frame_idx)
	return {
		"faction": Team.display_name(team_id),
		"semantic": "throw_grenade",
		"source_family": _throw_source_family(),
		"world_facing": _throw_world_direction,
		"camera_rotation": IsometricGrid.facet_camera_direction_degrees(),
		"resolved_source_direction": display_dir,
		"animation": anim_name,
		"frame_index": frame_idx,
		"frame_letter": frame_letter,
		"ordered_frames": frame_paths,
		"release_callback_fired": _throw_release_fired,
		"throw_active": _throw_grenade_active,
		"release_frame": GameplayPolicies.grenade.throw_release_frame_for_team(team_id),
	}


func _throw_display_direction() -> String:
	return AnimationDatabase.display_direction(
		_throw_world_direction,
		_presentation_camera_degrees(),
	)


func _throw_source_family() -> String:
	return "GSPRA" if team_id == Team.GERMANY else "ASTGA"


func _cancel_throw_grenade_visual(resume_idle: bool) -> void:
	if not _throw_grenade_active:
		return
	_throw_grenade_active = false
	if resume_idle and not _is_dead and not _death_sequence_active:
		_finish_throw_grenade_idle()


func _fire_display_direction() -> String:
	return _display_direction_for_world(_body_world_direction())


func _fire_source_family() -> String:
	var stance := PositionState.DOWN if _fire_return_prone else PositionState.UP
	return GameplayPolicies.fire_anim.source_family_for(team_id, stance, _fire_peek_side)


func _cancel_fire_visual(resume_idle: bool) -> void:
	_clear_fire_aim_hold(false, "cancel_fire_visual")
	var had_corner := _corner_phase_blocks_locomotion() or _fire_active
	if not _fire_active and not had_corner:
		return
	_fire_active = false
	_fire_restart_pending = false
	_fire_peek_side = CoverSystem.PeekSide.NONE
	_fire_target_cell = Vector2i(-999, -999)
	_clear_corner_presentation(false)
	if resume_idle and not _is_dead and not _death_sequence_active:
		_finish_fire_idle()


func _cancel_stance_transition_visual(resume_idle: bool) -> void:
	if not _stance_transition_active:
		return
	_stance_transition_active = false
	_stance_transition_semantic = ""
	stance_transition_cancelled.emit(team_id, soldier_id)
	if resume_idle and not _is_dead and not _death_sequence_active:
		_locomotion_walking = true
		var idle_dir := (
			_stance_transition_world_direction
			if not _stance_transition_world_direction.is_empty()
			else _locomotion_direction
		)
		_play_locomotion(idle_dir if not idle_dir.is_empty() else "n", false)


func _finish_stance_transition(anim_name: String) -> void:
	var target := _stance_transition_target
	var world_dir := (
		_stance_transition_world_direction
		if not _stance_transition_world_direction.is_empty()
		else _locomotion_direction
	)
	if world_dir.is_empty():
		world_dir = "n"
	_stance_transition_active = false
	_log_stance_transition(anim_name, "COMPLETE → clear pending gate")
	## Destination stance visuals (go-down already applied at PLAY).
	if target == PositionState.DOWN:
		_applied_position_state = PositionState.DOWN
		_anim.scale = _prone_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
		_prone_marker.visible = false
	else:
		_applied_position_state = PositionState.UP
		_anim.scale = _standing_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_standing_sprite_offset()
		_prone_marker.visible = false
	_locomotion_direction = world_dir
	_locomotion_walking = true
	_play_locomotion(world_dir, false)
	_sync_facing_arrow_visibility()
	stance_transition_finished.emit(team_id, soldier_id, target)


## Developer validation snapshot for rifle fire presentation.
func dump_fire_validation() -> Dictionary:
	var stance := PositionState.DOWN if _fire_return_prone else PositionState.UP
	var semantic := (
		_fire_semantic
		if not _fire_semantic.is_empty()
		else GameplayPolicies.fire_anim.semantic_for(stance, _fire_peek_side)
	)
	var display_dir := _fire_display_direction() if _fire_active else _display_direction_for_world(
		_body_world_direction(),
	)
	var anim_name := "%s_%s" % [semantic, display_dir]
	var family_id := (
		UsSoldierSpriteFrames.DB_FAMILY_USA
		if team_id == Team.USA
		else UsSoldierSpriteFrames.DB_FAMILY_GERMANY
	)
	var frame_paths := AnimationDatabase.get_direction_frames(family_id, semantic, display_dir)
	var frame_idx := _anim.frame if _anim != null else -1
	var frame_letter := "?"
	if frame_idx >= 0 and frame_idx < 26:
		frame_letter = String.chr(ord("A") + frame_idx)
	var fps := 0.0
	if _anim != null and _anim.sprite_frames != null and _anim.sprite_frames.has_animation(anim_name):
		fps = _anim.sprite_frames.get_animation_speed(anim_name)
	return {
		"faction": Team.display_name(team_id),
		"stance": PositionState.display_name(stance),
		"semantic": semantic,
		"source_family": _fire_source_family(),
		"world_facing": _body_world_direction(),
		"camera_rotation": IsometricGrid.facet_camera_direction_degrees(),
		"resolved_source_direction": display_dir,
		"animation": anim_name,
		"frame_index": frame_idx,
		"frame_letter": frame_letter,
		"ordered_frames": frame_paths,
		"fps": fps,
		"fire_active": _fire_active,
		"peek_side": CoverSystem.peek_side_name(_fire_peek_side),
		"visual_shot_frame": GameplayPolicies.fire_anim.visual_shot_frame_for(
			team_id, stance, _fire_peek_side
		),
		"authoritative_shot_event_count": GameplayPolicies.fire_anim.authoritative_shot_event_count,
		"visual_firing_trigger_count": GameplayPolicies.fire_anim.visual_firing_trigger_count,
	}


func _on_anim_frame_changed() -> void:
	## Ease corner lean with peek enter/exit frames.
	if (
		_corner_phase == CornerPresPhase.PEEKING_OUT
		or _corner_phase == CornerPresPhase.PEEKING_IN
	):
		_refresh_corner_lean_offset()
	if _fire_aim_hold_active and not _fire_active and not _fire_aim_enter_active:
		var hold_name := str(_anim.animation)
		## Only latch ASAIS/APAIS (or fire-clip fallback) — never idle fidgets / locomotion.
		if not _is_fire_aim_hold_anim_name(hold_name):
			return
		var aim_frame := _fire_aim_hold_frame(hold_name)
		if _anim.frame != aim_frame:
			_anim.pause()
			_anim.frame = aim_frame
	if _fire_active and not _fire_visual_shot_logged:
		var shot_frame := GameplayPolicies.fire_anim.visual_shot_frame_for_family(
			_fire_source_family()
		)
		## Muzzle is A (index 0); clamp for short clips.
		if _anim.sprite_frames != null and _anim.sprite_frames.has_animation(str(_anim.animation)):
			var max_frame := maxi(_anim.sprite_frames.get_frame_count(str(_anim.animation)) - 1, 0)
			shot_frame = mini(shot_frame, max_frame)
		if _anim.frame >= shot_frame:
			_fire_visual_shot_logged = true
			_log_fire_anim(str(_anim.animation), "VISUAL_SHOT_FRAME frame=%d" % _anim.frame)
	if not _throw_grenade_active or _throw_release_fired:
		return
	if not GameplayPolicies.grenade.is_throw_release_enabled_for_team(team_id):
		return
	var release_frame := GameplayPolicies.grenade.throw_release_frame_for_team(team_id)
	if _anim.frame < release_frame:
		return
	_throw_release_fired = true
	_log_throw_grenade(str(_anim.animation), "RELEASE_CALLBACK frame=%d" % _anim.frame)
	grenade_release_reached.emit(team_id, soldier_id)


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

	if (
		_stun_phase == StunPresPhase.KNOCKDOWN
		and not _death_sequence_active
		and anim_name.begins_with("stun_knockdown_")
	):
		_finish_stun_knockdown()
		return

	if (
		_stun_phase == StunPresPhase.RECOVER
		and not _death_sequence_active
		and (
			anim_name.begins_with("transition_prone_to_standing_")
			or anim_name.begins_with("stun_recover_")
		)
	):
		_finish_stun_recover()
		return

	if _throw_grenade_active and not _death_sequence_active:
		_finish_throw_grenade(anim_name)
		return

	if _hit_reaction_active and not _death_sequence_active:
		_finish_survivable_hit_reaction(anim_name)
		return

	if _corner_phase == CornerPresPhase.PEEKING_OUT and not _death_sequence_active:
		_start_corner_aim_hold()
		return

	if _corner_phase == CornerPresPhase.PEEKING_IN and not _death_sequence_active:
		_finish_corner_peek_exit()
		return

	if not _death_sequence_active and _is_idle_fidget_anim_name(anim_name):
		## Finish before fire_active — a cleared fidget latch must not run _finish_fire.
		_finish_standing_idle_fidget(anim_name)
		return

	if _fire_active and not _death_sequence_active:
		_finish_fire(anim_name)
		return

	if (
		_fire_aim_enter_active
		and not _death_sequence_active
		and anim_name.begins_with("aim_standing_")
		and not anim_name.begins_with("aim_standing_hold_")
	):
		_fire_aim_enter_active = false
		var dir_token := anim_name.trim_prefix("aim_standing_")
		_fire_semantic = "aim_standing_hold"
		_play_fire_aim_hold_pose("aim_standing_hold_%s" % dir_token)
		return

	if _stance_transition_active and not _death_sequence_active:
		_finish_stance_transition(anim_name)
		return

	if not _death_sequence_active:
		return

	if _is_hit_reaction_anim(anim_name):
		var fall_dir := _idle_display_direction(_death_direction)
		_log_hit_completion(anim_name, "→ fall_%s" % fall_dir)
		_play_animation("fall_%s" % fall_dir)
	elif anim_name.begins_with("fall_"):
		_log_hit_completion(anim_name, "→ dead_%s" % _death_direction)
		_finish_death_sequence()


func _finish_throw_grenade(anim_name: String) -> void:
	_throw_grenade_active = false
	_log_throw_grenade(anim_name, "COMPLETE → idle")
	_finish_throw_grenade_idle()


func _finish_fire(anim_name: String) -> void:
	if _fire_restart_pending and not _hit_reaction_active and not _throw_grenade_active:
		_log_fire_anim(anim_name, "COMPLETE → restart queued shot")
		var stance := PositionState.DOWN if _fire_return_prone else PositionState.UP
		var peek := (
			_corner_peek_side
			if _corner_peek_side != CoverSystem.PeekSide.NONE
			else _fire_peek_side
		)
		_fire_active = false
		## Sustained corner fire: CFA → CFA, never CIS between queued shots.
		## Facing from stored target cell (not locomotion heading).
		var restart_facing := _resolve_fire_facing_step(_last_applied_facing, _fire_target_cell)
		_begin_fire_sequence(stance, restart_facing, peek)
		return
	_fire_active = false
	_fire_restart_pending = false
	_log_fire_anim(anim_name, "COMPLETE → post-shot")
	## Stage 1: after CFA/open fire, between-shot pose is open ASAIS/APAIS at every camera.
	## Peek enter still plays before the shot; CAS/CIS between shots is Stage 10.
	if _corner_peek_side != CoverSystem.PeekSide.NONE:
		if DEBUG_AIM_HOLD:
			GameLog.log_system(
				(
					"[AIM_HOLD] phase=FINISH_CORNER_TO_OPEN soldier=%d rot_idx=%d "
					+ "facet_deg=%d corner_peek=%d"
				)
				% [
					soldier_id,
					IsometricGrid.current_view_rotation,
					IsometricGrid.facet_camera_direction_degrees(),
					_corner_peek_side,
				]
			)
		_clear_corner_presentation(false)
	_fire_peek_side = CoverSystem.PeekSide.NONE
	if not _fire_return_prone and not _is_moving:
		_begin_post_shot_crouch()
	_finish_fire_idle()


func _begin_post_shot_crouch() -> void:
	if _idle_peek_side != CoverSystem.PeekSide.NONE:
		return
	if _is_moving and _has_active_chase():
		return
	var hold := GameplayPolicies.idle_anim.post_shot_crouch_sec
	if hold <= 0.0:
		return
	_post_shot_crouch_remaining = hold
	_cancel_standing_idle()
	set_process(true)


func _tick_post_shot_crouch(delta: float) -> void:
	if _post_shot_crouch_remaining <= 0.0:
		return
	if _is_dead or _blocks_action_override():
		_post_shot_crouch_remaining = 0.0
		return
	_post_shot_crouch_remaining = maxf(0.0, _post_shot_crouch_remaining - delta)
	if _post_shot_crouch_remaining > 0.0:
		return
	## Timer elapsed — re-evaluate idle (standing if fire-at-will and not stressed).
	if _is_moving or _applied_position_state == PositionState.DOWN:
		return
	_locomotion_walking = true
	_play_locomotion(_body_world_direction(), false)


func _finish_fire_idle() -> void:
	## Fire/aim oneshots must not linger — idle family owns the stationary pose.
	_clear_fire_aim_hold(false, "finish_fire_idle")
	_clear_stale_open_fire_pose()
	## Never resume a run loop unless we still have a chase cell to cover.
	## Settling (empty path) or waiting at a cell must stay idle — not run-in-place.
	if _is_moving and _has_active_chase() and position.distance_to(_move_target_world) > 0.5:
		_locomotion_walking = false
		var move_dir := _body_world_direction()
		_play_locomotion(move_dir, true)
		_sync_facing_arrow_visibility()
		return
	if _is_moving and not _has_active_chase():
		## Snap settle after fire blocked _process; do not restart walk.
		position = _move_target_world
		_finish_presentation_move()
		_sync_facing_arrow_visibility()
		return
	if _fire_return_prone:
		_applied_position_state = PositionState.DOWN
		_anim.scale = _prone_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
		_prone_marker.visible = false
	else:
		_applied_position_state = PositionState.UP
		_anim.scale = _standing_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_standing_sprite_offset()
		_prone_marker.visible = false
	_locomotion_walking = true
	_play_locomotion(_body_world_direction(), false)
	_sync_facing_arrow_visibility()


func _finish_throw_grenade_idle() -> void:
	if _throw_return_prone:
		_applied_position_state = PositionState.DOWN
		_anim.scale = _prone_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
		_prone_marker.visible = false
	else:
		_applied_position_state = PositionState.UP
		_anim.scale = _standing_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_standing_sprite_offset()
		_prone_marker.visible = false
	_locomotion_walking = true
	var idle_dir := _throw_world_direction if not _throw_world_direction.is_empty() else _locomotion_direction
	_play_locomotion(idle_dir if not idle_dir.is_empty() else "n", false)
	_sync_facing_arrow_visibility()


func _finish_survivable_hit_reaction(anim_name: String) -> void:
	_hit_reaction_active = false
	var transition := "→ prone idle" if _hit_return_prone else "→ standing idle"
	_log_hit_completion(anim_name, transition)
	## Resume stance idle (paused walk frame). Never invent a substitute hit sprite.
	if _hit_return_prone:
		_applied_position_state = PositionState.DOWN
		_anim.scale = _prone_sprite_scale()
		_anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
		_prone_marker.visible = false
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
	_throw_grenade_active = false
	_fire_active = false
	_fire_restart_pending = false
	_apply_dead_visual(false)


func _show_dead_static(direction: String) -> void:
	var world_dir := direction if not direction.is_empty() else "n"
	_corpse_world_direction = world_dir
	var display_dir := _idle_display_direction(world_dir)
	var family := _death_sprite_family.strip_edges().to_upper()
	var anim_name := ""
	if not family.is_empty():
		anim_name = "dead_%s_%s" % [family, display_dir]
		if _anim.sprite_frames == null or not _anim.sprite_frames.has_animation(anim_name):
			var digit := AnimationDatabase.source_direction_digit(display_dir)
			var expected := "res://assets/sprites/%s/dead_fallen/%s%dA.png" % [
				"us_soldier" if team_id == Team.USA else "german_soldier",
				family,
				digit,
			]
			push_error(
				"Soldier: missing dead_static animation %s (faction=%s family=%s dir=%s path=%s)"
				% [anim_name, Team.display_name(team_id), family, display_dir, expected]
			)
			anim_name = "dead_%s" % display_dir
	else:
		anim_name = "dead_%s" % display_dir
	_play_animation(anim_name)
	_anim.pause()
	_anim.frame = 0
	_log_dead_static_once(world_dir, display_dir, anim_name)


func _remap_dead_for_camera() -> void:
	if not _is_dead:
		return
	var world_dir := _corpse_world_direction
	if world_dir.is_empty():
		world_dir = UsSoldierSpriteFrames.direction_from_step(_last_applied_facing)
	_show_dead_static(world_dir)


func _corpse_direction_for_state(state: SoldierState) -> String:
	if not _corpse_world_direction.is_empty():
		return _corpse_world_direction
	return UsSoldierSpriteFrames.direction_from_step(state.facing_direction)


func _log_dead_static_once(world_dir: String, display_dir: String, anim_name: String) -> void:
	if not DEBUG_DEAD_STATIC or _dead_static_logged:
		return
	_dead_static_logged = true
	var family := _death_sprite_family if not _death_sprite_family.is_empty() else "?"
	var source_dir := AnimationDatabase.source_direction_digit(display_dir)
	var frame_stem := "%s%dA" % [family, source_dir] if family != "?" else anim_name
	GameLog.log_system(
		"dead_static | %s | soldier_id=%d | family=%s | world_dir=%s | camera_rotation=%d | source_dir=%d | frame=%s"
		% [
			Team.display_name(team_id).to_lower(),
			soldier_id,
			family,
			world_dir.to_upper(),
			IsometricGrid.facet_camera_direction_degrees(),
			source_dir,
			frame_stem,
		]
	)


## Debug snapshot for corpse variant + camera remap validation.
func dump_dead_static_validation() -> Dictionary:
	var world_dir := _corpse_world_direction
	if world_dir.is_empty():
		world_dir = UsSoldierSpriteFrames.direction_from_step(_last_applied_facing)
	var cam := IsometricGrid.facet_camera_direction_degrees()
	var display_dir := AnimationDatabase.display_direction(world_dir, cam)
	return {
		"soldier_id": soldier_id,
		"team_id": team_id,
		"is_dead": _is_dead,
		"death_sprite_family": _death_sprite_family,
		"world_facing": _last_applied_facing,
		"world_dir": world_dir,
		"camera_rotation": cam,
		"display_dir": display_dir,
		"source_dir": AnimationDatabase.source_direction_digit(display_dir),
		"active_animation": str(_anim.animation) if _anim != null else "",
	}


## Debug helper: jump past hit/fall straight to the selected static corpse.
func debug_force_dead_static() -> void:
	_finish_death_sequence()


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
		"throw_grenade":
			return _throw_source_family()
		"fire_standing", "fire_prone", "corner_fire_left", "corner_fire_right":
			return _fire_source_family()
		"idle_standing", "corner_idle_left", "corner_idle_right":
			return _idle_source_family()
		"idle_breathing", "idle_rest_1", "idle_rest_2", "idle_rest_3":
			return _idle_source_family()
		"corner_aim_left":
			return "GLCAS" if team_id == Team.GERMANY else "ALCAS"
		"corner_aim_right":
			return "GRCAS" if team_id == Team.GERMANY else "ARCAS"
		"corner_peek_left":
			return "GLPKA" if team_id == Team.GERMANY else "ALPKA"
		"corner_peek_right":
			return "GRPKA" if team_id == Team.GERMANY else "ARPKA"
		"corner_peek_enter_left", "corner_peek_exit_left":
			return "GLCPA" if team_id == Team.GERMANY else "ALCPA"
		"corner_peek_enter_right", "corner_peek_exit_right":
			return "GRCPA" if team_id == Team.GERMANY else "ARCPA"
		"idle_prone":
			return _prone_idle_source_family()
		"transition_standing_to_prone", "transition_prone_to_standing":
			return "APRNA" if team_id == Team.USA else "GPRNA"
		"crawl":
			return "APMOA" if team_id == Team.USA else "GPMOA"
		_:
			return "?"


func _log_throw_grenade(anim_name: String, status: String) -> void:
	if not DEBUG_THROW_GRENADE:
		return
	var cam_rot := IsometricGrid.facet_camera_direction_degrees()
	var display_dir := _throw_display_direction()
	var family_id := (
		UsSoldierSpriteFrames.DB_FAMILY_USA
		if team_id == Team.USA
		else UsSoldierSpriteFrames.DB_FAMILY_GERMANY
	)
	var frame_paths := AnimationDatabase.get_direction_frames(
		family_id,
		"throw_grenade",
		display_dir,
	)
	var fps := 0.0
	var frame_idx := -1
	var frame_letter := "?"
	if _anim.sprite_frames != null and _anim.sprite_frames.has_animation(anim_name):
		fps = _anim.sprite_frames.get_animation_speed(anim_name)
		frame_idx = _anim.frame
		if frame_idx >= 0 and frame_idx < 26:
			frame_letter = String.chr(ord("A") + frame_idx)
	var release_frame := GameplayPolicies.grenade.throw_release_frame_for_team(team_id)
	GameLog.log_system(
		"[ThrowGrenade] status=%s faction=%s semantic=throw_grenade family=%s anim=%s world_dir=%s cam_rot=%d resolved_dir=%s frame=%d(%s) fps=%.1f release_frame=%d release_fired=%s frames=%d"
		% [
			status,
			Team.display_name(team_id),
			_throw_source_family(),
			anim_name,
			_throw_world_direction,
			cam_rot,
			display_dir,
			frame_idx,
			frame_letter,
			fps,
			release_frame,
			_throw_release_fired,
			frame_paths.size(),
		]
	)
	if not frame_paths.is_empty():
		GameLog.log_system(
			"[ThrowGrenade] ordered_frames=%s ... %s"
			% [frame_paths[0], frame_paths[frame_paths.size() - 1]]
		)


func _log_fire_anim(anim_name: String, status: String) -> void:
	if not DEBUG_FIRE_ANIM:
		return
	var cam_rot := IsometricGrid.facet_camera_direction_degrees()
	var display_dir := _fire_display_direction()
	var family_id := (
		UsSoldierSpriteFrames.DB_FAMILY_USA
		if team_id == Team.USA
		else UsSoldierSpriteFrames.DB_FAMILY_GERMANY
	)
	var frame_paths := AnimationDatabase.get_direction_frames(family_id, _fire_semantic, display_dir)
	var fps := 0.0
	var frame_idx := -1
	var frame_letter := "?"
	if _anim.sprite_frames != null and _anim.sprite_frames.has_animation(anim_name):
		fps = _anim.sprite_frames.get_animation_speed(anim_name)
		frame_idx = _anim.frame
		if frame_idx >= 0 and frame_idx < 26:
			frame_letter = String.chr(ord("A") + frame_idx)
	GameLog.log_system(
		"[FireAnim] status=%s faction=%s stance=%s semantic=%s family=%s anim=%s world_dir=%s cam_rot=%d resolved_dir=%s frame=%d(%s) fps=%.1f shot_events=%d visual_triggers=%d frames=%d"
		% [
			status,
			Team.display_name(team_id),
			"DOWN" if _fire_return_prone else "UP",
			_fire_semantic,
			_fire_source_family(),
			anim_name,
			_locomotion_direction,
			cam_rot,
			display_dir,
			frame_idx,
			frame_letter,
			fps,
			GameplayPolicies.fire_anim.authoritative_shot_event_count,
			GameplayPolicies.fire_anim.visual_firing_trigger_count,
			frame_paths.size(),
		]
	)
	if not frame_paths.is_empty():
		GameLog.log_system(
			"[FireAnim] ordered_frames=%s"
			% ", ".join(frame_paths)
		)


## --- Presentation-only standing idle fidgets (OG: static pose + rare oneshots) ---

func _standing_fidget_block_reason() -> String:
	if not _uses_og_frames():
		return "no_og_frames"
	if _is_dead:
		return "dead"
	if _is_moving:
		return "moving"
	if _presentation_stunned:
		return "stunned"
	if _stun_phase != StunPresPhase.NONE:
		return "stun_phase"
	if _blocks_action_override():
		return "action_override"
	if _fire_aim_hold_active or _fire_aim_enter_active:
		if _fire_active:
			return "fire_active_with_aim_hold"
		return ""  ## stale hold — caller clears before re-check
	if _applied_position_state == PositionState.DOWN:
		return "prone"
	if _idle_peek_side != CoverSystem.PeekSide.NONE:
		return "corner_peek"
	if _idle_fidget_active:
		return "fidget_active"
	return ""


func _log_idle_fidget_state(tag: String, anim_name: String = "") -> void:
	if not DEBUG_IDLE_STANDING:
		return
	var world_dir := _standing_idle_world_direction()
	var display_dir := _idle_display_direction(world_dir)
	var block := _standing_fidget_block_reason()
	var speed := _anim.speed_scale if _anim != null else 1.0
	var active_anim := str(_anim.animation) if _anim != null else ""
	GameLog.log_system(
		(
			"[IdleFidget] %s team=%d soldier=%d processing=%s wait=%.2f fidget=%s "
			+ "block=%s locomotion_dir=%s standing_dir=%s display_dir=%s "
			+ "anim=%s active=%s speed_scale=%.2f"
		)
		% [
			tag,
			team_id,
			soldier_id,
			is_processing(),
			_idle_wait_remaining_sec,
			_idle_fidget_active,
			block if block.is_empty() else block,
			_locomotion_direction,
			world_dir,
			display_dir,
			anim_name,
			active_anim,
			speed,
		]
	)


func _can_standing_fidget() -> bool:
	if (
		not _uses_og_frames()
		or _is_dead
		or _is_moving
		or _presentation_stunned
		or _stun_phase != StunPresPhase.NONE
	):
		return false
	if _blocks_action_override():
		return false
	if _fire_aim_hold_active or _fire_aim_enter_active:
		if not _fire_active:
			_clear_fire_aim_hold(false, "fidget_stale_hold")
		else:
			return false
	## Allow unset (-1) during first sync: facing can run before position visual.
	if _applied_position_state == PositionState.DOWN:
		return false
	if _idle_peek_side != CoverSystem.PeekSide.NONE:
		return false
	if _idle_fidget_active:
		return false
	return true


func _maybe_arm_standing_idle_timer() -> void:
	## Open standing idle only — corner CIS / crouch use their own loops, no fidgets.
	if _idle_fidget_active or _idle_wait_remaining_sec > 0.0:
		return
	if _post_shot_crouch_remaining > 0.0:
		return
	if not _can_standing_fidget():
		return
	if _idle_standing_semantic() != "idle_standing":
		return
	_arm_standing_idle_timer(true)


func _ensure_standing_idle_timer() -> void:
	## Keep an existing wait; only arm when stopped (facing refresh must not reset it).
	## Always keep _process on while a wait is armed — stop_movement / sync must not freeze it.
	if _idle_wait_remaining_sec > 0.0:
		set_process(true)
		return
	_arm_standing_idle_timer(true)


func _arm_standing_idle_timer(force_restart: bool = true) -> void:
	if _fire_aim_hold_active or _fire_aim_enter_active:
		if not _fire_active:
			_clear_fire_aim_hold(false, "fidget_rearm_stale_hold")
	if not _can_standing_fidget():
		_idle_wait_remaining_sec = -1.0
		_log_idle_fidget_state("arm_blocked")
		return
	if not force_restart and _idle_wait_remaining_sec > 0.0:
		return
	_idle_wait_remaining_sec = GameplayPolicies.idle_anim.random_fidget_delay_sec(_idle_rng)
	set_process(true)
	_log_idle_fidget_state("arm")


func _tick_standing_idle_wait(delta: float) -> void:
	if _idle_fidget_active:
		return
	if _idle_wait_remaining_sec < 0.0:
		return
	if not _can_standing_fidget():
		## Permanent blocks — release wait; open idle will re-arm via _maybe_arm_standing_idle_timer.
		if (
			_idle_peek_side != CoverSystem.PeekSide.NONE
			or _applied_position_state == PositionState.DOWN
		):
			_idle_wait_remaining_sec = -1.0
			_log_idle_fidget_state("tick_blocked_permanent")
		else:
			_log_idle_fidget_state("tick_blocked_transient")
		return
	_idle_wait_remaining_sec -= delta
	if _idle_wait_remaining_sec > 0.0:
		return
	_idle_wait_remaining_sec = -1.0
	if not GameplayPolicies.idle_anim.should_play_fidget(_idle_rng):
		_log_idle_fidget_state("tick_chance_miss")
		_arm_standing_idle_timer(true)
		return
	_play_standing_idle_fidget()


func _cancel_standing_idle(resume_hold_pose: bool = true) -> void:
	_idle_wait_remaining_sec = -1.0
	var was_fidget := _idle_fidget_active
	_idle_fidget_active = false
	_idle_fidget_semantic = ""
	if was_fidget:
		_reset_idle_fidget_play_speed()
	if not resume_hold_pose:
		_post_shot_crouch_remaining = 0.0
		return
	if not was_fidget:
		return
	_log_idle_fidget_state("cancel_fidget_resume_hold")
	## Mid-fidget interrupt returning to idle: snap ABRLA/GBRLA pose A.
	if (
		_is_dead
		or _presentation_stunned
		or _stun_phase != StunPresPhase.NONE
		or _blocks_action_override()
		or _is_moving
		or _applied_position_state == PositionState.DOWN
		or _fire_active
		or _fire_aim_hold_active
		or _fire_aim_enter_active
	):
		return
	var world_dir := _standing_idle_world_direction()
	_play_idle_standing(world_dir)


## Drop open idle (wait, fidget, post-shot crouch) so combat / move / stance can take over.
func _interrupt_standing_idle_for_action() -> void:
	_cancel_standing_idle(false)


func _is_idle_fidget_anim_name(anim_name: String) -> bool:
	for semantic in GameplayPolicies.idle_anim.FIDGET_SEMANTICS:
		if anim_name.begins_with("%s_" % semantic):
			return true
	return false


func _is_fire_aim_hold_anim_name(anim_name: String) -> bool:
	return (
		anim_name.begins_with("aim_standing_hold_")
		or anim_name.begins_with("aim_prone_hold_")
	)


func _is_open_fire_anim_name(anim_name: String) -> bool:
	return (
		anim_name.begins_with("fire_standing_")
		or anim_name.begins_with("fire_prone_")
		or anim_name.begins_with("corner_fire_")
	)


func _is_stale_combat_oneshot_anim_name(anim_name: String) -> bool:
	if _is_open_fire_anim_name(anim_name):
		return true
	if anim_name.begins_with("aim_standing_") and not anim_name.begins_with("aim_standing_hold_"):
		return true
	if anim_name.begins_with("aim_prone_") and not anim_name.begins_with("aim_prone_hold_"):
		return true
	return false


func _clear_stale_open_fire_pose() -> void:
	## Fire/aim oneshots (ASFIA, ASAPA, CFA, …) are play_fire / peek only — never idle.
	if _fire_active or _corner_phase == CornerPresPhase.FIRING:
		return
	var anim_name := str(_anim.animation)
	if not _is_stale_combat_oneshot_anim_name(anim_name):
		return
	if _anim.is_playing():
		return
	if DEBUG_IDLE_STANDING:
		GameLog.log_system(
			"[IdleFidget] clear stale fire pose team=%d soldier=%d anim=%s"
			% [team_id, soldier_id, anim_name]
		)
	var world_dir := _standing_idle_world_direction()
	if _applied_position_state == PositionState.DOWN:
		_play_idle_prone(world_dir)
	else:
		_play_idle_standing(world_dir)


func _play_standing_idle_fidget() -> void:
	if not _can_standing_fidget() or _anim == null or _anim.sprite_frames == null:
		_arm_standing_idle_timer(true)
		return
	var semantic := GameplayPolicies.idle_anim.pick_fidget_semantic(_idle_rng)
	var world_dir := _standing_idle_world_direction()
	var display_dir := _idle_display_direction(world_dir)
	var anim_name := "%s_%s" % [semantic, display_dir]
	if not _anim.sprite_frames.has_animation(anim_name):
		push_warning("Soldier: missing idle fidget %s" % anim_name)
		_arm_standing_idle_timer(true)
		return
	var frame_count := _anim.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		_arm_standing_idle_timer(true)
		return
	_idle_wait_remaining_sec = -1.0
	_idle_fidget_active = true
	_idle_fidget_semantic = semantic
	set_process(true)
	_apply_idle_fidget_play_speed(anim_name)
	_anim.play(anim_name)
	_log_idle_standing(anim_name, "FIDGET_PLAY")
	_log_idle_fidget_state("play", anim_name)


func _apply_idle_fidget_play_speed(anim_name: String) -> void:
	var policy_fps := GameplayPolicies.idle_anim.fidget_fps
	if policy_fps <= 0.0 or _anim.sprite_frames == null:
		_anim.speed_scale = 1.0
		return
	var db_fps := _anim.sprite_frames.get_animation_speed(anim_name)
	if db_fps <= 0.0:
		_anim.speed_scale = 1.0
		return
	_anim.speed_scale = policy_fps / db_fps


func _reset_idle_fidget_play_speed() -> void:
	if _anim != null:
		_anim.speed_scale = 1.0


func _finish_standing_idle_fidget(anim_name: String) -> void:
	_idle_fidget_active = false
	_idle_fidget_semantic = ""
	_reset_idle_fidget_play_speed()
	_log_idle_standing(anim_name, "FIDGET_COMPLETE → HOLD_POSE")
	## Re-arm before returning to hold pose so _process stays enabled for the next tick.
	_arm_standing_idle_timer(true)
	var world_dir := _standing_idle_world_direction()
	_play_idle_standing(world_dir)
	_log_idle_fidget_state("finish", anim_name)


func _log_idle_standing(anim_name: String, status: String) -> void:
	if not DEBUG_IDLE_STANDING:
		return
	var cam_rot := IsometricGrid.facet_camera_direction_degrees()
	var world_dir := _standing_idle_world_direction()
	var display_dir := _idle_display_direction(world_dir)
	var family_id := (
		UsSoldierSpriteFrames.DB_FAMILY_USA
		if team_id == Team.USA
		else UsSoldierSpriteFrames.DB_FAMILY_GERMANY
	)
	var frame_paths := AnimationDatabase.get_direction_frames(family_id, "idle_standing", display_dir)
	var fps := 0.0
	var loop := false
	var frame_count := 0
	if _anim.sprite_frames != null and _anim.sprite_frames.has_animation(anim_name):
		fps = _anim.sprite_frames.get_animation_speed(anim_name)
		loop = _anim.sprite_frames.get_animation_loop(anim_name)
		frame_count = _anim.sprite_frames.get_frame_count(anim_name)
	var digit := -1
	match display_dir:
		"w":
			digit = 1
		"sw":
			digit = 2
		"s":
			digit = 3
		"se":
			digit = 4
		"e":
			digit = 5
		"ne":
			digit = 6
		"n":
			digit = 7
		"nw":
			digit = 8
	var first_name := frame_paths[0].get_file() if not frame_paths.is_empty() else "?"
	var last_name := frame_paths[frame_paths.size() - 1].get_file() if not frame_paths.is_empty() else "?"
	GameLog.log_system(
		"idle_standing | %s | %s | world_dir=%s | camera_rotation=%d | source_dir=%d | fps=%.0f | loop=%s | frames=%d | %s..%s | status=%s anim=%s"
		% [
			Team.display_name(team_id).to_lower(),
			_idle_source_family(),
			world_dir.to_upper(),
			cam_rot,
			digit,
			fps,
			str(loop).to_lower(),
			frame_count,
			first_name,
			last_name,
			status,
			anim_name,
		]
	)


func _log_stance_transition(anim_name: String, status: String) -> void:
	if not DEBUG_STANCE_TRANSITION:
		return
	var cam_rot := IsometricGrid.facet_camera_direction_degrees()
	var world_dir := (
		_stance_transition_world_direction
		if not _stance_transition_world_direction.is_empty()
		else (_locomotion_direction if not _locomotion_direction.is_empty() else "n")
	)
	var display_dir := _idle_display_direction(world_dir)
	var semantic := _stance_transition_semantic
	if semantic.is_empty():
		if str(anim_name).begins_with("idle_prone_"):
			semantic = "idle_prone"
		else:
			var parts := str(anim_name).rsplit("_", true, 1)
			semantic = parts[0] if parts.size() == 2 else "stance"
	var family := _source_family_for_semantic(semantic)
	var family_id := (
		UsSoldierSpriteFrames.DB_FAMILY_USA
		if team_id == Team.USA
		else UsSoldierSpriteFrames.DB_FAMILY_GERMANY
	)
	var frame_paths := AnimationDatabase.get_direction_frames(family_id, semantic, display_dir)
	var fps := 0.0
	var loop := false
	var frame_count := 0
	if _anim.sprite_frames != null and _anim.sprite_frames.has_animation(anim_name):
		fps = _anim.sprite_frames.get_animation_speed(anim_name)
		loop = _anim.sprite_frames.get_animation_loop(anim_name)
		frame_count = _anim.sprite_frames.get_frame_count(anim_name)
	var first_name := frame_paths[0].get_file() if not frame_paths.is_empty() else "?"
	var last_name := frame_paths[frame_paths.size() - 1].get_file() if not frame_paths.is_empty() else "?"
	GameLog.log_system(
		"%s | %s | %s | world_dir=%s | camera_rotation=%d | resolved_dir=%s | fps=%.0f | loop=%s | frames=%d | %s..%s | status=%s anim=%s"
		% [
			semantic,
			Team.display_name(team_id).to_lower(),
			family,
			world_dir.to_upper(),
			cam_rot,
			display_dir,
			fps,
			str(loop).to_lower(),
			frame_count,
			first_name,
			last_name,
			status,
			anim_name,
		]
	)


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
	var cam_rot := IsometricGrid.facet_camera_direction_degrees()
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
