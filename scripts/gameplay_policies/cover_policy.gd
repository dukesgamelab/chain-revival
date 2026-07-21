class_name CoverPolicy
extends RefCounted
## Cover hit / visibility modifiers.
## Gameplay asks: "What cover modifier applies?"

## Moderate cover halves final hit chance (e.g. 60% -> 30%).
const DEFAULT_MODERATE_HIT_MULT := 0.5
## Visibility score factor when target is behind moderate cover (matches prior suppression-linked value).
const DEFAULT_MODERATE_VISIBILITY_MULT := 0.65


var moderate_hit_mult: float = DEFAULT_MODERATE_HIT_MULT
var moderate_visibility_mult: float = DEFAULT_MODERATE_VISIBILITY_MULT


func reset_to_defaults() -> void:
	moderate_hit_mult = DEFAULT_MODERATE_HIT_MULT
	moderate_visibility_mult = DEFAULT_MODERATE_VISIBILITY_MULT


func apply_hit_modifier(chance: float, is_moderate_cover: bool) -> float:
	if is_moderate_cover:
		return chance * moderate_hit_mult
	return chance


func apply_config(section: Dictionary) -> void:
	if section.has("moderate_hit_mult"):
		moderate_hit_mult = float(section.moderate_hit_mult)
	if section.has("moderate_visibility_mult"):
		moderate_visibility_mult = float(section.moderate_visibility_mult)
