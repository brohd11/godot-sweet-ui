extends SceneTree

const Suite = preload("res://addons/code_ui/_export_ignore/test/preview_test.gd")
const SweetsSuite = preload("res://addons/code_ui/_export_ignore/test/sweets_test.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var passed = true
	for suite_script: GDScript in [Suite, SweetsSuite]:
		if suite_script.reload(true) != OK or not suite_script.has_method(&"run_tests"):
			quit(1)
			return
		var report: Dictionary = await suite_script.run_tests()
		for line in report.get("output", []):
			print(line)
		passed = passed and report.get("completed", false) and report.get("result", 1) == 0
	quit(0 if passed else 1)
