extends Node
## Checks for game updates on startup and handles self-updating.
##
## Queries Supabase site_settings for the latest game_version and download_url.
## If a newer version is available, prompts the user, downloads the zip,
## extracts it, and launches a batch script to replace the running exe.

signal update_check_complete(update_available: bool)
signal update_progress(percent: float)
signal update_failed(reason: String)

const SUPABASE_URL := "https://tnyaqreedvdmyworvqbw.supabase.co"
const SUPABASE_ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRueWFxcmVlZHZkbXl3b3J2cWJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI5NzA5MzQsImV4cCI6MjEwODU0NjkzNH0.z9P6-W9U-NsJYr5TXxeHsc8Z5_flrDZSOqkNNParqPQ"

var remote_version: String = ""
var download_url: String = ""
var _http: HTTPRequest
var _download_http: HTTPRequest
var _download_path: String = ""


func _ready() -> void:
	if OS.has_feature("editor"):
		update_check_complete.emit(false)
		return
	check_for_update()


func check_for_update() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_version_check_complete)
	var url := "%s/rest/v1/site_settings?select=key,value&key=in.(game_version,download_url)" % SUPABASE_URL
	var headers := [
		"apikey: %s" % SUPABASE_ANON_KEY,
		"Authorization: Bearer %s" % SUPABASE_ANON_KEY,
	]
	var err := _http.request(url, headers)
	if err != OK:
		push_warning("AutoUpdater: failed to start version check: %s" % error_string(err))
		update_check_complete.emit(false)


