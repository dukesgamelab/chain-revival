class_name AiObjective
extends RefCounted
## Replaceable objective for an AI Commander. Map-agnostic cell + label.

var objective_id: String = ""
var label: String = ""
var cell: Vector2i = Vector2i(-999, -999)
var kind: String = "sector" ## sector | cover | retreat | support | custom
var priority: int = 0


func is_valid() -> bool:
	return cell.x > -900 and not objective_id.is_empty()


func to_dict() -> Dictionary:
	return {
		"objective_id": objective_id,
		"label": label,
		"cell": {"x": cell.x, "y": cell.y},
		"kind": kind,
		"priority": priority,
	}


static func from_dict(data: Dictionary):
	var obj = new()
	obj.objective_id = str(data.get("objective_id", ""))
	obj.label = str(data.get("label", ""))
	obj.kind = str(data.get("kind", "sector"))
	obj.priority = int(data.get("priority", 0))
	var c: Variant = data.get("cell", {})
	if c is Dictionary:
		obj.cell = Vector2i(int(c.get("x", -999)), int(c.get("y", -999)))
	return obj


static func make(id: String, label_text: String, at: Vector2i, kind_id: String = "sector", prio: int = 0):
	var obj = new()
	obj.objective_id = id
	obj.label = label_text
	obj.cell = at
	obj.kind = kind_id
	obj.priority = prio
	return obj
