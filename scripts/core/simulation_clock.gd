extends Node
## Autoload: authoritative simulation clock for gameplay timing.
##
## Advanced in fixed ticks from Main (and manually in tests). Gameplay must not read
## wall-clock Time.get_ticks_msec() for stun/fuse/aim/cooldown — use SimulationClock.
##
## Tick rate: 20 Hz (50 ms). Chosen because:
## - evenly divides auto_fire_scan_interval (0.5 s → exactly 10 ticks per combat scan)
## - keeps fuse/prep/cooldown on a clean millisecond grid
## - separates sim from render without changing combat cadence (~2 Hz scans)

## Fixed simulation rate. Configurable; defaults preserve combat scan math.
const DEFAULT_TICK_HZ := 20
## Cap catch-up steps after a hitch so the sim does not spiral.
const DEFAULT_MAX_CATCHUP_TICKS := 10

var _msec: int = 0
var tick_hz: int = DEFAULT_TICK_HZ
var max_catchup_ticks: int = DEFAULT_MAX_CATCHUP_TICKS


func reset(start_msec: int = 0) -> void:
	_msec = maxi(start_msec, 0)


func get_ticks_msec() -> int:
	return _msec


func tick_msec() -> int:
	return maxi(int(round(1000.0 / float(maxi(tick_hz, 1)))), 1)


func tick_sec() -> float:
	return float(tick_msec()) / 1000.0


func advance_msec(delta_msec: int) -> void:
	if delta_msec <= 0:
		return
	_msec += delta_msec


func advance_sec(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	_msec += int(delta_sec * 1000.0)


## Advance exactly one configured simulation tick.
func advance_tick() -> int:
	var step := tick_msec()
	advance_msec(step)
	return step


func reset_tick_defaults() -> void:
	tick_hz = DEFAULT_TICK_HZ
	max_catchup_ticks = DEFAULT_MAX_CATCHUP_TICKS


func apply_config(section: Dictionary) -> void:
	if section.has("tick_hz"):
		tick_hz = maxi(int(section.tick_hz), 1)
	if section.has("max_catchup_ticks"):
		max_catchup_ticks = maxi(int(section.max_catchup_ticks), 1)
