class_name SimpleAIController
extends RefCounted
## Very basic offline AI entry point. Expand here later (fire, face, cover, etc.).
##
## v1: on match start in OFFLINE_DEV, each German RUNs to a fixed post outside the
## Hay field's fort-facing (east) wall — the line shown in the reference screenshot.

const MoveCommandClass := preload("res://scripts/commands/move_command.gd")
const MovementModeClass := preload("res://scripts/enums/movement_mode.gd")

## Outside the Hay field east wall (x=20 blockers), facing into the paddock.
## North→south along the fort-side wall (matches the 4-man line in the reference shot).
const HAYFIELD_WALL_POSTS: Array[Vector2i] = [
	Vector2i(21, 72),
	Vector2i(21, 74),
	Vector2i(21, 76),
	Vector2i(21, 78),
]

var _opening_issued: bool = false


## Call once after match start + soldier views exist.
## submit_move: Callable(MoveCommand) — typically main._apply_move_command
func on_match_started(
	game_state: GameState,
	map_data: MapData,
	submit_move: Callable,
	_submit_face: Callable = Callable(),
) -> void:
	if not GameModeManager.is_offline_dev():
		return
	if _opening_issued:
		return
	if game_state == null or map_data == null or not submit_move.is_valid():
		return
	var germany: Fireteam = game_state.session.get_fireteam(Team.GERMANY)
	if germany == null or germany.soldiers.is_empty():
		return

	_opening_issued = true
	var posts := _posts_for_map(map_data)
	var ordered := 0
	for i in germany.soldiers.size():
		var soldier: SoldierState = germany.soldiers[i]
		if soldier == null or not soldier.is_alive():
			continue
		var post: Vector2i = posts[i % posts.size()]
		if not map_data.is_walkable(post):
			GameLog.log_system("[AI] Skip post %s — not walkable" % post)
			continue
		var cmd := MoveCommandClass.new()
		cmd.team_id = Team.GERMANY
		cmd.soldier_id = soldier.soldier_id
		cmd.scope = MoveCommandClass.Scope.SINGLE
		cmd.movement_mode = MovementModeClass.RUN
		cmd.target_cell = post
		submit_move.call(cmd)
		ordered += 1
		GameLog.log_system(
			"[AI] Germany Soldier %d RUN → %s (hay wall post)"
			% [soldier.soldier_id, post]
		)

	if ordered == 0:
		GameLog.log_system("[AI] Germany opening: no walkable hay wall posts")


static func _posts_for_map(map_data: MapData) -> Array[Vector2i]:
	## Fortress hay paddock posts; other maps fall back to the same offsets from label.
	var hay := resolve_landmark_cell(map_data, "Hay field", Vector2i(15, 76))
	if hay == Vector2i(15, 76):
		return HAYFIELD_WALL_POSTS.duplicate()
	## Generic: line just east of the hay label.
	var posts: Array[Vector2i] = []
	for i in 4:
		posts.append(Vector2i(hay.x + 6, hay.y - 4 + i * 2))
	return posts


## Look up a map label by case-insensitive text; returns fallback if missing.
static func resolve_landmark_cell(
	map_data: MapData,
	label_text: String,
	fallback: Vector2i,
) -> Vector2i:
	if map_data == null:
		return fallback
	var want := label_text.strip_edges().to_lower()
	for entry in map_data.labels:
		if not entry is Dictionary:
			continue
		var text := str(entry.get("text", "")).strip_edges().to_lower()
		if text == want:
			return Vector2i(int(entry.get("x", fallback.x)), int(entry.get("y", fallback.y)))
	return fallback
