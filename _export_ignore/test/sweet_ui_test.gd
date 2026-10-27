extends RefCounted

const Generator = preload("res://addons/sweet_ui/src/generator/sweet_ui_generator.gd")
const CHECKS = [
	"res://addons/sweet_ui/_export_ignore/test/runtime/preview_checks.gd",
	"res://addons/sweet_ui/_export_ignore/test/runtime/sweets_checks.gd",
	"res://addons/sweet_ui/_export_ignore/test/runtime/project_generation_checks.gd",
]


static func run_tests() -> Dictionary:
	var setup = Generator.setup()
	if setup.error != OK:
		return {"result": 1, "output": [setup.message], "completed": true}
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var filesystem = Engine.get_singleton(&"EditorInterface").get_resource_filesystem()
		filesystem.scan()
		while filesystem.is_scanning():
			await Engine.get_main_loop().process_frame
		await Engine.get_main_loop().process_frame
	var failures = 0
	var output: Array = []
	for path in CHECKS:
		var checks: GDScript = load(path)
		if checks == null or checks.reload(true) != OK or not checks.has_method(&"run_tests"):
			return {"result": failures + 1, "output": output + ["Failed to load " + path], "completed": true}
		var result: Dictionary = await checks.run_tests()
		failures += result.get("result", 1)
		output.append_array(result.get("output", []))
	return {"result": failures, "output": output, "completed": true}
