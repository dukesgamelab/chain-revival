extends Node2D
## Root scene: presentation shell for the authoritative game loop.
##
## Architecture:
##   Input/UI → CommandRouter → ActionResolver → GameState (truth) → Soldier visuals
##
## Ownership: GameState + ObjectRegistry hold authoritative data. This scene owns
## Soldier node views in _soldier_views only — never store node refs in the registry.
## main.gd must not mutate SoldierState or MapData directly. Use CommandRouter for commands.

const SoldierScene := preload("res://scenes/soldier.tscn")
const GameSessionClass := preload("res://scripts/core/game_session.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")
const GameSaveClass := preload("res://scripts/core/game_save.gd")
const MapDataClass := preload("res://scripts/map/map_data.gd")
const MovementModeClass := preload("res://scripts/enums/movement_mode.gd")
const PositionStateClass := preload("res://scripts/enums/position_state.gd")
const FireControlCommandClass := preload("res://scripts/commands/fire_control_command.gd")
const FireControlStateClass := preload("res://scripts/enums/fire_control_state.gd")
const LosVisualizerClass := preload("res://scripts/effects/los_visualizer.gd")
const FireteamLoadoutClass := preload("res://scripts/soldiers/fireteam_loadout.gd")
const LOSSystemClass := preload("res://scripts/combat/los_system.gd")
const ConeOfFireClass := preload("res://scripts/combat/cone_of_fire.gd")
const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")
const ActionResultClass := preload("res://scripts/core/action_result.gd")
const CommandContextClass := preload("res://scripts/core/command_context.gd")
const MapEditorClass := preload("res://scripts/map/map_editor.gd")
const SimpleAIControllerClass := preload("res://scripts/ai/simple_ai_controller.gd")

@onready var _world: MapWorldView = $World
@onready var _map_background: Node2D = $World/MapBackground
@onready var _grass_layer: GrassTerrainLayer = $World/GrassTerrainLayer
@onready var _original_ground_layer: OriginalGroundLayer = $World/OriginalGroundLayer
@onready var _floor_layer: OriginalFloorLayer = $World/OriginalFloorLayer
@onready var _underlay_layer: OriginalUnderlayLayer = $World/OriginalUnderlayLayer
@onready var _iso_map: IsometricMap = $World/IsometricMap
@onready var _depth_sorted: DepthSortedLayer = $World/DepthSorted
@onready var _label_layer: OriginalLabelLayer = $World/OriginalLabelLayer
@onready var _coc_debug_overlay: CocTileDebugOverlay = $World/CocTileDebugOverlay
@onready var _tracers_root: Node2D = $World/Tracers
@onready var _los_visualizer: LosVisualizerClass = $World/LosVisualizer
@onready var _camera: MapCamera = $Camera2D
@onready var _command_bar: CommandBar = $UI/CommandBar
var _return_to_editor_on_exit: bool = false

var _map_data = MapDataClass.create_default()
var _session: GameSession = GameSessionClass.new([], [])
var _game_state: GameStateClass

var _soldier_views: Dictionary = {}
var _move_targeting: bool = false
var _squad_move_targeting: bool = false
var _active_movement_mode: int = MovementModeClass.RUN
var _move_soldier_id: int = 1
var _fire_at_mode: bool = false
var _squad_fire_at_mode: bool = false
var _fire_at_soldier_id: int = 1
var _fire_at_engaged: bool = false
var _face_mode: bool = false
var _face_soldier_id: int = 1
var _grenade_mode: bool = false
var _grenade_soldier_id: int = 1
var _map_edit_mode: bool = false
var _map_edit_palette: int = MapEditorClass.Palette.WALL
var _sim_accum_sec: float = 0.0
var _combat_scan_accum_msec: int = 0
var _grass_layer_visible: bool = true
var _simple_ai: SimpleAIControllerClass


func _ready() -> void:
	_bootstrap_simulation()
	_log_network_mode()
	LOSSystemClass.apply_debug_settings()
	RenderingServer.set_default_clear_color(Color(0.22, 0.38, 0.18, 1.0))
	_camera.make_current()
	_load_map_data()
	_init_session_from_spawns()
	_connect_command_bar()
	_apply_multiplayer_side_lock()
	_apply_map_presentation()
	_center_camera_on_map()
	_spawn_all_soldier_views()
	_log_fireteam_loadouts()
	_command_bar.set_active_team(_session.active_team_id)
	_refresh_all_views()
	_show_startup_status()
	_start_simple_ai()


## Seeded RNG + sim clock for reproducible gameplay timing (not wall-clock).
func _bootstrap_simulation() -> void:
	SimulationClock.reset()
	SimulationClock.reset_tick_defaults()
	GameRandom.begin_match(GameRandom.DEFAULT_SEED)
	GameplayPolicies.reset_all_to_defaults()
	GameplayPolicies.reload_from_config()
	_sim_accum_sec = 0.0
	_combat_scan_accum_msec = 0


func _start_simple_ai() -> void:
	_simple_ai = SimpleAIControllerClass.new()
	## Defer one frame so soldier views finish entering the tree before paths animate.
	call_deferred("_run_simple_ai_opening")


func _run_simple_ai_opening() -> void:
	if _simple_ai == null:
		return
	_simple_ai.on_match_started(_game_state, _map_data, _apply_move_command)


func _log_network_mode() -> void:
	var mode_name := GameMode.display_name(GameModeManager.get_mode())
	GameLog.log_system("Current Mode: %s" % mode_name)
	if GameModeManager.is_local_multiplayer():
		if NetworkClient.is_connected_to_server():
			GameLog.log_system("[NetworkClient] Already connected to server.")
		else:
			NetworkClient.connect_for_local_multiplayer()
	else:
		GameLog.log_system("[NetworkClient] Offline mode — no server connection.")


func _show_startup_status() -> void:
	if _map_data != null and _map_data.is_original_visual_map():
		_command_bar.show_status(
			"%s loaded. Rotate Q/E. --test-map switches maps."
			% str(_map_data.map_name)
		)
		return
	if GameModeManager.is_local_multiplayer() and PlayerSides.has_assignment():
		_command_bar.show_status(
			"Controlling %s. Fire At: click an enemy to open fire. Right-click cancels."
			% PlayerSides.display_side_name()
		)
	else:
		_command_bar.show_status(
			"Press 1 = USA, 2 = Germany. Fire At: click an enemy to open fire. Right-click cancels."
		)


func _apply_multiplayer_side_lock() -> void:
	if not GameModeManager.is_local_multiplayer():
		return
	if not PlayerSides.has_assignment():
		push_error("Local multiplayer started without an assigned side.")
		return
	_session.set_active_team(PlayerSides.assigned_team_id)
	_command_bar.set_active_team(PlayerSides.assigned_team_id)
	var fireteam: Fireteam = _session.get_active_fireteam()
	_repair_fireteam_selection(fireteam)
	_command_bar.sync_selected_soldier(fireteam.selected_soldier_id)
	GameLog.log_system(
		"[PlayerSide] Locked control to %s." % PlayerSides.display_side_name()
	)


func _log_fireteam_loadouts() -> void:
	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			var message := FireteamLoadoutClass.assignment_message(
				soldier_state.team_id,
				soldier_state.soldier_id,
				soldier_state.weapon_name,
			)
			GameLog.log_system(message)


func _process(delta: float) -> void:
	## Sim first (authoritative), then presentation so views reflect the latest tick.
	_step_fixed_simulation(delta)

	if not _map_edit_mode:
		_update_los_preview()
		_update_command_bar_hit_columns()
		if _any_soldier_moving():
			_refresh_all_views()


