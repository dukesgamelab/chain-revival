class_name StressLabels
extends RefCounted
## Stress band display labels (shared by CombatSystem and SoldierState).


static func state_label(stress: float) -> String:
	match _stress_band(stress):
		1:
			return "Nervous"
		2:
			return "Suppressed"
		3:
			return "Pinned"
		4:
			return "Panicked"
		_:
			return "OK"


static func _stress_band(stress: float) -> int:
	if stress < 10.0:
		return 0
	if stress < 25.0:
		return 1
	if stress < 45.0:
		return 2
	if stress < 70.0:
		return 3
	return 4
