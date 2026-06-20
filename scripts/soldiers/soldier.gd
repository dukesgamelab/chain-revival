class_name Soldier
extends Node2D
## Presentation only: sprites, selection, facing arrow, movement animation.
##
## Does NOT mutate SoldierState. Emits movement signals so ActionResolver can update
## authoritative position via GameState when each animation step completes.

const TEXTURE_USA_NE := preload("res://assets/sprites/us_soldier_ne.png")
const TEXTURE_USA_NW := preload("res://assets/sprites/us_soldier_nw.png")
const TEXTURE_USA_SE := preload("res://assets/sprites/us_soldier_se.png")
const TEXTURE_USA_SW := preload("res://assets/sprites/us_soldier_sw.png")
const TEXTURE_GERMANY := preload("res://assets/sprites/soldier_germany.svg")

const _USA_TEXTURES: Dictionary = {
	"ne": TEXTURE_USA_NE,
	"nw": TEXTURE_USA_NW,
	"se": TEXTURE_USA_SE,
	"sw": TEXTURE_USA_SW,
}
## Match directional PNG art to the 32×48 German placeholder footprint.
const _GERMAN_SPRITE_SIZE := Vector2(32.0, 48.0)
const _USA_SPRITE_SIZE := Vector2(64.0, 104.0)
const _USA_SPRITE_SCALE := Vector2(
	_GERMAN_SPRITE_SIZE.x / _USA_SPRITE_SIZE.x,
	_GERMAN_SPRITE_SIZE.y / _USA_SPRITE_SIZE.y,
)
## Slightly larger than the German placeholder footprint.
const _USA_SIZE_BOOST := 1.15
const _PRONE_SPRITE_SCALE := Vector2(1.15, 0.42)
## Visual-only sprite shift so feet sit on the tile center (Node2D stays on grid center).
const SPRITE_OFFSET_STANDING := Vector2(0, -24)
const SPRITE_OFFSET_PRONE := Vector2(0, -10)

signal movement_step_reached(team_id: int, soldier_id: int, tile: Vector2i, step_delta: Vector2i)
signal movement_finished(team_id: int, soldier_id: int)

var soldier_id: int = 1
var team_id: int = Team.USA

@export var move_speed := 95.0

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
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _selection_marker: Polygon2D = $SelectionMarker
@onready var _facing_arrow: Line2D = $FacingArrow
@onready var _dead_marker: Line2D = $DeadMarker
@onready var _prone_marker: Line2D = $ProneMarker
@onready var _weapon_badge: Label = $WeaponBadge


func _ready() -> void:
	set_process(false)


## Apply authoritative gameplay state to this sprite (position, facing, selection).
func sync_from_state(state: SoldierState, is_selected: bool, is_spotted: bool = true) -> void:
	soldier_id = state.soldier_id
	team_id = state.team_id
	_is_dead = state.is_dead

	if state.is_dead:
		stop_movement()
		position = IsometricGrid.grid_to_world(state.grid_position)
		_facing_from_cell = state.grid_position
		_apply_directional_sprite(state.facing_direction, _facing_from_cell)
		_apply_dead_visual(is_selected)
		return
	_dead_marker.visible = false
	if not _is_moving:
		position = IsometricGrid.grid_to_world(state.grid_position)
	_facing_from_cell = state.grid_position
	_apply_facing(state.facing_direction, _facing_from_cell)
	_apply_position_visual(state)
	_apply_weapon_badge(state)
	_apply_spotted_visual(is_selected, is_spotted)
	set_selected(is_selected)


func _apply_spotted_visual(is_selected: bool, is_spotted: bool) -> void:
	if _is_dead:
		return
	if is_spotted:
		if is_selected:
			_sprite.modulate = Color(1.14, 1.14, 1.08, 1.0)
		else:
			_sprite.modulate = Color.WHITE
	else:
		_sprite.modulate = Color(0.55, 0.55, 0.58, 0.45)


func set_selected(is_selected: bool) -> void:
	if _is_dead:
		_selection_marker.visible = false
		return
	_selection_marker.visible = is_selected
	_selection_marker.polygon = IsometricGrid.diamond_corners(Vector2.ZERO)
	_apply_directional_sprite(_last_applied_facing, _facing_from_cell)