## Advance SimulationClock in fixed ticks; run movement every tick and combat on policy cadence.
func _step_fixed_simulation(frame_delta: float) -> void:
	if frame_delta <= 0.0:
		return
	_sim_accum_sec += frame_delta
	var tick_sec := SimulationClock.tick_sec()
	var steps := 0
	while _sim_accum_sec >= tick_sec and steps < SimulationClock.max_catchup_ticks:
		_sim_accum_sec -= tick_sec
		_step_simulation_tick()
		steps += 1
	## Drop excess accumulator after catch-up cap so a long hitch does not spiral.
	if steps >= SimulationClock.max_catchup_ticks and _sim_accum_sec >= tick_sec:
		_sim_accum_sec = fmod(_sim_accum_sec, tick_sec)


func _step_simulation_tick() -> void:
	var stepped := SimulationClock.advance_tick()
	if _map_edit_mode:
		return

	var move_result: ActionResultClass = ActionResolverClass.process_movement_tick(_game_state)
	if (
		not move_result.movement_steps.is_empty()
		or not move_result.movement_completions.is_empty()
	):
		_present_movement_tick_result(move_result)

	_combat_scan_accum_msec += stepped
	var scan_msec := _combat_scan_interval_msec()
	if _combat_scan_accum_msec < scan_msec:
		return
	_combat_scan_accum_msec -= scan_msec
	var tick_result: ActionResultClass = ActionResolverClass.process_combat_tick(_game_state)
	_present_action_result(tick_result, true)


func _present_movement_tick_result(result: ActionResultClass) -> void:
	if result == null:
		return
	for step in result.movement_steps:
		var step_view: Soldier = _get_view(int(step.team_id), int(step.soldier_id))
		var step_state: SoldierState = _game_state.get_soldier(int(step.team_id), int(step.soldier_id))
		if step_view != null and step_state != null:
			step_view.sync_movement_chase_from_state(step_state)
	for done in result.movement_completions:
		var team_id := int(done.team_id)
		var soldier_id := int(done.soldier_id)
		var state: SoldierState = _game_state.get_soldier(team_id, soldier_id)
		var view: Soldier = _get_view(team_id, soldier_id)
		if view != null and state != null:
			view.sync_movement_chase_from_state(state)
		_log_move_complete(soldier_id, state, view)
		if team_id == _session.active_team_id and not _any_active_team_soldier_moving():
			_iso_map.clear_path()
		_ensure_active_selection_alive()
		_refresh_command_bar()
		_command_bar.show_status(
			"%s Soldier %d move complete." % [Team.display_name(team_id), soldier_id]
		)
	if result.refresh_views:
		_refresh_all_views()


func _combat_scan_interval_msec() -> int:
	return maxi(int(round(GameplayPolicies.hit.auto_fire_scan_interval * 1000.0)), 1)


func _input(event: InputEvent) -> void:
	if not _map_edit_mode:
		return
	if event is InputEventMouseMotion:
		_update_map_edit_hover()


func _get_manual_fire_at_shooters() -> Array[SoldierState]:
	var shooters: Array[SoldierState] = []
	var fireteam: Fireteam = _session.get_active_fireteam()
	if _squad_fire_at_mode:
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.is_alive():
				shooters.append(soldier_state)
	else:
		var shooter: SoldierState = fireteam.get_soldier(_fire_at_soldier_id)
		if shooter != null and shooter.is_alive():
			shooters.append(shooter)
	return shooters


func _clear_manual_fire_at_targets() -> void:
	CommandRouter.cancel_sustained_fire(_game_state)


func _active_fireteam_has_engaged_soldier() -> bool:
	var fireteam: Fireteam = _session.get_active_fireteam()
	for state in fireteam.soldiers:
		var soldier_state: SoldierState = state
		if not _is_soldier_in_fire_at_scope(soldier_state):
			continue
		if soldier_state.is_sustained_fire():
			return true
	return false


func _sync_fire_at_ui_from_engagements() -> void:
	var has_engaged := _active_fireteam_has_engaged_soldier()
	_fire_at_engaged = has_engaged
	_command_bar.set_fire_at_engaged(has_engaged)
	if has_engaged and _fire_at_mode:
		_affirm_fire_at_ui()
	elif not has_engaged and _fire_at_mode:
		_command_bar.set_fire_at_engaged(false)


func _affirm_fire_at_ui() -> void:
	if not _fire_at_mode:
		return
	if _squad_fire_at_mode:
		_command_bar.affirm_fire_at_pressed(true, CommandBar.SQUAD_ID)
	else:
		_command_bar.affirm_fire_at_pressed(false, _fire_at_soldier_id)


func _exit_fire_at_mode(message: String = "") -> void:
	_clear_manual_fire_at_targets()
	_fire_at_mode = false
	_squad_fire_at_mode = false
	_fire_at_engaged = false
	_los_visualizer.hide_preview()
	_command_bar.set_fire_at_engaged(false)
	_command_bar.clear_fire_at_mode()
	if not message.is_empty():
		_command_bar.show_status(message)


func _update_los_preview() -> void:
	## Presentation-only: reads GameState + CombatSystem queries; does not mutate gameplay data.
	if _grenade_mode:
		_update_grenade_preview()
		return
	if not _fire_at_mode:
		_los_visualizer.hide_preview()
		return

	var cone_shooter: SoldierState = _get_fire_at_preview_shooter()
	if cone_shooter == null or cone_shooter.is_dead:
		_los_visualizer.hide_preview()
		return

	var hover_soldier: SoldierState = _find_living_soldier_at_mouse()
	var aim_world := _get_world_mouse_local()
	var click_cell := IsometricGrid.world_to_grid(aim_world)
	var explicit_team_id := -1
	var explicit_soldier_id := -1
	if hover_soldier != null and hover_soldier.team_id != cone_shooter.team_id:
		explicit_team_id = hover_soldier.team_id
		explicit_soldier_id = hover_soldier.soldier_id
		click_cell = hover_soldier.grid_position
		aim_world = _get_soldier_tracer_point(hover_soldier)

	if _squad_fire_at_mode:
		_update_squad_los_preview(
			cone_shooter,
			aim_world,
			click_cell,
			explicit_team_id,
			explicit_soldier_id,
		)
		return

	var shooter: SoldierState = cone_shooter
	var weapon := shooter.get_weapon_data()
	var max_range := ConeOfFireClass.effective_range(weapon.range_tiles) if weapon != null else ConeOfFireClass.RANGE_BONUS
	var from_world := _get_soldier_tracer_point(shooter)
	var preview := CombatSystem.evaluate_fire_at_preview(
		_game_state,
		shooter,
		from_world,
		aim_world,
		click_cell,
		explicit_team_id,
		explicit_soldier_id,
	)
	var cone_world := ConeOfFireClass.cone_outline_world_toward(
		from_world,
		aim_world,
		shooter.grid_position,
		max_range,
	)
	if not _fire_at_engaged:
		var shooter_ids: Array[int] = []
		for shooter_state in _get_manual_fire_at_shooters():
			shooter_ids.append(shooter_state.soldier_id)
		var face_cell := preview.click_cell
		if preview.target != null:
			face_cell = preview.target.grid_position
		if ActionResolverClass.preview_fire_at_facing(
			_game_state,
			_session.active_team_id,
			shooter_ids,
			face_cell,
		):
			_sync_fire_at_shooter_views()
	_los_visualizer.show_fire_at_preview(from_world, cone_world, preview)


