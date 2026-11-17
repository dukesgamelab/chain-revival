extends Node
## Checks for a newer Windows release on startup and replaces the installed exe and pck.
##
## Release exports ask Supabase site_settings for game_version and download_url.
## Editor runs, debug exports, survival-playtest exports, and a copy sitting next
## to project.godot never download or replace themselves. BuildConfig.is_development()
## is true for the normal Windows release, so it is not a safe updater gate.

signal update_check_complete(update_available: bool)
signal update_progress(percent: float)
signal update_failed(reason: String)

const SUPABASE_URL := "https://tnyaqreedvdmyworvqbw.supabase.co"
const SUPABASE_ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRueWFxcmVlZHZkbXl3b3J2cWJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI5NzA5MzQsImV4cCI6MjEwODU0NjkzNH0.z9P6-W9U-NsJYr5TXxeHsc8Z5_flrDZSOqkNNParqPQ"
const DOWNLOAD_NAME := "ChainRevival-update.zip"

var remote_version: String = ""
var download_url: String = ""
var _http: HTTPRequest
var _download_http: HTTPRequest
var _download_path: String = ""
var _check_started := false


func _ready() -> void:
	# The menu connects these signals after add_child returns. Defer so a
	# synchronous "no update" result is not emitted before that connection.
	call_deferred("_start_update_check")


func updates_allowed() -> bool:
	return _skip_reason().is_empty()


func _start_update_check() -> void:
	var reason := _skip_reason()
	if not reason.is_empty():
		_log("Skipping update check (%s)" % reason)
		update_check_complete.emit(false)
		return
	var marker_path := OS.get_user_data_dir().path_join("updates/just_updated")
	if FileAccess.file_exists(marker_path):
		var applied := FileAccess.get_file_as_string(marker_path).strip_edges()
		DirAccess.remove_absolute(marker_path)
		_log("Skipping one check after applying %s" % applied)
		update_check_complete.emit(false)
		return
	check_for_update()


func check_for_update() -> void:
	if _check_started:
		return
	_check_started = true
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_version_check_complete)
	if _http.is_node_ready():
		_send_version_request()
	else:
		_http.ready.connect(_send_version_request, CONNECT_ONE_SHOT)


func _send_version_request() -> void:
	if _http == null:
		return
	var url := "%s/rest/v1/site_settings?select=key,value&key=in.(game_version,download_url)" % SUPABASE_URL
	var headers := PackedStringArray([
		"apikey: %s" % SUPABASE_ANON_KEY,
		"Authorization: Bearer %s" % SUPABASE_ANON_KEY,
		"User-Agent: ChainRevival/%s" % BuildConfig.VERSION,
		"Accept: application/json",
	])
	var err := _http.request(url, headers)
	if err != OK:
		_log("Version check failed to start: %s" % error_string(err))
		_http.queue_free()
		_http = null
		update_check_complete.emit(false)


