class_name LastKnownMarkers
extends Node2D
## Fog of war: frozen ghost silhouettes where enemies were last seen (Phase 48).
## Presentation only. A marker is dropped when a spotted enemy drops out of sight (or a
## hidden one fires or throws), fades out over LIFETIME_SEC, and goes at once if that
## enemy is spotted again or dies. Ghost sprites live under the movers root so they
## depth-sort with soldiers and walls.

const LIFETIME_SEC := 8.0
## Full ghost strength for this share of the lifetime, then a linear fade to nothing.
const HOLD_FRACTION := 0.25
## Fire At may still pick a marker this fresh (server RECENTLY_SEEN_SEC).
const RECENT_SEC := 2.0

var _movers_root: Node2D = null
## Team.soldier_key -> {"sprite": Node2D, "cell": Vector2i, "offset": Vector2, "born_msec": int}
var _markers: Dictionary = {}


func setup(movers_root: Node2D) -> void:
	_movers_root = movers_root
	set_process(false)


## Drop (or replace) the marker for this soldier, using the view's current frame.
func drop(key: String, view: Soldier, cell: Vector2i, now_msec: int = -1) -> void:
	if view == null:
		return
	clear(key)
	var ghost := view.make_ghost_copy()
	var parent: Node = _movers_root if _movers_root != null else self
	parent.add_child(ghost)
	_markers[key] = {
		"sprite": ghost,
		"cell": cell,
		"offset": ghost.position - IsometricGrid.grid_to_world(cell),
		"born_msec": _now(now_msec),
		"base_alpha": ghost.modulate.a,
	}
	set_process(true)


func clear(key: String) -> void:
	if not _markers.has(key):
		return
	var sprite: Node = _markers[key].get("sprite")
	if is_instance_valid(sprite):
		sprite.queue_free()
	_markers.erase(key)


func clear_all() -> void:
	for key in _markers.keys():
		clear(key)


func has_marker(key: String) -> bool:
	return _markers.has(key)


func marker_cell(key: String) -> Vector2i:
	if not _markers.has(key):
		return Vector2i(-999, -999)
	return _markers[key].get("cell", Vector2i(-999, -999))


func is_recent(key: String, now_msec: int = -1) -> bool:
	if not _markers.has(key):
		return false
	return float(_now(now_msec) - int(_markers[key].get("born_msec", 0))) / 1000.0 <= RECENT_SEC


func count() -> int:
	return _markers.size()


## Camera rotated: put every ghost back on its cell in the new projection.
func refresh_view_rotation() -> void:
	for key in _markers.keys():
		var entry: Dictionary = _markers[key]
		var sprite: Node2D = entry.get("sprite")
		if is_instance_valid(sprite):
			sprite.position = IsometricGrid.grid_to_world(entry.cell) + entry.offset


## Fade markers; free the ones whose time is up. Public so tests can drive it.
func tick(now_msec: int = -1) -> void:
	var now := _now(now_msec)
	for key in _markers.keys():
		var entry: Dictionary = _markers[key]
		var age := float(now - int(entry.born_msec)) / 1000.0
		if age >= LIFETIME_SEC:
			clear(key)
			continue
		var sprite: Node2D = entry.get("sprite")
		if not is_instance_valid(sprite):
			_markers.erase(key)
			continue
		var hold := LIFETIME_SEC * HOLD_FRACTION
		var fade := 1.0
		if age > hold:
			fade = 1.0 - (age - hold) / (LIFETIME_SEC - hold)
		sprite.modulate.a = float(entry.base_alpha) * clampf(fade, 0.0, 1.0)
	if _markers.is_empty():
		set_process(false)


func _process(_delta: float) -> void:
	tick()


func _now(now_msec: int) -> int:
	return now_msec if now_msec >= 0 else Time.get_ticks_msec()