func _update_grenade_preview() -> void:
	var shooter: SoldierState = _grenade_preview_shooter()
	if shooter == null:
		_los_visualizer.hide_preview()
		return

	var target_cell := IsometricGrid.world_to_cell_at_point(_get_world_mouse_local())
	var from_world := _get_soldier_tracer_point(shooter)
	var target_world := IsometricGrid.soldier_aim_point(target_cell)
	var in_bounds := _map_data.is_in_bounds(target_cell)
	var in_range := (
		in_bounds
		and CombatSystem.grenade_throw_distance(shooter.grid_position, target_cell)
		<= CombatSystem.GRENADE_THROW_RANGE
	)
	_los_visualizer.show_grenade_throw_preview(from_world, target_world, in_range)

	if _grenade_soldier_id == CommandBar.SQUAD_ID:
		var fireteam: Fireteam = _session.get_active_fireteam()
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if (
				soldier_state == null
				or soldier_state.is_dead
				or soldier_state.grenade_count <= 0
				or soldier_state.is_stunned()
				or soldier_state.has_pending_grenade()
			):
				continue
			if ActionResolverClass.preview_grenade_facing(
				_game_state,
				soldier_state.team_id,
				soldier_state.soldier_id,
				target_cell,
			):
				_sync_soldier_view(
					soldier_state.team_id,
					soldier_state.soldier_id,
					soldier_state.soldier_id == fireteam.selected_soldier_id,
				)
	else:
		if ActionResolverClass.preview_grenade_facing(
			_game_state,
			shooter.team_id,
			shooter.soldier_id,
			target_cell,
		):
			_sync_soldier_view(shooter.team_id, shooter.soldier_id, true)


func _update_squad_los_preview(
	cone_shooter: SoldierState,
	aim_world: Vector2,
	click_cell: Vector2i,
	explicit_team_id: int,
	explicit_soldier_id: int,
) -> void:
	var weapon := cone_shooter.get_weapon_data()
	var max_range := (
		ConeOfFireClass.effective_range(weapon.range_tiles)
		if weapon != null
		else ConeOfFireClass.RANGE_BONUS
	)
	var cone_from_world := _get_soldier_tracer_point(cone_shooter)
	var cone_world := ConeOfFireClass.cone_outline_world_toward(
		cone_from_world,
		aim_world,
		cone_shooter.grid_position,
		max_range,
	)

	var entries: Array = []
	var cone_has_target := false
	var face_cell := click_cell

	for shooter_state in _get_manual_fire_at_shooters():
		var from_world := _get_soldier_tracer_point(shooter_state)
		var preview: FireAtPreviewResult
		if _fire_at_engaged and shooter_state.is_sustained_fire():
			preview = CombatSystem.evaluate_engaged_target_preview(_game_state, shooter_state)
		else:
			preview = CombatSystem.evaluate_fire_at_preview(
				_game_state,
				shooter_state,
				from_world,
				aim_world,
				click_cell,
				explicit_team_id,
				explicit_soldier_id,
			)
		if preview.target != null:
			if preview.targetable:
				cone_has_target = true
			if face_cell == click_cell:
				face_cell = preview.target.grid_position
		entries.append({"from_world": from_world, "preview": preview})

	if not _fire_at_engaged:
		var shooter_ids: Array[int] = []
		for shooter_state in _get_manual_fire_at_shooters():
			shooter_ids.append(shooter_state.soldier_id)
		if ActionResolverClass.preview_fire_at_facing(
			_game_state,
			_session.active_team_id,
			shooter_ids,
			face_cell,
		):
			_sync_fire_at_shooter_views()

	_los_visualizer.show_squad_fire_at_previews(entries, cone_world, cone_has_target)


func _sync_fire_at_shooter_views() -> void:
	var active_fireteam: Fireteam = _session.get_active_fireteam()
	for shooter_state in _get_manual_fire_at_shooters():
		var is_selected: bool = shooter_state.soldier_id == active_fireteam.selected_soldier_id
		_sync_soldier_view(shooter_state.team_id, shooter_state.soldier_id, is_selected)


func _get_fire_at_preview_shooter() -> SoldierState:
	var fireteam: Fireteam = _session.get_active_fireteam()
	if _squad_fire_at_mode:
		var selected: SoldierState = fireteam.get_selected()
		if selected != null and selected.is_alive():
			return selected
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.is_alive():
				return soldier_state
		return null
	return fireteam.get_soldier(_fire_at_soldier_id)


func _load_map_data() -> void:
	CocTileCatalog.reload()
	var pending := EditorPlaySession.consume_pending_map_path()
	_return_to_editor_on_exit = EditorPlaySession.should_return_to_editor()
	if not pending.is_empty():
		_map_data = MapLoader.load_path(pending)
	else:
		_map_data = MapLoader.load_path(MapDataClass.resolve_startup_map_path())
	IsometricGrid.set_original_projection_enabled(
		_map_data != null and _map_data.uses_original_projection
	)


func _init_session_from_spawns() -> void:
	var blue_spawns: Array[Vector2i] = _map_data.team_1_spawn_points
	var red_spawns: Array[Vector2i] = _map_data.team_2_spawn_points
	if blue_spawns.is_empty():
		blue_spawns = MapDataClass.default_usa_spawn_points()
	if red_spawns.is_empty():
		red_spawns = MapDataClass.default_germany_spawn_points()
	_session = GameSessionClass.new(blue_spawns, red_spawns)
	_game_state = _session.create_game_state(_map_data)
	ActionResolverClass.apply_match_start_setup(_game_state)


