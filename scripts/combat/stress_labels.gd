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
	return GameplayPolicies.suppression.stress_band(stress)
