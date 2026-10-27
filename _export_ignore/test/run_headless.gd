extends SceneTree

const GENERATOR_PATH = "res://addons/sweet_ui/src/generator/sweet_ui_generator.gd"
const SUITE_PATH = "res://addons/sweet_ui/_export_ignore/test/sweet_ui_test.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var imported = ProjectSettings.get_global_class_list().any(func(entry): return entry.class == "_SweetUIGenerator")
	if not imported:
		if "--sweet-ui-imported" in OS.get_cmdline_user_args():
			printerr("Sweet UI generator was not registered by the import pass.")
			quit(1)
		else:
			_import_and_restart()
		return
	var generator: GDScript = load(GENERATOR_PATH)
	if generator == null or not generator.has_method(&"setup"):
		quit(1)
		return
	var setup: Dictionary = generator.setup()
	if setup.error != OK:
		printerr(setup.message)
		quit(1)
		return
	if setup.changed:
		_import_and_restart()
		return
	var suite: GDScript = load(SUITE_PATH)
	if suite == null or suite.reload(true) != OK or not suite.has_method(&"run_tests"):
		quit(1)
		return
	var report: Dictionary = await suite.run_tests()
	for line in report.get("output", []):
		print(line)
	quit(0 if report.get("completed", false) and report.get("result", 1) == 0 else 1)


## A fresh process must see imported global classes before loading typed suites.
func _import_and_restart() -> void:
	var output: Array = []
	var project = ProjectSettings.globalize_path("res://")
	var temp = OS.get_environment("TMPDIR")
	if temp.is_empty():
		temp = "/tmp"
	var status = OS.execute(OS.get_executable_path(), ["--headless", "--editor", "--recovery-mode", "--import", "--quit", "--path", project, "--log-file", temp.path_join("sweet_ui_test_import.log")], output, true)
	if status == 0:
		output.clear()
		status = OS.execute(OS.get_executable_path(), ["--headless", "--path", project, "--script", get_script().resource_path, "--log-file", temp.path_join("sweet_ui_test_runtime.log"), "--", "--sweet-ui-imported"], output, true)
	for line in output:
		print(line)
	quit(status)
