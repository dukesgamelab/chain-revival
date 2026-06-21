class_name OgFrameSequence
extends RefCounted
## Loads OG-style animation frames: PREFIX + letter suffix (e.g. EXP2A3A..EXP2A3W).
##
## Each PNG is typically a 100×100 transparent canvas used for alignment, not final size.


static func load_letter_range(
	directory: String,
	prefix: String,
	first_letter: String = "A",
	last_letter: String = "Z",
) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var from_code := first_letter.unicode_at(0)
	var to_code := last_letter.unicode_at(0)
	if to_code < from_code:
		push_warning("OgFrameSequence: last letter precedes first letter for %s" % prefix)
		return frames

	var dir := directory.trim_suffix("/")

	for code in range(from_code, to_code + 1):
		var frame_path := "%s/%s%s.png" % [dir, prefix, char(code)]
		if not ResourceLoader.exists(frame_path):
			push_warning("OgFrameSequence: missing frame %s" % frame_path)
			continue
		var texture := load(frame_path) as Texture2D
		if texture != null:
			frames.append(texture)

	return frames
