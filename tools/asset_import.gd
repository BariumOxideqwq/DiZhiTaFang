extends SceneTree

# ---------------------------------------------------------------------------
# 无人值守导入工具：往 res:// 里放了新的美术/音频后，跑一次让它完成导入。
# 用法（不需要开编辑器）：
#   godot --headless --path . --script tools/asset_import.gd
# 同时会清掉早期导入探针留下的临时文件。
# ---------------------------------------------------------------------------


func _init() -> void:
	_remove_leftovers()
	var exe := OS.get_executable_path()
	var project_dir := ProjectSettings.globalize_path("res://")
	var output := []
	var code := OS.execute(exe, ["--headless", "--import", "--path", project_dir], output, true)
	print("asset import finished, exit code: ", code)
	_report_audio()
	quit(0 if code == 0 else 1)


func _remove_leftovers() -> void:
	for leftover in [
		"res://GameResource/Audio/_import_probe.wav",
		"res://GameResource/Audio/_import_probe.wav.import",
	]:
		var absolute := ProjectSettings.globalize_path(leftover)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)
			print("removed leftover: ", leftover)


func _report_audio() -> void:
	var dir := DirAccess.open("res://GameResource/Audio")
	if dir == null:
		return
	for file_name in dir.get_files():
		var path := "res://GameResource/Audio/" + file_name
		print("audio: ", file_name, " imported=", ResourceLoader.exists(path))
