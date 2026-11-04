class_name TextUtils
extends RefCounted


static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")
