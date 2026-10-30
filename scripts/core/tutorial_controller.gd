class_name TutorialController
extends RefCounted

signal step_changed(new_step: int)
signal tutorial_completed

enum Step {
	WELCOME,
	SELECT_SOLDIER,
	RUN_TO,
	WAIT_ARRIVAL,
	GO_PRONE,
	FACE_ENEMY,
	FIRE_AT_WILL,
	OBSERVE,
	HOLD_FIRE,
	MANUAL_FIRE,
	STAND_UP,
	CRAWL,
	GRENADE,
	COMPLETE,
}

const STEP_COUNT := 14
const OBSERVE_WAIT_SEC := 5.0
const TUTORIAL_SOLDIER_ID := 1

var current_step: int = Step.WELCOME
var _observe_timer_sec: float = 0.0
var _observe_start_fired: bool = false


func reset() -> void:
	current_step = Step.WELCOME
	_observe_timer_sec = 0.0
	_observe_start_fired = false


func advance() -> void:
	if current_step >= Step.COMPLETE:
		return
	current_step += 1
	_observe_timer_sec = 0.0
	_observe_start_fired = false
	step_changed.emit(current_step)
	if current_step == Step.COMPLETE:
		tutorial_completed.emit()


func step_title() -> String:
	if current_step == Step.WELCOME:
		return "Welcome"
	if current_step == Step.COMPLETE:
		return "Tutorial Complete"
	return "Step %d of %d" % [current_step, STEP_COUNT - 2]


func step_instruction() -> String:
	match current_step:
		Step.WELCOME:
			return "Welcome to basic training!"
		Step.SELECT_SOLDIER:
			return "Click on Soldier 1's row in the command bar below to select them."
		Step.RUN_TO:
			return "Click 'Run To', then click a tile toward the right side of the map (toward the enemy)."
		Step.WAIT_ARRIVAL:
			return "Your soldier is moving! Wait for them to arrive."
		Step.GO_PRONE:
			return "Click 'Down' to go prone. Prone soldiers are harder to hit."
		Step.FACE_ENEMY:
			return "Click 'Face', then click a tile to the right (toward the enemy side)."
		Step.FIRE_AT_WILL:
			return "Click 'Fire At Will' to fire at visible enemies automatically."
		Step.OBSERVE:
			return "Watch your soldier engage! They will fire at enemies in sight."
		Step.HOLD_FIRE:
			return "Click 'Hold Fire' to cease firing."
		Step.MANUAL_FIRE:
			return "Click 'Fire At', then click on an enemy soldier (red) to target them."
		Step.STAND_UP:
			return "Click 'Up' to stand back up. Standing gives better accuracy."
		Step.CRAWL:
			return "Click 'Crawl To', then click a tile. Crawling is slower but keeps you low."
		Step.GRENADE:
			return "Click 'Grenade', then click near an enemy (red) to throw one!"
		Step.COMPLETE:
			return "Congratulations! You have completed basic training."
	return ""


func allowed_buttons() -> Dictionary:
	match current_step:
		Step.RUN_TO:
			return {"run_to": true}
		Step.GO_PRONE:
			return {"position": true}
		Step.FACE_ENEMY:
			return {"face": true}
		Step.FIRE_AT_WILL:
			return {"fire_at_will": true}
		Step.HOLD_FIRE:
			return {"hold_fire": true}
		Step.MANUAL_FIRE:
			return {"fire_at": true}
		Step.STAND_UP:
			return {"position": true}
		Step.CRAWL:
			return {"crawl_to": true}
		Step.GRENADE:
			return {"grenade": true}
	return {}


func process_tick(game_state, _session) -> void:
	if current_step == Step.WAIT_ARRIVAL:
		var soldier := _get_tutorial_soldier(game_state)
		if soldier != null and not soldier.is_moving:
			advance()
	elif current_step == Step.OBSERVE:
		_observe_timer_sec += SimulationClock.tick_sec()
		if _observe_timer_sec >= OBSERVE_WAIT_SEC:
			advance()


func notify_soldier_selected(soldier_id: int) -> void:
	if current_step == Step.SELECT_SOLDIER and soldier_id == TUTORIAL_SOLDIER_ID:
		advance()


func notify_move_command(soldier_id: int, movement_mode: int) -> void:
	if soldier_id != TUTORIAL_SOLDIER_ID:
		return
	if current_step == Step.RUN_TO and movement_mode == MovementMode.RUN:
		advance()
	elif current_step == Step.CRAWL and movement_mode == MovementMode.CRAWL:
		advance()


func notify_position_changed(soldier_id: int, position_state: int) -> void:
	if soldier_id != TUTORIAL_SOLDIER_ID:
		return
	if current_step == Step.GO_PRONE and position_state == PositionState.DOWN:
		advance()
	elif current_step == Step.STAND_UP and position_state == PositionState.UP:
		advance()


func notify_face_command(soldier_id: int) -> void:
	if current_step == Step.FACE_ENEMY and soldier_id == TUTORIAL_SOLDIER_ID:
		advance()


func notify_fire_control_changed(soldier_id: int, fire_control_state: int) -> void:
	if soldier_id != TUTORIAL_SOLDIER_ID:
		return
	if current_step == Step.FIRE_AT_WILL and fire_control_state == FireControlState.FIRE_AT_WILL:
		advance()
	elif current_step == Step.HOLD_FIRE and fire_control_state == FireControlState.HOLD_FIRE:
		advance()


func notify_fire_at_command(soldier_id: int) -> void:
	if current_step == Step.MANUAL_FIRE and soldier_id == TUTORIAL_SOLDIER_ID:
		advance()


func notify_grenade_command(soldier_id: int) -> void:
	if current_step == Step.GRENADE and soldier_id == TUTORIAL_SOLDIER_ID:
		advance()


func notify_soldier_fired(soldier_id: int) -> void:
	if current_step == Step.OBSERVE and soldier_id == TUTORIAL_SOLDIER_ID:
		advance()


func _get_tutorial_soldier(game_state) -> SoldierState:
	if game_state == null:
		return null
	return game_state.get_soldier(Team.USA, TUTORIAL_SOLDIER_ID)