func _on_version_check_complete(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	_http = null

	if response_code != 200:
		push_warning("AutoUpdater: version check returned %d" % response_code)
		update_check_complete.emit(false)
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null or not parsed is Array:
		push_warning("AutoUpdater: invalid version response")
		update_check_complete.emit(false)
		return

	for entry in (parsed as Array):
		if not entry is Dictionary:
			continue
		var d := entry as Dictionary
		match str(d.get("key", "")):
			"game_version":
				remote_version = str(d.get("value", ""))
			"download_url":
				download_url = str(d.get("value", ""))

	if remote_version.is_empty() or download_url.is_empty():
		update_check_complete.emit(false)
		return

	var needs_update := _compare_versions(BuildConfig.VERSION, remote_version)
	update_check_complete.emit(needs_update)


func start_download() -> void:
	if download_url.is_empty():
		update_failed.emit("No download URL available")
		return

	var temp_dir := OS.get_user_data_dir().path_join("updates")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	_download_path = temp_dir.path_join("ChainRevival-update.zip")

	_download_http = HTTPRequest.new()
	_download_http.download_file = _download_path
	add_child(_download_http)
	_download_http.request_completed.connect(_on_download_complete)
	var err := _download_http.request(download_url)
	if err != OK:
		update_failed.emit("Failed to start download: %s" % error_string(err))
		return

	set_process(true)


func _process(_delta: float) -> void:
	if _download_http == null:
		set_process(false)
		return
	var body_size := _download_http.get_body_size()
	var downloaded := _download_http.get_downloaded_bytes()
	if body_size > 0:
		update_progress.emit(float(downloaded) / float(body_size) * 100.0)


func _on_download_complete(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	set_process(false)
	_download_http.queue_free()
	_download_http = null

	if response_code != 200:
		update_failed.emit("Download failed (HTTP %d)" % response_code)
		return

	if not FileAccess.file_exists(_download_path):
		update_failed.emit("Downloaded file not found")
		return

	_apply_update()


func _apply_update() -> void:
	var exe_path := OS.get_executable_path()
	var game_dir := exe_path.get_base_dir()
	var temp_dir := OS.get_user_data_dir().path_join("updates")
	var extract_dir := temp_dir.path_join("extracted")

	# Clean previous extraction
	if DirAccess.dir_exists_absolute(extract_dir):
		_remove_dir_recursive(extract_dir)
	DirAccess.make_dir_recursive_absolute(extract_dir)

	# Extract zip
	var reader := ZIPReader.new()
	var err := reader.open(_download_path)
	if err != OK:
		update_failed.emit("Failed to open update zip: %s" % error_string(err))
		return

	var files := reader.get_files()
	for file_path in files:
		if file_path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(extract_dir.path_join(file_path))
			continue
		var parent := extract_dir.path_join(file_path).get_base_dir()
		DirAccess.make_dir_recursive_absolute(parent)
		var data := reader.read_file(file_path)
		var out := FileAccess.open(extract_dir.path_join(file_path), FileAccess.WRITE)
		if out != null:
			out.store_buffer(data)
			out.close()
	reader.close()

	# Find the actual game files — might be in a subfolder
	var source_dir := _find_exe_in_dir(extract_dir)
	if source_dir.is_empty():
		update_failed.emit("Could not find game executable in update")
		return

	# Write batch updater script
	var bat_path := temp_dir.path_join("update.bat")
	var game_dir_native := ProjectSettings.globalize_path(game_dir).replace("/", "\\")
	var source_dir_native := ProjectSettings.globalize_path(source_dir).replace("/", "\\")
	var exe_name := exe_path.get_file()
	var exe_native := ProjectSettings.globalize_path(game_dir).replace("/", "\\") + "\\" + exe_name
	var bat_content := '@echo off\r\n'
	bat_content += 'echo Updating Chain Revival...\r\n'
	bat_content += 'echo Waiting for game to close...\r\n'
	bat_content += 'timeout /t 2 /nobreak >nul\r\n'
	bat_content += ':waitloop\r\n'
	bat_content += 'tasklist /FI "IMAGENAME eq %s" 2>NUL | find /I "%s" >NUL\r\n' % [exe_name, exe_name]
	bat_content += 'if not errorlevel 1 (\r\n'
	bat_content += '    timeout /t 1 /nobreak >nul\r\n'
	bat_content += '    goto waitloop\r\n'
	bat_content += ')\r\n'
	bat_content += 'echo Copying new files...\r\n'
	bat_content += 'xcopy "%s\\*" "%s\\" /E /Y /Q\r\n' % [source_dir_native, game_dir_native]
	bat_content += 'echo Update complete! Restarting...\r\n'
	bat_content += 'start "" "%s"\r\n' % exe_native
	bat_content += 'del "%s"\r\n' % ProjectSettings.globalize_path(bat_path).replace("/", "\\")
	bat_content += 'exit\r\n'

	var bat_file := FileAccess.open(bat_path, FileAccess.WRITE)
	if bat_file == null:
		update_failed.emit("Failed to write updater script")
		return
	bat_file.store_string(bat_content)
	bat_file.close()

	# Launch the batch script and quit
	var bat_native := ProjectSettings.globalize_path(bat_path).replace("/", "\\")
	OS.create_process("cmd.exe", ["/c", bat_native])
	get_tree().quit()


func _find_exe_in_dir(dir_path: String) -> String:
	var da := DirAccess.open(dir_path)
	if da == null:
		return ""
	da.list_dir_begin()
	var found_exe := false
	var file_name := da.get_next()
	while not file_name.is_empty():
		if file_name.ends_with(".exe"):
			found_exe = true
			break
		file_name = da.get_next()
	da.list_dir_end()

	if found_exe:
		return dir_path

	# Check one level of subdirectories
	da.list_dir_begin()
	file_name = da.get_next()
	while not file_name.is_empty():
		if da.current_is_dir() and not file_name.begins_with("."):
			var sub := _find_exe_in_dir(dir_path.path_join(file_name))
			if not sub.is_empty():
				return sub
		file_name = da.get_next()
	da.list_dir_end()
	return ""


func _remove_dir_recursive(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var file_name := da.get_next()
	while not file_name.is_empty():
		var full := path.path_join(file_name)
		if da.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		file_name = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)


static func _compare_versions(local: String, remote: String) -> bool:
	var l := _parse_version(local)
	var r := _parse_version(remote)
	for i in range(mini(l.size(), r.size())):
		if r[i] > l[i]:
			return true
		if r[i] < l[i]:
			return false
	return r.size() > l.size()


static func _parse_version(ver: String) -> Array[int]:
	var cleaned := ver.strip_edges()
	# Remove leading 'v' and trailing labels like '-alpha'
	if cleaned.begins_with("v"):
		cleaned = cleaned.substr(1)
	var dash := cleaned.find("-")
	if dash >= 0:
		cleaned = cleaned.substr(0, dash)
	var parts: Array[int] = []
	for p in cleaned.split("."):
		parts.append(int(p))
	return parts
