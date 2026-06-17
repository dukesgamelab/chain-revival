extends Node
## Combat log — prints and stores recent messages for debugging.

const MAX_LINES := 50

var _lines: Array[String] = []


func log_combat(message: String) -> void:
	print("[Combat] ", message)
	_lines.append(message)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()


func log_system(message: String) -> void:
	print(message)
	_lines.append(message)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()


func get_recent_lines(count: int = 10) -> Array[String]:
	var start := maxi(0, _lines.size() - count)
	return _lines.slice(start)


func clear_log() -> void:
	_lines.clear()
