class_name SetAiPlanCommand
extends RefCounted
## Plain data: set an AI player's selected pre-game plan. Validated by ActionResolver.

## Hierarchy / MatchConfig player_id.
var player_id: int = -1
## Stable AiPlan string id (e.g. "attack_center", "random").
var plan_id: String = ""