func _apply_dead_visual(_is_selected: bool) -> void:
	_applied_position_state = PositionState.DOWN
	_facing_arrow.visible = false
	_prone_marker.visible = false
	_dead_marker.visible = true
	_weapon_badge.visible = false
	_selection_marker.visible = false
	_sprite.scale = _prone_sprite_scale()
	_sprite.position = Vector2.ZERO
	_sprite.offset = SPRITE_OFFSET_PRONE
	_apply_directional_sprite(_last_applied_facing, _facing_from_cell)
	_sprite.modulate = Color(0.38, 0.38, 0.38, 0.85)


func _apply_position_visual(state: SoldierState) -> void:
	if not _is_dead and state.position_state == _applied_position_state:
		return
	_applied_position_state = state.position_state
	_sprite.position = Vector2.ZERO
	if state.position_state == PositionState.DOWN:
		_sprite.scale = _prone_sprite_scale()
		_sprite.offset = SPRITE_OFFSET_PRONE
		_facing_arrow.visible = false
		_prone_marker.visible = true
	else:
		_sprite.scale = _standing_sprite_scale()
		_sprite.offset = SPRITE_OFFSET_STANDING
		_facing_arrow.visible = true
		_prone_marker.visible = false


func _standing_sprite_scale() -> Vector2:
	if team_id == Team.USA:
		return _USA_SPRITE_SCALE * _USA_SIZE_BOOST
	return Vector2.ONE


func _prone_sprite_scale() -> Vector2:
	if team_id == Team.USA:
		var base := _USA_SPRITE_SCALE * _USA_SIZE_BOOST
		return Vector2(base.x * _PRONE_SPRITE_SCALE.x, base.y * _PRONE_SPRITE_SCALE.y)
	return _PRONE_SPRITE_SCALE


func _apply_weapon_badge(state: SoldierState) -> void:
	if _weapon_badge == null:
		return
	_weapon_badge.visible = true
	_weapon_badge.text = WeaponType.short_code(state.weapon_type)
	_weapon_badge.tooltip_text = state.weapon_name


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
	_is_moving = false
	_path.clear()
	_path_index = 0
	set_process(false)


func follow_path(path: Array[Vector2i], speed_multiplier: float = 1.0) -> void:
	## Presentation-only path animation. Authoritative grid_position updates via
	## movement_step_reached → ActionResolver.on_movement_step.
	if _is_dead or path.size() <= 1:
		return

	_speed_multiplier = speed_multiplier
	_path = path
	_path_index = 1
	_is_moving = true
	_previous_grid_pos = _path[0]
	position = IsometricGrid.grid_to_world(_path[0])
	_move_target_world = IsometricGrid.grid_to_world(_path[_path_index])
	set_process(true)


func _process(delta: float) -> void:
	# Interpolates Node2D.position only; does not write SoldierState.grid_position.
	if not _is_moving or _is_dead:
		return

	var to_target := _move_target_world - position
	var distance := to_target.length()
	var step_delta := _path[_path_index] - _previous_grid_pos
	_apply_facing(FacingDirection.from_step(step_delta), _previous_grid_pos)

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
		movement_finished.emit(team_id, soldier_id)
	else:
		_move_target_world = IsometricGrid.grid_to_world(_path[_path_index])


## Point the placeholder arrow along the isometric screen direction for grid facing.
func _apply_facing(facing: Vector2i, from_cell: Vector2i = Vector2i.ZERO) -> void:
	_last_applied_facing = facing
	_facing_from_cell = from_cell
	_apply_directional_sprite(facing, from_cell)
	if _facing_arrow == null:
		return
	_facing_arrow.rotation_degrees = IsometricGrid.grid_facing_to_degrees(facing, from_cell)


## Choose USA directional art from authoritative grid facing; Germany keeps placeholder SVG.
func _apply_directional_sprite(facing: Vector2i, from_cell: Vector2i) -> void:
	if _sprite == null:
		return
	if team_id == Team.USA:
		var quarter: String = IsometricGrid.grid_facing_to_diagonal_quarter(facing, from_cell)
		var texture: Texture2D = _USA_TEXTURES.get(quarter, TEXTURE_USA_SE) as Texture2D
		_sprite.texture = texture
	else:
		_sprite.texture = TEXTURE_GERMANY