extends SceneTree

const Suite = preload("res://addons/code_ui/_export_ignore/test/preview_test.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var suite_script: GDScript = Suite
	if suite_script.reload(true) != OK or not suite_script.has_method(&"run_tests"):
		quit(1)
		return
	var report: Dictionary = await Suite.run_tests()
	for line in report.get("output", []):
		print(line)
	quit(0 if report.get("completed", false) and report.get("result", 1) == 0 else 1)
