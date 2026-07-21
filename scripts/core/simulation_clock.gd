extends Node
## Autoload: authoritative simulation clock for gameplay timing.
##
## Advanced from Main._process (and manually in tests). Gameplay must not read wall-clock
## Time.get_ticks_msec() for stun/fuse/aim/cooldown — use SimulationClock instead.

var _msec: int = 0


func reset(start_msec: int = 0) -> void:
	_msec = maxi(start_msec, 0)


func get_ticks_msec() -> int:
	return _msec


func advance_msec(delta_msec: int) -> void:
	if delta_msec <= 0:
		return
	_msec += delta_msec


func advance_sec(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	_msec += int(delta_sec * 1000.0)