func _on_version_check_complete(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _http != null:
		_http.queue_free()
		_http = null
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_log("Version check failed (result %s, HTTP %d)" % [result, response_code])
		update_check_complete.emit(false)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null or not parsed is Array:
		_log("Version check returned a response that was not a settings list")
		update_check_complete.emit(false)
		return
	for entry in (parsed as Array):
		if not entry is Dictionary:
			continue
		var row := entry as Dictionary
		match str(row.get("key", "")):
			"game_version":
				remote_version = setting_text(row.get("value", ""))
			"download_url":
				download_url = setting_text(row.get("value", ""))
	if remote_version.is_empty() or download_url.is_empty():
		_log("Version check is missing game_version or download_url")
		update_check_complete.emit(false)
		return
	if not _is_safe_version(remote_version) or not download_allowed(download_url):
		_log("Published version or download URL was rejected")
		remote_version = ""
		download_url = ""
		update_check_complete.emit(false)
		return
	var needs_update := is_newer(BuildConfig.VERSION, remote_version)
	_log("Installed %s, published %s, update=%s" % [BuildConfig.VERSION, remote_version, needs_update])
	update_check_complete.emit(needs_update)


func start_download() -> void:
	if not updates_allowed():
		_fail("Updates are disabled for this build", false)
		return
	if not download_allowed(download_url):
		_fail("Download URL is not a GitHub release zip", false)
		return
	var temp_dir := OS.get_user_data_dir().path_join("updates")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	_download_path = temp_dir.path_join(DOWNLOAD_NAME)
	_delete_file(_download_path)
	_download_http = HTTPRequest.new()
	_download_http.timeout = 180.0
	_download_http.accept_gzip = false
	_download_http.download_file = _download_path
	_download_http.use_threads = true
	add_child(_download_http)
	_download_http.request_completed.connect(_on_download_complete)
	if _download_http.is_node_ready():
		_send_download_request()
	else:
		_download_http.ready.connect(_send_download_request, CONNECT_ONE_SHOT)


func _send_download_request() -> void:
	if _download_http == null:
		return
	var headers := PackedStringArray([
		"User-Agent: ChainRevival/%s" % BuildConfig.VERSION,
		"Accept: application/octet-stream",
	])
	var err := _download_http.request(download_url, headers)
	if err != OK:
		_fail("Failed to start download: %s" % error_string(err))
		return
	_log("Downloading %s" % download_url)
	set_process(true)


func _process(_delta: float) -> void:
	if _download_http == null:
		set_process(false)
		return
	var body_size := _download_http.get_body_size()
	var downloaded := _download_http.get_downloaded_bytes()
	if body_size > 0:
		update_progress.emit(float(downloaded) / float(body_size) * 100.0)


func _on_download_complete(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	set_process(false)
	if _download_http != null:
		_download_http.queue_free()
		_download_http = null
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fail("Download failed (result %s, HTTP %d)" % [result, response_code])
		return
	if not FileAccess.file_exists(_download_path) or not _is_zip(_download_path):
		_fail("Downloaded file is not a zip")
		return
	var downloaded := FileAccess.open(_download_path, FileAccess.READ)
	var download_size := downloaded.get_length() if downloaded != null else 0
	if downloaded != null:
		downloaded.close()
	_log("Download finished (%d bytes)" % download_size)
	_apply_update()


func _apply_update() -> void:
	if not updates_allowed():
		_fail("Refusing to replace this build")
		return
	var install_exe := OS.get_executable_path()
	var install_pck := install_exe.get_basename() + ".pck"
	if not FileAccess.file_exists(install_exe) or not FileAccess.file_exists(install_pck):
		_fail("Installed exe or pck was not found beside the running game")
		return
	var temp_dir := OS.get_user_data_dir().path_join("updates")
	var extract_dir := temp_dir.path_join("extracted")
	if DirAccess.dir_exists_absolute(extract_dir):
		_remove_dir_recursive(extract_dir)
	DirAccess.make_dir_recursive_absolute(extract_dir)
	var extracted := _extract_zip(_download_path, extract_dir)
	if not extracted.is_empty():
		_fail(extracted)
		return
	var release := _locate_release_files(extract_dir)
	if release.is_empty():
		_fail("Update zip did not contain a Windows exe and matching pck")
		return
	var bat_path := temp_dir.path_join("update.bat")
	var script := build_swap_script(
		install_exe,
		install_pck,
		str(release["exe"]),
		str(release["pck"]),
		temp_dir.path_join("just_updated"),
		temp_dir.path_join("update.log"),
		remote_version,
	)
	if script.is_empty():
		_fail("Could not build a safe updater script for these paths")
		return
	var bat_file := FileAccess.open(bat_path, FileAccess.WRITE)
	if bat_file == null:
		_fail("Failed to write the updater script")
		return
	bat_file.store_string(script)
	bat_file.close()
	var bat_native := _native_path(bat_path)
	var pid := OS.create_process("cmd.exe", PackedStringArray(["/d", "/c", bat_native]))
	if pid <= 0:
		_fail("Could not start the updater")
		return
	_log("Updater started; closing so the exe and pck can be replaced")
	get_tree().quit()


func _extract_zip(zip_path: String, extract_dir: String) -> String:
	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		return "Failed to open update zip: %s" % error_string(err)
	var root := extract_dir.simplify_path()
	for file_path in reader.get_files():
		if not _zip_entry_is_safe(file_path):
			reader.close()
			return "Update zip contained an unsafe path"
		var resolved := root.path_join(file_path).simplify_path()
		if not resolved.begins_with(root):
			reader.close()
			return "Update zip contained an unsafe path"
		if file_path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(resolved)
			continue
		DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
		var out := FileAccess.open(resolved, FileAccess.WRITE)
		if out == null:
			reader.close()
			return "Could not write an extracted update file"
		out.store_buffer(reader.read_file(file_path))
		out.close()
	reader.close()
	return ""


func _fail(reason: String, remove_download: bool = true) -> void:
	_log(reason)
	set_process(false)
	if _download_http != null:
		_download_http.cancel_request()
		_download_http.queue_free()
		_download_http = null
	if remove_download:
		_delete_file(_download_path)
	update_failed.emit(reason)


func _log(message: String) -> void:
	GameLog.log_system("[AutoUpdater] %s" % message)
	var dir := OS.get_user_data_dir().path_join("updates")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("updater.log")
	var log_file := FileAccess.open(path, FileAccess.READ_WRITE)
	if log_file == null:
		log_file = FileAccess.open(path, FileAccess.WRITE)
	if log_file == null:
		return
	log_file.seek_end()
	log_file.store_line("%s %s" % [Time.get_datetime_string_from_system(), message])
	log_file.close()


func _skip_reason() -> String:
	if OS.has_feature("editor"):
		return "editor"
	if not OS.has_feature("release"):
		return "not a release export"
	if OS.get_name() != "Windows":
		return "not Windows"
	if BuildConfig.is_survival_playtest():
		return "survival playtest"
	if FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join("project.godot")):
		return "project checkout"
	return ""


static func is_newer(local: String, remote: String) -> bool:
	var local_parts := _split_version(local)
	var remote_parts := _split_version(remote)
	if (local_parts["core"] as Array).is_empty() or (remote_parts["core"] as Array).is_empty():
		return false
	return _compare_version_order(local_parts, remote_parts) < 0


static func setting_text(value: Variant) -> String:
	var text := str(value).strip_edges()
	if text.begins_with("\"") and text.ends_with("\"") and text.length() >= 2:
		var inner: Variant = JSON.parse_string(text)
		if inner is String:
			return str(inner).strip_edges()
	return text


static func download_allowed(url: String) -> bool:
	var cleaned := url.strip_edges()
	if not cleaned.begins_with("https://github.com/"):
		return false
	if not cleaned.contains("/releases/download/"):
		return false
	if not cleaned.ends_with(".zip"):
		return false
	if cleaned.contains("..") or cleaned.contains(" ") or cleaned.contains("\\") or cleaned.contains("\""):
		return false
	return true


static func build_swap_script(
	install_exe: String,
	install_pck: String,
	source_exe: String,
	source_pck: String,
	marker_path: String,
	log_path: String,
	version: String,
) -> String:
	if not _is_safe_version(version):
		return ""
	var exe := _native_path(install_exe)
	var pck := _native_path(install_pck)
	var new_exe := _native_path(source_exe)
	var new_pck := _native_path(source_pck)
	var marker := _native_path(marker_path)
	var log_path_native := _native_path(log_path)
	var image := exe.get_file()
	for path in [exe, pck, new_exe, new_pck, marker, log_path_native, image]:
		if not _path_is_safe_for_bat(path):
			return ""
	var lines: PackedStringArray = PackedStringArray([
		"@echo off",
		"title Chain Revival Update",
		"setlocal EnableExtensions",
		"set \"EXE=%s\"" % exe,
		"set \"PCK=%s\"" % pck,
		"set \"NEWEXE=%s\"" % new_exe,
		"set \"NEWPCK=%s\"" % new_pck,
		"set \"MARKER=%s\"" % marker,
		"set \"LOG=%s\"" % log_path_native,
		">>\"%%LOG%%\" echo starting %s" % version,
		"set /a TRIES=0",
		":waitloop",
		"set /a TRIES+=1",
		"if %TRIES% GTR 40 goto stillrunning",
		"tasklist /FI \"IMAGENAME eq %s\" 2>NUL | find /I \"%s\" >NUL" % [image, image],
		"if errorlevel 1 goto processgone",
		"ping -n 2 127.0.0.1 >nul",
		"goto waitloop",
		":processgone",
		"ping -n 2 127.0.0.1 >nul",
		"copy /Y \"%NEWEXE%\" \"%EXE%.new\" >nul",
		"if errorlevel 1 goto copyfail",
		"copy /Y \"%NEWPCK%\" \"%PCK%.new\" >nul",
		"if errorlevel 1 goto copyfail",
		"if not exist \"%EXE%.new\" goto copyfail",
		"if not exist \"%PCK%.new\" goto copyfail",
		"if exist \"%EXE%.bak\" del /F /Q \"%EXE%.bak\"",
		"if exist \"%PCK%.bak\" del /F /Q \"%PCK%.bak\"",
		"move /Y \"%EXE%\" \"%EXE%.bak\" >nul",
		"if errorlevel 1 goto swapfail",
		"move /Y \"%PCK%\" \"%PCK%.bak\" >nul",
		"if errorlevel 1 goto restoreexe",
		"move /Y \"%EXE%.new\" \"%EXE%\" >nul",
		"if errorlevel 1 goto restoreboth",
		"move /Y \"%PCK%.new\" \"%PCK%\" >nul",
		"if errorlevel 1 goto restorepck",
		">\"%%MARKER%%\" echo %s" % version,
		">>\"%%LOG%%\" echo success %s" % version,
		"if \"%CHAIN_REVIVAL_SKIP_RELAUNCH%\"==\"1\" goto cleanupbak",
		"start \"\" \"%EXE%\"",
		":cleanupbak",
		"del /F /Q \"%EXE%.bak\" >nul 2>&1",
		"del /F /Q \"%PCK%.bak\" >nul 2>&1",
		"exit /b 0",
		":stillrunning",
		">>\"%LOG%\" echo game still running",
		"goto cleanupnew",
		":copyfail",
		">>\"%LOG%\" echo copy failed",
		"goto cleanupnew",
		":swapfail",
		">>\"%LOG%\" echo could not move the installed exe",
		"goto cleanupnew",
		":restoreexe",
		">>\"%LOG%\" echo could not move the installed pck",
		"move /Y \"%EXE%.bak\" \"%EXE%\" >nul",
		"goto cleanupnew",
		":restoreboth",
		">>\"%LOG%\" echo could not move the new exe into place",
		"if exist \"%EXE%\" del /F /Q \"%EXE%\"",
		"move /Y \"%EXE%.bak\" \"%EXE%\" >nul",
		"if exist \"%PCK%.bak\" move /Y \"%PCK%.bak\" \"%PCK%\" >nul",
		"goto cleanupnew",
		":restorepck",
		">>\"%LOG%\" echo could not move the new pck into place",
		"if exist \"%EXE%\" del /F /Q \"%EXE%\"",
		"move /Y \"%EXE%.bak\" \"%EXE%\" >nul",
		"if exist \"%PCK%\" del /F /Q \"%PCK%\"",
		"move /Y \"%PCK%.bak\" \"%PCK%\" >nul",
		"goto cleanupnew",
		":cleanupnew",
		"if exist \"%EXE%.new\" del /F /Q \"%EXE%.new\"",
		"if exist \"%PCK%.new\" del /F /Q \"%PCK%.new\"",
		">>\"%LOG%\" echo failed, previous install kept",
		"if \"%CHAIN_REVIVAL_SKIP_RELAUNCH%\"==\"1\" exit /b 1",
		"if exist \"%EXE%\" start \"\" \"%EXE%\"",
		"exit /b 1",
		"",
	])
	return "\r\n".join(lines)


static func _locate_release_files(dir_path: String) -> Dictionary:
	var exes := _find_exes(dir_path, 0)
	for exe_path in exes:
		if exe_path.get_file().ends_with(".console.exe"):
			continue
		var pck_path := exe_path.get_basename() + ".pck"
		if _is_pe_exe(exe_path) and _is_godot_pck(pck_path):
			return {"exe": exe_path, "pck": pck_path}
	return {}


static func _find_exes(dir_path: String, depth: int) -> Array[String]:
	var found: Array[String] = []
	var listing := DirAccess.open(dir_path)
	if listing == null:
		return found
	listing.list_dir_begin()
	var file_name := listing.get_next()
	while not file_name.is_empty():
		if not file_name.begins_with("."):
			var full := dir_path.path_join(file_name)
			if listing.current_is_dir():
				if depth < 1:
					found.append_array(_find_exes(full, depth + 1))
			elif file_name.ends_with(".exe"):
				found.append(full)
		file_name = listing.get_next()
	listing.list_dir_end()
	return found


static func _compare_version_order(local_parts: Dictionary, remote_parts: Dictionary) -> int:
	var local_core: Array = local_parts["core"]
	var remote_core: Array = remote_parts["core"]
	var count := maxi(local_core.size(), remote_core.size())
	for i in count:
		var local_value := int(local_core[i]) if i < local_core.size() else 0
		var remote_value := int(remote_core[i]) if i < remote_core.size() else 0
		if local_value != remote_value:
			return -1 if local_value < remote_value else 1
	var local_pre: Array = local_parts["pre"]
	var remote_pre: Array = remote_parts["pre"]
	if local_pre.is_empty() and remote_pre.is_empty():
		return 0
	if local_pre.is_empty():
		return 1
	if remote_pre.is_empty():
		return -1
	var shared := mini(local_pre.size(), remote_pre.size())
	for i in shared:
		var compared := _compare_pre_id(str(local_pre[i]), str(remote_pre[i]))
		if compared != 0:
			return compared
	if local_pre.size() == remote_pre.size():
		return 0
	return -1 if local_pre.size() < remote_pre.size() else 1


static func _compare_pre_id(local_id: String, remote_id: String) -> int:
	var local_numeric := local_id.is_valid_int()
	var remote_numeric := remote_id.is_valid_int()
	if local_numeric and remote_numeric:
		var local_value := int(local_id)
		var remote_value := int(remote_id)
		if local_value == remote_value:
			return 0
		return -1 if local_value < remote_value else 1
	if local_numeric:
		return -1
	if remote_numeric:
		return 1
	if local_id == remote_id:
		return 0
	return -1 if local_id < remote_id else 1


static func _split_version(ver: String) -> Dictionary:
	var cleaned := setting_text(ver).trim_prefix("v").trim_prefix("V")
	var dash := cleaned.find("-")
	var core_text := cleaned if dash < 0 else cleaned.substr(0, dash)
	var pre_text := "" if dash < 0 else cleaned.substr(dash + 1)
	var core: Array[int] = []
	for part in core_text.split("."):
		if part.is_valid_int():
			core.append(int(part))
		elif not part.is_empty():
			return {"core": [], "pre": []}
	var pre: Array[String] = []
	if not pre_text.is_empty():
		for part in pre_text.split("."):
			if not part.is_empty():
				pre.append(part)
	return {"core": core, "pre": pre}


static func _is_safe_version(ver: String) -> bool:
	if ver.is_empty() or ver.length() > 40:
		return false
	for i in ver.length():
		var code := ver.unicode_at(i)
		var is_digit := code >= 48 and code <= 57
		var is_upper := code >= 65 and code <= 90
		var is_lower := code >= 97 and code <= 122
		if not is_digit and not is_upper and not is_lower and code != 45 and code != 46:
			return false
	return true


static func _path_is_safe_for_bat(path: String) -> bool:
	return not path.is_empty() and not path.contains("\"") and not path.contains("%") and not path.contains("\n") and not path.contains("\r") and not path.contains("&") and not path.contains("|")


static func _native_path(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("/", "\\")


static func _zip_entry_is_safe(file_path: String) -> bool:
	if file_path.is_empty() or file_path.contains(".."):
		return false
	if file_path.begins_with("/") or file_path.begins_with("\\"):
		return false
	return true


static func _is_zip(path: String) -> bool:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return false
	var magic := handle.get_buffer(2)
	handle.close()
	return magic.size() == 2 and magic[0] == 0x50 and magic[1] == 0x4B


static func _is_pe_exe(path: String) -> bool:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return false
	var magic := handle.get_buffer(2)
	handle.close()
	return magic.size() == 2 and magic[0] == 0x4D and magic[1] == 0x5A


static func _is_godot_pck(path: String) -> bool:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return false
	var magic := handle.get_buffer(4)
	handle.close()
	return magic == PackedByteArray([0x47, 0x44, 0x50, 0x43])


static func _remove_dir_recursive(path: String) -> void:
	var listing := DirAccess.open(path)
	if listing == null:
		return
	listing.list_dir_begin()
	var file_name := listing.get_next()
	while not file_name.is_empty():
		var full := path.path_join(file_name)
		if listing.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		file_name = listing.get_next()
	listing.list_dir_end()
	DirAccess.remove_absolute(path)


static func _delete_file(path: String) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
