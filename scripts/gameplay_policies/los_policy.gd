class_name LOSPolicy
extends RefCounted
## Line-of-sight adjacency / peek tuning.
## Gameplay asks: "How close must a soldier be to peek/use wall cover?"
##
## Geometry of ray traversal stays in LOSSystem; only tunable thresholds live here.

## Chebyshev distance for wall adjacency (peek / use-as-cover). Current rule: <= 1.
const DEFAULT_PEEK_ADJACENCY_CHEBYSHEV := 1


var peek_adjacency_chebyshev: int = DEFAULT_PEEK_ADJACENCY_CHEBYSHEV


func reset_to_defaults() -> void:
	peek_adjacency_chebyshev = DEFAULT_PEEK_ADJACENCY_CHEBYSHEV


func is_adjacent(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if from_cell == to_cell:
		return false
	return (
		maxi(absi(from_cell.x - to_cell.x), absi(from_cell.y - to_cell.y))
		<= peek_adjacency_chebyshev
	)


func apply_config(section: Dictionary) -> void:
	if section.has("peek_adjacency_chebyshev"):
		peek_adjacency_chebyshev = int(section.peek_adjacency_chebyshev)