func _connect_command_bar() -> void:
	_command_bar.soldier_selected.connect(_on_soldier_selected)
	_command_bar.move_targeting_changed.connect(_on_move_targeting_changed)
	_command_bar.fire_at_mode_changed.connect(_on_fire_at_mode_changed)
	_command_bar.face_mode_changed.connect(_on_face_mode_changed)
	_command_bar.grenade_mode_changed.connect(_on_grenade_mode_changed)
	_command_bar.position_change_requested.connect(_on_position_change_requested)
	_command_bar.fire_control_change_requested.connect(_on_fire_control_change_requested)
	_command_bar.save_requested.connect(_on_save_requested)
	_command_bar.load_requested.connect(_on_load_requested)
	_command_bar.map_save_requested.connect(_on_map_save_requested)
	_command_bar.map_load_requested.connect(_on_map_load_requested)
	_command_bar.center_camera_requested.connect(_on_center_camera_requested)
	_command_bar.rotate_view_left_requested.connect(_on_rotate_view_left_requested)
	_command_bar.rotate_view_right_requested.connect(_on_rotate_view_right_requested)
	_command_bar.map_edit_mode_changed.connect(_on_map_edit_mode_changed)
	_command_bar.map_edit_palette_changed.connect(_on_map_edit_palette_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M or event.is_action_pressed("map_edit"):
			_toggle_map_edit_mode()
			get_viewport().set_input_as_handled()
			return
		if _map_edit_mode:
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_1:
			_switch_active_team(Team.USA)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_2:
			_switch_active_team(Team.GERMANY)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_B:
			_toggle_grass_layer()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F3:
			_world.toggle_debug_overlay()
			_command_bar.show_status(
				"CoC tile debug %s" % ("ON" if _coc_debug_overlay.enabled else "OFF")
			)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F4:
			_world.toggle_handedness_overlay()
			_command_bar.show_status("Handedness overlay toggled (F5 cycles candidates)")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F5:
			var cand := _world.cycle_handedness_candidate()
			_command_bar.show_status("Handedness candidate: %s" % cand)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and _return_to_editor_on_exit:
			EditorPlaySession.clear_return_flag()
			get_tree().change_scene_to_file("res://scenes/editor/map_editor.tscn")
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("rotate_view_left"):
			_apply_view_rotation_left()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("rotate_view_right"):
			_apply_view_rotation_right()
			get_viewport().set_input_as_handled()
			return

	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	var target_cell := IsometricGrid.world_to_cell_at_point(_get_world_mouse_local())

	if _map_edit_mode:
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_apply_map_edit_cell(target_cell, false)
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_apply_map_edit_cell(target_cell, true)
		get_viewport().set_input_as_handled()
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if _fire_at_mode:
			_exit_fire_at_mode("Targeting cancelled.")
			get_viewport().set_input_as_handled()
			return
		if _face_mode:
			_face_mode = false
			_command_bar.clear_face_mode()
			_command_bar.show_status("Facing cancelled.")
			get_viewport().set_input_as_handled()
			return
		if _grenade_mode:
			_grenade_mode = false
			_command_bar.clear_grenade_mode()
			_los_visualizer.hide_preview()
			_command_bar.show_status("Grenade targeting cancelled.")
			get_viewport().set_input_as_handled()
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if _fire_at_mode:
		var clicked_soldier: SoldierState = _find_living_soldier_at_mouse()
		if clicked_soldier != null and clicked_soldier.team_id == _session.active_team_id:
			_command_bar.show_status("Cannot shoot friendlies.")
			get_viewport().set_input_as_handled()
			return

		var aim_world: Vector2
		if clicked_soldier != null:
			aim_world = _get_soldier_tracer_point(clicked_soldier)
		else:
			aim_world = IsometricGrid.soldier_aim_point(target_cell)
		_apply_fire_at_aim(aim_world, clicked_soldier)
		get_viewport().set_input_as_handled()
		return

	if _face_mode:
		var face_target_cell := target_cell
		var face_target_soldier: SoldierState = _find_living_soldier_at_mouse()
		if face_target_soldier != null:
			face_target_cell = face_target_soldier.grid_position
		var face_cmd := FaceCommand.new()
		face_cmd.team_id = _session.active_team_id
		face_cmd.target_cell = face_target_cell
		if _face_soldier_id == CommandBar.SQUAD_ID:
			face_cmd.scope = FaceCommand.Scope.SQUAD
		else:
			face_cmd.scope = FaceCommand.Scope.SINGLE
			face_cmd.soldier_id = _face_soldier_id
		_apply_face_command(face_cmd)
		get_viewport().set_input_as_handled()
		return

	if _grenade_mode:
		_apply_grenade_command(target_cell)
		get_viewport().set_input_as_handled()
		return

	if not _move_targeting:
		return

	var move_cmd := MoveCommand.new()
	move_cmd.team_id = _session.active_team_id
	move_cmd.target_cell = target_cell
	move_cmd.movement_mode = _active_movement_mode
	if _squad_move_targeting:
		move_cmd.scope = MoveCommand.Scope.SQUAD
	else:
		move_cmd.scope = MoveCommand.Scope.SINGLE
		move_cmd.soldier_id = _move_soldier_id
	_apply_move_command(move_cmd)
	get_viewport().set_input_as_handled()


func _switch_active_team(team_id: int) -> void:
	if not PlayerSides.can_control_team(team_id):
		_command_bar.show_status(
			"You control %s only." % PlayerSides.display_side_name()
		)
		return
	if team_id == _session.active_team_id:
		return
	_session.set_active_team(team_id)
	_move_targeting = false
	_squad_move_targeting = false
	_fire_at_mode = false
	_squad_fire_at_mode = false
	_fire_at_engaged = false
	_face_mode = false
	_grenade_mode = false
	_map_edit_mode = false
	_command_bar.clear_map_edit_mode()
	_command_bar.set_active_team(team_id)
	var fireteam: Fireteam = _session.get_active_fireteam()
	_repair_fireteam_selection(fireteam)
	_command_bar.sync_selected_soldier(fireteam.selected_soldier_id)
	_refresh_all_views()
	var status := "Controlling %s team." % Team.display_name(team_id)
	if GameModeManager.is_offline_dev():
		status += " Press 1/2 to switch."
	_command_bar.show_status(status)


func _toggle_map_edit_mode() -> void:
	_command_bar.set_map_edit_active(not _map_edit_mode)


func _on_map_edit_mode_changed(is_active: bool) -> void:
	_map_edit_mode = is_active
	if is_active:
		_move_targeting = false
		_squad_move_targeting = false
		_fire_at_mode = false
		_squad_fire_at_mode = false
		_fire_at_engaged = false
		_face_mode = false
		_grenade_mode = false
		_los_visualizer.hide_preview()
		_update_map_edit_hover()
	else:
		_iso_map.clear_map_edit_hover()
		_command_bar.show_status("Map Edit OFF.")


func _on_map_edit_palette_changed(palette: int) -> void:
	_map_edit_palette = palette


func _update_map_edit_hover() -> void:
	var cell := IsometricGrid.world_to_cell_at_point(_get_world_mouse_local())
	if not _map_data.is_in_bounds(cell):
		_iso_map.clear_map_edit_hover()
		return
	_iso_map.set_map_edit_hover(cell)


func _apply_map_edit_cell(cell: Vector2i, erase: bool) -> void:
	var result: ActionResultClass = CommandRouter.apply_map_edit(
		_game_state,
		cell,
		_map_edit_palette,
		erase,
	)
	_map_data = _game_state.map_data
	_present_action_result(result)


func _apply_map_presentation() -> void:
	_world.apply_map_data(_map_data)
	_world.set_grass_visible(_grass_layer_visible)


func _toggle_grass_layer() -> void:
	_grass_layer_visible = not _grass_layer_visible
	_world.set_grass_visible(_grass_layer_visible)
	if _grass_layer_visible:
		_command_bar.show_status("Ground Layer Visible")
	else:
		_command_bar.show_status("Ground Layer Hidden")


func _spawn_all_soldier_views() -> void:
	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			var view: Soldier = SoldierScene.instantiate()
			view.soldier_id = soldier_state.soldier_id
			view.team_id = soldier_state.team_id
			view.movement_step_reached.connect(_on_soldier_step_reached)
			view.movement_finished.connect(_on_soldier_movement_finished)
			view.stance_transition_finished.connect(_on_soldier_stance_transition_finished)
			view.stance_transition_cancelled.connect(_on_soldier_stance_transition_cancelled)
			_depth_sorted.add_child(view)
			_soldier_views[Team.soldier_key(soldier_state.team_id, soldier_state.soldier_id)] = view


func _refresh_all_views() -> void:
	_apply_spotting_cell_overrides()
	var active_team: int = _session.active_team_id
	var active_fireteam: Fireteam = _session.get_active_fireteam()
	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			var is_selected: bool = (
				soldier_state.team_id == active_team
				and soldier_state.soldier_id == active_fireteam.selected_soldier_id
			)
			_sync_soldier_view(soldier_state.team_id, soldier_state.soldier_id, is_selected)
	_clear_spotting_cell_overrides()

	_ensure_active_selection_alive()
	_refresh_command_bar()


func _refresh_selection_marks() -> void:
	var active_team: int = _session.active_team_id
	var active_fireteam: Fireteam = _session.get_active_fireteam()
	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			var view: Soldier = _get_view(soldier_state.team_id, soldier_state.soldier_id)
			if view == null:
				continue
			var is_selected: bool = (
				soldier_state.team_id == active_team
				and soldier_state.soldier_id == active_fireteam.selected_soldier_id
			)
			view.set_selected(is_selected)


func _sync_soldier_view(team_id: int, soldier_id: int, is_selected: bool = false) -> void:
	var soldier_state: SoldierState = _get_fireteam(team_id).get_soldier(soldier_id)
	if soldier_state == null:
		return
	var view: Soldier = _get_view(team_id, soldier_id)
	if view == null:
		return
	var is_spotted := true
	if soldier_state.team_id != _session.active_team_id and soldier_state.is_alive():
		is_spotted = CombatSystem.is_enemy_visible_to_team(
			_game_state,
			_session.active_team_id,
			soldier_state,
		)
	view.sync_from_state(soldier_state, is_selected, is_spotted)


func _refresh_armed_movement_views(soldier_id: int) -> void:
	var fireteam: Fireteam = _session.get_active_fireteam()
	var active_team: int = _session.active_team_id
	if soldier_id == CommandBar.SQUAD_ID:
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if not soldier_state.is_alive():
				continue
			var is_selected := soldier_state.soldier_id == fireteam.selected_soldier_id
			_sync_soldier_view(active_team, soldier_state.soldier_id, is_selected)
		_refresh_command_bar()
	elif soldier_id > 0:
		var is_selected := soldier_id == fireteam.selected_soldier_id
		_sync_soldier_view(active_team, soldier_id, is_selected)
		_refresh_command_bar()


func _refresh_command_bar() -> void:
	var fireteam: Fireteam = _session.get_active_fireteam()
	for i in range(fireteam.soldiers.size()):
		var soldier_state: SoldierState = fireteam.soldiers[i]
		var hit_pct := _hit_pct_for_command_row(soldier_state)
		_command_bar.sync_soldier_row(i, soldier_state, hit_pct)


func _update_command_bar_hit_columns() -> void:
	if not _should_update_hit_columns():
		return
	var fireteam: Fireteam = _session.get_active_fireteam()
	var hit_pcts: Array = []
	for state in fireteam.soldiers:
		var soldier_state: SoldierState = state
		hit_pcts.append(_hit_pct_for_command_row(soldier_state))
	_command_bar.update_hit_columns(hit_pcts)


func _should_update_hit_columns() -> bool:
	if _fire_at_mode:
		return true
	for state in _session.get_active_fireteam().soldiers:
		var soldier_state: SoldierState = state
		if soldier_state.is_alive() and soldier_state.fire_control_state == FireControlStateClass.FIRE_AT_WILL:
			return true
	return false


func _hit_pct_for_command_row(soldier_state: SoldierState) -> float:
	## Presentation-only read of CombatSystem; does not mutate state.
	if not _should_show_hit_pct(soldier_state):
		return -1.0
	return CombatSystem.hit_pct_vs_faced_enemy(_game_state, soldier_state)


func _should_show_hit_pct(soldier_state: SoldierState) -> bool:
	if soldier_state.is_dead:
		return false
	if soldier_state.fire_control_state == FireControlStateClass.FIRE_AT_WILL:
		return true
	return _is_soldier_in_fire_at_scope(soldier_state)


func _is_soldier_in_fire_at_scope(soldier_state: SoldierState) -> bool:
	if not _fire_at_mode or soldier_state.team_id != _session.active_team_id:
		return false
	if _squad_fire_at_mode:
		return true
	return soldier_state.soldier_id == _fire_at_soldier_id


func _on_center_camera_requested() -> void:
	_center_camera_on_active_fireteam()


func _on_rotate_view_left_requested() -> void:
	_apply_view_rotation_left()


func _on_rotate_view_right_requested() -> void:
	_apply_view_rotation_right()


func _apply_view_rotation_left() -> void:
	_rotate_view_preserving_viewport(true)


func _apply_view_rotation_right() -> void:
	_rotate_view_preserving_viewport(false)


## Rotate projection while keeping the battlefield point under the viewport center.
func _rotate_view_preserving_viewport(rotate_left: bool) -> void:
	var focus_logical := IsometricGrid.world_to_logical_point(_camera.get_viewport_center_world())
	if rotate_left:
		IsometricGrid.rotate_view_left()
	else:
		IsometricGrid.rotate_view_right()
	_refresh_view_rotation()
	_camera.center_on_world(IsometricGrid.logical_point_to_world(focus_logical))


func _refresh_view_rotation() -> void:
	if _map_data == null:
		return
	_camera.set_map_size(_map_data.width, _map_data.height)
	_world.set_center_cell(_get_camera_focus_cell())
	_world.refresh_view_rotation()
	for view in _soldier_views.values():
		var soldier_view: Soldier = view
		soldier_view.refresh_movement_visual()
		soldier_view.refresh_action_visual_for_camera()
	_refresh_all_views()
	_command_bar.show_status(
		"Camera %d° — Q/E or Rotate. Simulation grid unchanged."
		% IsometricGrid.camera_direction_degrees(),
	)


func _center_camera_on_active_fireteam() -> void:
	var fireteam: Fireteam = _session.get_active_fireteam()
	var sum := Vector2i.ZERO
	var count := 0
	for state in fireteam.soldiers:
		var soldier_state: SoldierState = state
		if not soldier_state.is_alive():
			continue
		sum += soldier_state.grid_position
		count += 1
	if count == 0:
		_command_bar.show_status("No living soldiers to center on.")
		return
	var center_cell := Vector2i(floori(float(sum.x) / count), floori(float(sum.y) / count))
	_map_background.set_center_cell(center_cell)
	_camera.reset_to_default_view(IsometricGrid.grid_to_world(center_cell))
	_command_bar.show_status("Camera centered on %s fireteam." % Team.display_name(_session.active_team_id))


func _repair_fireteam_selection(fireteam: Fireteam) -> bool:
	var selected: SoldierState = fireteam.get_selected()
	if selected != null and selected.is_alive():
		return false
	var previous_id := fireteam.selected_soldier_id
	fireteam.select_first_alive()
	return fireteam.selected_soldier_id != previous_id


func _ensure_active_selection_alive() -> void:
	var fireteam: Fireteam = _session.get_active_fireteam()
	if _repair_fireteam_selection(fireteam):
		_command_bar.sync_selected_soldier(fireteam.selected_soldier_id)


func _get_view(team_id: int, soldier_id: int) -> Soldier:
	return _soldier_views.get(Team.soldier_key(team_id, soldier_id)) as Soldier


func _get_fireteam(team_id: int) -> Fireteam:
	return _session.get_fireteam(team_id)


func _any_active_team_soldier_moving() -> bool:
	for state in _session.get_active_fireteam().soldiers:
		var soldier_state: SoldierState = state
		if _is_soldier_moving(soldier_state):
			return true
	return false


func _any_soldier_moving() -> bool:
	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if _is_soldier_moving(soldier_state):
				return true
	return false


func _is_soldier_moving(state: SoldierState) -> bool:
	if state == null or state.is_dead:
		return false
	## Authoritative only — presentation lerp must not keep gameplay "moving".
	return state.is_moving


func _build_spotting_cell_overrides() -> Dictionary:
	## Deprecated: spotting uses SoldierState.grid_position only.
	return {}


func _apply_spotting_cell_overrides() -> void:
	CombatSystem.clear_spotting_cell_overrides()


func _clear_spotting_cell_overrides() -> void:
	CombatSystem.clear_spotting_cell_overrides()


func _on_soldier_selected(soldier_id: int) -> void:
	## UI-local selection only (client-side; not an authoritative gameplay command).
	_session.get_active_fireteam().select_soldier(soldier_id)
	_refresh_all_views()


## Apply ActionResult to views, overlays, and status (presentation only).
func _present_action_result(result: ActionResultClass, combat_tick: bool = false) -> void:
	if result == null:
		return
	if not result.success:
		if not result.status_message.is_empty():
			_command_bar.show_status(result.status_message)
		return

	for halt in result.movement_halts:
		var halt_view: Soldier = _get_view(halt.team_id, halt.soldier_id)
		if halt_view != null:
			halt_view.stop_movement()

	for order in result.move_orders:
		var order_view: Soldier = _get_view(order.team_id, order.soldier_id)
		if order_view != null:
			order_view.follow_path(order.path, order.speed_mult)

	if result.refresh_map_data:
		_apply_map_presentation()

	if result.clear_path_overlay:
		_iso_map.clear_path()
	if result.path_overlay.has("target"):
		_iso_map.show_path(
			result.path_overlay.get("cells", []),
			result.path_overlay.target,
		)

	if result.clear_move_targeting:
		_command_bar.clear_move_targeting()
		_move_targeting = false
		_squad_move_targeting = false

	var combat_lines: Array[String] = []
	for shot in result.combat_shots:
		var shooter: SoldierState = _game_state.get_soldier(shot.shooter_team_id, shot.shooter_id)
		var target: SoldierState = _game_state.get_soldier(shot.target_team_id, shot.target_id)
		if shot.fired:
			combat_lines.append_array(_finalize_shot_result(shot, shooter, target))
		else:
			for line in shot.messages:
				GameLog.log_combat(line)
				combat_lines.append(line)

	if not result.grenade_explosions.is_empty():
		_spawn_grenade_explosions(result.grenade_explosions)
		_trigger_grenade_death_animations(result.grenade_explosions)

	if result.refresh_views:
		_ensure_active_selection_alive()
		_refresh_all_views()
		_refresh_command_bar()

	for order in result.throw_orders:
		var throw_view: Soldier = _get_view(int(order.team_id), int(order.soldier_id))
		var thrower: SoldierState = _game_state.get_soldier(int(order.team_id), int(order.soldier_id))
		if throw_view != null and thrower != null:
			throw_view.play_throw_grenade(thrower.position_state, thrower.facing_direction)

	for order in result.stance_transition_orders:
		var stance_view: Soldier = _get_view(int(order.team_id), int(order.soldier_id))
		var stance_soldier: SoldierState = _game_state.get_soldier(int(order.team_id), int(order.soldier_id))
		if stance_view != null and stance_soldier != null:
			stance_view.play_stance_transition(
				int(order.target_position_state),
				stance_soldier.facing_direction,
			)

	if result.sync_fire_at_ui:
		_sync_fire_at_ui_from_engagements()

	if result.begin_fire_engagement:
		_begin_fire_at_engagement()

	if combat_tick and not combat_lines.is_empty():
		_command_bar.show_status("\n".join(combat_lines.slice(-3)))
	elif not result.grenade_explosions.is_empty():
		_present_grenade_explosion_messages(result.grenade_explosions)
	elif not result.status_message.is_empty():
		_command_bar.show_status(result.status_message)


func _present_grenade_explosion_messages(explosions: Array) -> void:
	var lines: Array[String] = []
	for explosion in explosions:
		for line in explosion.messages:
			GameLog.log_combat(line)
			lines.append(line)
	if not lines.is_empty():
		_command_bar.show_status("\n".join(lines.slice(-3)))


func _spawn_grenade_explosions(explosions: Array) -> void:
	for explosion in explosions:
		var cell: Vector2i = explosion.explosion_cell
		var world_pos := IsometricGrid.grid_to_world(cell)
		GrenadeExplosion.spawn(_tracers_root, world_pos)
		AudioManager.play_grenade_explosion()


func _trigger_grenade_death_animations(explosions: Array) -> void:
	for explosion in explosions:
		var blast_cell: Vector2i = explosion.explosion_cell
		for entry in explosion.killed:
			var team_id := int(entry.get("team_id", -1))
			var soldier_id := int(entry.get("soldier_id", -1))
			var victim: SoldierState = _game_state.get_soldier(team_id, soldier_id)
			if victim == null:
				continue
			# Vector from victim toward blast; fall plays away from the explosion.
			var threat_step := blast_cell - victim.grid_position
			AudioManager.play_death(team_id)
			var view: Soldier = _get_view(team_id, soldier_id)
			if view != null:
				view.play_death_sequence(threat_step, victim.stance_at_death)


func _snap_cell_for_soldier(state: SoldierState) -> Vector2i:
	## Authoritative grid only — presentation interpolation is never queried for gameplay.
	return state.grid_position


func _make_move_context(cmd: MoveCommand) -> CommandContextClass:
	var ctx := CommandContextClass.new()
	ctx.find_path = _iso_map.find_path
	return ctx


func _add_snap_cell_if_animating(_ctx: CommandContextClass, _state: SoldierState) -> void:
	## No-op: mid-move gameplay uses SoldierState.grid_position.
	pass


func _make_fire_context(shooters: Array[SoldierState]) -> CommandContextClass:
	var ctx := CommandContextClass.new()
	for shooter in shooters:
		ctx.shooter_ids.append(shooter.soldier_id)
	return ctx


func _make_grenade_context(soldier_state: SoldierState) -> CommandContextClass:
	var ctx := CommandContextClass.new()
	ctx.shooter_ids.append(soldier_state.soldier_id)
	return ctx


func _apply_grenade_command(target_cell: Vector2i) -> void:
	if _grenade_soldier_id == CommandBar.SQUAD_ID:
		_apply_squad_grenade_command(target_cell)
		return

	var soldier_state: SoldierState = _game_state.get_soldier(
		_session.active_team_id,
		_grenade_soldier_id,
	)
	if soldier_state == null or soldier_state.is_dead:
		_command_bar.show_status("Soldier unavailable.")
		return

	var cmd := GrenadeCommand.new()
	cmd.team_id = _session.active_team_id
	cmd.soldier_id = _grenade_soldier_id
	cmd.target_cell = target_cell

	var result: ActionResultClass = CommandRouter.submit_command(
		_game_state,
		cmd,
		_make_grenade_context(soldier_state),
	)
	if result.success:
		_grenade_mode = false
		_command_bar.clear_grenade_mode()
		_los_visualizer.hide_preview()
	_present_action_result(result)


func _apply_squad_grenade_command(target_cell: Vector2i) -> void:
	var thrown := 0
	var last_result: ActionResultClass = null
	var fireteam: Fireteam = _session.get_active_fireteam()
	for state in fireteam.soldiers:
		var soldier_state: SoldierState = state
		if (
			soldier_state == null
			or soldier_state.is_dead
			or soldier_state.grenade_count <= 0
			or soldier_state.is_stunned()
			or soldier_state.has_pending_grenade()
			or soldier_state.is_moving
		):
			continue
		var cmd := GrenadeCommand.new()
		cmd.team_id = _session.active_team_id
		cmd.soldier_id = soldier_state.soldier_id
		cmd.target_cell = target_cell
		var result: ActionResultClass = CommandRouter.submit_command(
			_game_state,
			cmd,
			_make_grenade_context(soldier_state),
		)
		last_result = result
		if result.success:
			thrown += 1
			## Play each thrower anim even when only the last ActionResult is presented.
			for order in result.throw_orders:
				var throw_view: Soldier = _get_view(int(order.team_id), int(order.soldier_id))
				if throw_view != null:
					throw_view.play_throw_grenade(
						soldier_state.position_state,
						soldier_state.facing_direction,
					)
	if thrown > 0:
		_grenade_mode = false
		_command_bar.clear_grenade_mode()
		_los_visualizer.hide_preview()
		if last_result != null:
			## Avoid replaying throw anims already started above.
			last_result.throw_orders.clear()
			_present_action_result(last_result)
		_command_bar.show_status("Fireteam grenade — %d thrown." % thrown)
	elif last_result != null:
		_present_action_result(last_result)
	else:
		_command_bar.show_status("No soldiers available to throw grenades.")


func _grenade_preview_shooter() -> SoldierState:
	if _grenade_soldier_id == CommandBar.SQUAD_ID:
		var fireteam: Fireteam = _session.get_active_fireteam()
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if (
				soldier_state != null
				and soldier_state.is_alive()
				and soldier_state.grenade_count > 0
				and not soldier_state.is_stunned()
				and not soldier_state.has_pending_grenade()
			):
				return soldier_state
		return null
	var shooter: SoldierState = _game_state.get_soldier(
		_session.active_team_id,
		_grenade_soldier_id,
	)
	if shooter == null or shooter.is_dead:
		return null
	return shooter


func _apply_move_command(cmd: MoveCommand) -> void:
	var result: ActionResultClass = CommandRouter.submit_command(
		_game_state,
		cmd,
		_make_move_context(cmd),
	)
	if (
		result.success
		and cmd.scope == MoveCommand.Scope.SINGLE
		and not result.move_orders.is_empty()
	):
		var order: Dictionary = result.move_orders[0]
		var soldier_state: SoldierState = _game_state.get_soldier(order.team_id, order.soldier_id)
		_log_move_order(cmd.target_cell, order.path, soldier_state)
	_present_action_result(result)


func _apply_face_command(cmd: FaceCommand) -> void:
	var result: ActionResultClass = CommandRouter.submit_command(_game_state, cmd)
	_present_action_result(result)


func _apply_position_command(cmd: PositionCommand) -> void:
	var result: ActionResultClass = CommandRouter.submit_command(_game_state, cmd)
	if (
		result.success
		and cmd.position_state == PositionStateClass.DOWN
		and _move_targeting
		and not MovementModeClass.is_allowed(PositionStateClass.DOWN, _active_movement_mode)
	):
		if _squad_move_targeting or _move_soldier_id == cmd.soldier_id:
			_command_bar.clear_move_targeting()
			_move_targeting = false
			_squad_move_targeting = false
	_present_action_result(result)


func _on_fire_control_change_requested(soldier_id: int, fire_control_state: int) -> void:
	if soldier_id == CommandBar.SQUAD_ID:
		var last_result: ActionResultClass = null
		var fireteam: Fireteam = _session.get_active_fireteam()
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state == null or soldier_state.is_dead:
				continue
			var cmd := FireControlCommandClass.new()
			cmd.team_id = _session.active_team_id
			cmd.soldier_id = soldier_state.soldier_id
			cmd.fire_control_state = fire_control_state
			last_result = CommandRouter.submit_command(_game_state, cmd)
		if last_result != null:
			_present_action_result(last_result)
		else:
			_command_bar.show_status("No soldiers available.")
		return

	var cmd := FireControlCommandClass.new()
	cmd.team_id = _session.active_team_id
	cmd.soldier_id = soldier_id
	cmd.fire_control_state = fire_control_state
	var result: ActionResultClass = CommandRouter.submit_command(_game_state, cmd)
	_present_action_result(result)


func _on_position_change_requested(soldier_id: int, position_state: int) -> void:
	if soldier_id == CommandBar.SQUAD_ID:
		var last_result: ActionResultClass = null
		var combined_transitions: Array[Dictionary] = []
		var fireteam: Fireteam = _session.get_active_fireteam()
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state == null or soldier_state.is_dead or soldier_state.is_stunned():
				continue
			var cmd := PositionCommand.new()
			cmd.team_id = _session.active_team_id
			cmd.soldier_id = soldier_state.soldier_id
			cmd.position_state = position_state
			last_result = CommandRouter.submit_command(_game_state, cmd)
			if last_result != null and last_result.success:
				for order in last_result.stance_transition_orders:
					combined_transitions.append(order)
		if (
			last_result != null
			and last_result.success
			and position_state == PositionStateClass.DOWN
			and _move_targeting
			and not MovementModeClass.is_allowed(PositionStateClass.DOWN, _active_movement_mode)
		):
			_command_bar.clear_move_targeting()
			_move_targeting = false
			_squad_move_targeting = false
		## Don't force Up/Down UI to the target yet — gameplay stance commits after anims.
		if last_result != null:
			## Replay all deferred transitions (each submit only carries one soldier).
			last_result.stance_transition_orders = combined_transitions
			_present_action_result(last_result)
		else:
			_command_bar.show_status("No soldiers available.")
		return

	var cmd := PositionCommand.new()
	cmd.team_id = _session.active_team_id
	cmd.soldier_id = soldier_id
	cmd.position_state = position_state
	_apply_position_command(cmd)


func _arm_movement_mode(soldier_id: int, movement_mode: int) -> String:
	var result: ActionResultClass = CommandRouter.arm_movement_mode(
		_game_state,
		_session.active_team_id,
		soldier_id,
		movement_mode,
	)
	return result.status_message if result.success else ""


func _apply_fire_at_aim(aim_world: Vector2, clicked_soldier: SoldierState = null) -> void:
	var shooters: Array[SoldierState] = _get_manual_fire_at_shooters()
	if shooters.is_empty():
		_command_bar.show_status("No available soldiers to fire.")
		return

	var cmd := FireCommand.new()
	cmd.team_id = _session.active_team_id
	cmd.aim_world = aim_world
	if clicked_soldier != null and clicked_soldier.team_id != _session.active_team_id:
		cmd.target_team_id = clicked_soldier.team_id
		cmd.target_soldier_id = clicked_soldier.soldier_id
	if _squad_fire_at_mode:
		cmd.scope = FireCommand.Scope.SQUAD
	else:
		cmd.scope = FireCommand.Scope.SINGLE
		cmd.soldier_id = _fire_at_soldier_id

	var result: ActionResultClass = CommandRouter.submit_command(
		_game_state,
		cmd,
		_make_fire_context(shooters),
	)
	_present_action_result(result)


func _finalize_shot_result(
	result: CombatShotResult,
	shooter: SoldierState,
	target: SoldierState,
) -> Array[String]:
	if result.fired:
		GameplayPolicies.fire_anim.note_authoritative_shot()
		if shooter != null:
			var shooter_view: Soldier = _get_view(shooter.team_id, shooter.soldier_id)
			if shooter_view != null:
				shooter_view.play_fire(shooter.position_state, shooter.facing_direction)
		if target != null:
			_spawn_shot_tracers(shooter, target, maxi(result.tracer_count, 1))
			result.messages.append("Tracer created")

	if result.killed and target != null:
		var threat_step := shooter.grid_position - target.grid_position
		var target_view: Soldier = _get_view(target.team_id, target.soldier_id)
		if target_view != null:
			## Use stance_at_death — mark_killed already forced position_state DOWN.
			target_view.play_death_sequence(threat_step, target.stance_at_death)
	elif result.hit and target != null and not result.killed:
		var threat_step := shooter.grid_position - target.grid_position
		var target_view: Soldier = _get_view(target.team_id, target.soldier_id)
		if target_view != null:
			target_view.play_hit_reaction(threat_step, target.position_state)

	var lines: Array[String] = []
	for line in result.messages:
		GameLog.log_combat(line)
		lines.append(line)
	return lines


func _spawn_shot_tracers(shooter: SoldierState, target: SoldierState, count: int) -> void:
	var from_world := _get_soldier_tracer_point(shooter)
	var to_world := _get_soldier_tracer_point(target)
	for i in range(count):
		var jitter := Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		ShotTracer.spawn(_tracers_root, from_world + jitter, to_world + jitter)


func _get_soldier_tracer_point(soldier_state: SoldierState) -> Vector2:
	## Presentation-only: prefers animated view position for tracers and LOS preview.
	var view: Soldier = _get_view(soldier_state.team_id, soldier_state.soldier_id)
	if view != null:
		return view.position + TileSizeConfig.tracer_aim_offset()
	return IsometricGrid.soldier_aim_point(soldier_state.grid_position)


func _on_soldier_step_reached(_team_id: int, _soldier_id: int, _tile: Vector2i, _step_delta: Vector2i) -> void:
	## Legacy presentation signal — authoritative steps come from process_movement_tick.
	pass


func _on_soldier_movement_finished(_team_id: int, _soldier_id: int) -> void:
	## Legacy presentation signal — authoritative completion comes from process_movement_tick.
	pass


func _on_soldier_stance_transition_finished(
	team_id: int,
	soldier_id: int,
	target_position_state: int,
) -> void:
	var result: ActionResultClass = ActionResolverClass.commit_stance_transition(
		_game_state,
		team_id,
		soldier_id,
		target_position_state,
	)
	_present_action_result(result)


func _on_soldier_stance_transition_cancelled(team_id: int, soldier_id: int) -> void:
	var soldier: SoldierState = _game_state.get_soldier(team_id, soldier_id)
	if soldier != null:
		soldier.clear_pending_position()


func _log_move_order(clicked_tile: Vector2i, path: Array[Vector2i], state: SoldierState) -> void:
	var path_final := path[path.size() - 1] if not path.is_empty() else Vector2i(-1, -1)
	call_deferred(
		"_emit_move_order_log",
		clicked_tile,
		path_final,
		state.grid_position,
		_soldier_world_pos(state),
	)


func _emit_move_order_log(
	clicked_tile: Vector2i,
	path_final: Vector2i,
	soldier_grid: Vector2i,
	soldier_world: Vector2,
) -> void:
	GameLog.log_system(
		"Move order: clicked=%s path_final=%s soldier_grid=%s soldier_world=%s"
		% [clicked_tile, path_final, soldier_grid, soldier_world],
	)


func _log_move_complete(soldier_id: int, state: SoldierState, view: Soldier) -> void:
	if state == null:
		return
	var world_pos := view.position if view != null else _soldier_world_pos(state)
	call_deferred(
		"_emit_move_complete_log",
		soldier_id,
		state.grid_position,
		world_pos,
	)


func _emit_move_complete_log(soldier_id: int, grid_pos: Vector2i, world_pos: Vector2) -> void:
	GameLog.log_system(
		"Move complete: soldier=%d grid=%s world=%s cell_at_world=%s"
		% [
			soldier_id,
			grid_pos,
			world_pos,
			IsometricGrid.world_to_cell_at_point(world_pos),
		],
	)


func _soldier_world_pos(state: SoldierState) -> Vector2:
	var view: Soldier = _get_view(state.team_id, state.soldier_id)
	if view != null:
		return view.position
	return IsometricGrid.grid_to_world(state.grid_position)


func _on_move_targeting_changed(is_active: bool, soldier_id: int, movement_mode: int) -> void:
	_move_targeting = is_active
	_squad_move_targeting = is_active and soldier_id == CommandBar.SQUAD_ID
	_active_movement_mode = movement_mode
	_move_soldier_id = soldier_id if soldier_id > 0 else _session.get_active_fireteam().selected_soldier_id
	if is_active:
		_map_edit_mode = false
		_command_bar.clear_map_edit_mode()
		_fire_at_mode = false
		_squad_fire_at_mode = false
		_fire_at_engaged = false
		_face_mode = false
		_grenade_mode = false
		if soldier_id > 0:
			_session.get_active_fireteam().select_soldier(soldier_id)
		var arm_message := _arm_movement_mode(soldier_id, movement_mode)
		_refresh_selection_marks()
		_refresh_armed_movement_views(soldier_id)
		if not arm_message.is_empty():
			_command_bar.show_status(arm_message)


func _begin_fire_at_engagement() -> void:
	## Arm an immediate combat scan on the next simulation tick (preserve prior kick behavior).
	_combat_scan_accum_msec = _combat_scan_interval_msec()
	_sync_fire_at_ui_from_engagements()


func _on_fire_at_mode_changed(is_active: bool, soldier_id: int) -> void:
	_fire_at_mode = is_active
	_squad_fire_at_mode = is_active and soldier_id == CommandBar.SQUAD_ID
	_fire_at_soldier_id = soldier_id if is_active else 1
	if is_active:
		_map_edit_mode = false
		_command_bar.clear_map_edit_mode()
		_move_targeting = false
		_squad_move_targeting = false
		_face_mode = false
		_grenade_mode = false
		if soldier_id > 0:
			_session.get_active_fireteam().select_soldier(soldier_id)
			_refresh_all_views()
	else:
		_los_visualizer.hide_preview()
		_sync_fire_at_ui_from_engagements()


func _on_grenade_mode_changed(is_active: bool, soldier_id: int) -> void:
	_grenade_mode = is_active
	_grenade_soldier_id = soldier_id if is_active else 1
	if is_active:
		_map_edit_mode = false
		_command_bar.clear_map_edit_mode()
		_move_targeting = false
		_squad_move_targeting = false
		_fire_at_mode = false
		_squad_fire_at_mode = false
		_face_mode = false
		_los_visualizer.hide_preview()
		if soldier_id > 0:
			_session.get_active_fireteam().select_soldier(soldier_id)
			_refresh_all_views()


func _on_face_mode_changed(is_active: bool, soldier_id: int) -> void:
	_face_mode = is_active
	_face_soldier_id = soldier_id if is_active else 1
	if is_active:
		_map_edit_mode = false
		_command_bar.clear_map_edit_mode()
		_move_targeting = false
		_squad_move_targeting = false
		_fire_at_mode = false
		_squad_fire_at_mode = false
		_grenade_mode = false
		if soldier_id > 0:
			_session.get_active_fireteam().select_soldier(soldier_id)
			_refresh_all_views()


func _on_save_requested() -> void:
	if GameSaveClass.save_game(_session, _map_data):
		_command_bar.show_status("Game saved.")
	else:
		_command_bar.show_status("Save failed.")


func _on_load_requested() -> void:
	var result: ActionResultClass = CommandRouter.load_saved_session(_game_state)
	if not result.success:
		_command_bar.show_status(result.status_message)
		return
	_sync_views_after_load()
	_present_action_result(result)


func _on_map_save_requested() -> void:
	if MapDataClass.save_to_file(_map_data):
		_command_bar.show_status("Map saved to res://maps/test_map.json")
	else:
		_command_bar.show_status("Map save failed.")


func _on_map_load_requested() -> void:
	var result: ActionResultClass = CommandRouter.reload_map_from_file(_game_state)
	_map_data = _game_state.map_data
	_map_edit_mode = false
	_command_bar.clear_map_edit_mode()
	IsometricGrid.reset_view_rotation()
	_apply_map_presentation()
	_camera.set_map_size(_map_data.width, _map_data.height)
	_center_camera_on_map()
	_sync_views_after_load()
	_present_action_result(result)


func _sync_views_after_load() -> void:
	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			var view: Soldier = _get_view(soldier_state.team_id, soldier_state.soldier_id)
			if view == null:
				continue
			view.stop_movement()
			var is_selected: bool = (
				soldier_state.team_id == _session.active_team_id
				and soldier_state.soldier_id == _session.get_active_fireteam().selected_soldier_id
			)
			view.sync_from_state(soldier_state, is_selected)

	_iso_map.clear_path()
	_command_bar.clear_move_targeting()
	_command_bar.clear_fire_at_mode()
	_command_bar.clear_face_mode()
	_command_bar.set_active_team(_session.active_team_id)
	_refresh_all_views()
	_command_bar.sync_selected_soldier(_session.get_active_fireteam().selected_soldier_id)


func _get_world_mouse_local() -> Vector2:
	return _world.to_local(get_global_mouse_position())


## Resolve a soldier under the cursor (grid cell + sprite proximity for isometric picking).
func _find_living_soldier_at_mouse() -> SoldierState:
	var world := _get_world_mouse_local()
	var clicked_cell := IsometricGrid.world_to_cell_at_point(world)

	var exact: SoldierState = _game_state.find_living_soldier_at_cell(clicked_cell)
	if exact != null:
		return exact

	const PICK_RADIUS := TileSizeConfig.SOLDIER_PICK_RADIUS
	const PICK_RADIUS_SQ := PICK_RADIUS * PICK_RADIUS
	var best: SoldierState = null
	var best_dist := PICK_RADIUS_SQ

	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.is_dead:
				continue
			var view: Soldier = _get_view(soldier_state.team_id, soldier_state.soldier_id)
			var pick_center := IsometricGrid.soldier_aim_point(soldier_state.grid_position)
			if view != null:
				pick_center = view.position + TileSizeConfig.tracer_aim_offset()
			var dist_sq := world.distance_squared_to(pick_center)
			if dist_sq < best_dist:
				best_dist = dist_sq
				best = soldier_state

	return best


func _center_camera_on_map() -> void:
	if _map_data == null:
		return
	IsometricGrid.set_view_pivot_for_map(_map_data.width, _map_data.height)
	_camera.set_map_size(_map_data.width, _map_data.height)
	var focus_cell: Vector2i = _get_camera_focus_cell()
	_map_background.set_center_cell(focus_cell)
	_camera.reset_to_default_view(IsometricGrid.grid_to_world(focus_cell))


func _get_camera_focus_cell() -> Vector2i:
	var spawns: Array[Vector2i] = _map_data.team_1_spawn_points
	if spawns.is_empty():
		return Vector2i(floori(_map_data.width / 2.0), floori(_map_data.height / 2.0))
	var sum := Vector2i.ZERO
	for cell in spawns:
		sum += cell
	return Vector2i(floori(float(sum.x) / spawns.size()), floori(float(sum.y) / spawns.size()))
