class_name EnemyVisibilityResult
extends RefCounted

enum Source { NONE, DIRECT, CLUSTER }

var visible: bool = false
var source: int = Source.NONE
var visibility_score: float = -1.0
var spotter_team_id: int = -1
var spotter_soldier_id: int = -1
var cluster_anchor_team_id: int = -1
var cluster_anchor_soldier_id: int = -1
