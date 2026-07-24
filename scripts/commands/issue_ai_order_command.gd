class_name IssueAiOrderCommand
extends RefCounted
## Human (or allied commander) order to an AI-controlled player.

var from_player_id: int = -1
var to_player_id: int = -1
## Stable AiOrder id (attack, defend, hold, retreat, move_to, face_direction, resume_plan).
var order_id: String = ""
var target_cell: Vector2i = Vector2i(-999, -999)
