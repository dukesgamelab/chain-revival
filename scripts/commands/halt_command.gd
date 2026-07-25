class_name HaltCommand
extends RefCounted
## Plain data: stop in-progress movement for a soldier or fireteam.
## ActionResolver clears paths via the shared combat-halt path (movement_halts).

enum Scope { SINGLE, SQUAD }

var team_id: int = Team.BLUE
var soldier_id: int = 1
var scope: Scope = Scope.SQUAD
