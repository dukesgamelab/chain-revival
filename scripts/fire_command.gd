class_name FireCommand
extends RefCounted
## Multiplayer-ready fire order issued by UI (Fire At targeting mode).

enum Scope { SINGLE, SQUAD }

var team_id: int = Team.BLUE
var soldier_id: int = 1
var target_team_id: int = Team.RED
var target_soldier_id: int = 1
var scope: Scope = Scope.SINGLE
