extends RefCounted

const Generator = preload("res://addons/sweet_ui/src/generator/sweet_ui_generator.gd")

static var _failures: Array[String]
static var _checks: int


static func run_tests() -> Dictionary:
	_failures = []
	_checks = 0
	var temp = OS.get_environment("TMPDIR")
	if temp.is_empty():
		temp = "/tmp"
	var directory = temp.path_join("sweet_ui_project_%d" % Time.get_ticks_usec())
	_check("project setup completes", _test_setup(directory.path_join("setup")))
	_check("custom target checks complete", _test_custom(directory.path_join("custom")))
	_check("class name checks complete", _test_names(directory.path_join("names")))
	_remove(directory)
	return {"result": _failures.size(), "output": ["Sweet UI project generation: %d checks, %d failures" % [_checks, _failures.size()]] + _failures, "completed": true}


static func _test_setup(directory: String) -> bool:
	var result = Generator._setup_directory(directory)
	_check("first setup generates", result.error == OK and result.get("changed", false))
	if result.error != OK:
		_failures.append(result.message)
		return false
	var source = directory.path_join("sweet_ui_source.gd")
	var target = directory.path_join("generated/sweet_ui.gd")
	var wrappers = directory.path_join("generated/sweets_generated.gd")
	var sweets = directory.path_join("generated/sweets.gd")
	var original = FileAccess.get_file_as_string(target)
	var custom_source = FileAccess.get_file_as_string(source).replace("#! set color", "#! set color, modulate") + "\n# Project owned.\n"
	_write(source, custom_source)
	result = Generator._setup_directory(directory)
	_check("enable preserves edited source without regeneration", result.error == OK and not result.changed and FileAccess.get_file_as_string(source) == custom_source and FileAccess.get_file_as_string(target) == original)
	DirAccess.remove_absolute(sweets)
	result = Generator._setup_directory(directory)
	_check("enable repairs missing output using edited source", result.error == OK and result.changed and FileAccess.get_file_as_string(wrappers).contains("func modulate(") and FileAccess.get_file_as_string(source) == custom_source)
	result = Generator._setup_directory(directory, true)
	_check("explicit repeat generation is deterministic", result.error == OK and not result.changed)
	var saved = FileAccess.get_file_as_string(wrappers)
	_write(source, "extends RefCounted\n")
	result = Generator._setup_directory(directory, true)
	_check("invalid user source preserves previous output", result.error != OK and FileAccess.get_file_as_string(wrappers) == saved)
	_check("runtime has no Sweet UI addon dependencies", not original.contains("res://addons/") and not saved.contains("res://addons/"))
	var previous = ProjectSettings.get_setting(Generator.TARGETS_SETTING, Generator.DEFAULT_TARGETS)
	for invalid in ["/tmp/sweet_ui", "res://addons/sweet_ui", "res://addons/sweet_ui/output"]:
		ProjectSettings.set_setting(Generator.TARGETS_SETTING, {invalid: "SweetUI"})
		_check("unsafe output location rejected", Generator.setup().error != OK)
	ProjectSettings.set_setting(Generator.TARGETS_SETTING, {"res://scripts/sweet_ui_conflict": "SweetUI"})
	_check("existing global SweetUI location prevents duplicate generation", Generator.setup().error != OK)
	# Every case is invalid, so validation must fail before anything is written under res://.
	var rejected = {
		"duplicate class names": {"res://sweet_ui_check_a": "SweetDup", "res://sweet_ui_check_b": "SweetDup"},
		"invalid class name": {"res://sweet_ui_check_a": "1Sweet"},
		"engine class name": {"res://sweet_ui_check_a": "Node"},
		"non-string class name": {"res://sweet_ui_check_a": 3},
		"overlapping directories": {"res://sweet_ui_check_a": "", "res://sweet_ui_check_a/inner": ""},
	}
	for label in rejected:
		ProjectSettings.set_setting(Generator.TARGETS_SETTING, rejected[label])
		_check(label + " rejected", Generator.setup().error != OK and not DirAccess.dir_exists_absolute("res://sweet_ui_check_a"))
	ProjectSettings.set_setting(Generator.TARGETS_SETTING, "res://scripts/sweet_ui")
	_check("non-dictionary targets rejected", Generator.setup().error != OK)
	ProjectSettings.set_setting(Generator.TARGETS_SETTING, previous)
	_check("unconfigured single target rejected", Generator.setup(true, "res://sweet_ui_check_a").error != OK)
	ProjectSettings.set_setting(Generator.TARGETS_SETTING, null)
	ProjectSettings.set_setting(Generator.LEGACY_DIRECTORY_SETTING, "res://sweet_ui_legacy/")
	Generator.register_setting()
	_check("legacy directory setting migrates", ProjectSettings.get_setting(Generator.TARGETS_SETTING) == {"res://sweet_ui_legacy/": "SweetUI"} and not ProjectSettings.has_setting(Generator.LEGACY_DIRECTORY_SETTING))
	ProjectSettings.set_setting(Generator.TARGETS_SETTING, previous)
	return true


static func _test_names(directory: String) -> bool:
	var bare_name = RegEx.create_from_string("\\bSweetUI\\b")
	var named = directory.path_join("named")
	var result = Generator._setup_directory(named, false, "SweetUIEditor")
	_check("named target generates", result.error == OK)
	if result.error != OK:
		_failures.append(result.message)
		return false
	var outputs = ["generated/sweet_ui.gd", "generated/sweets_generated.gd", "generated/sweets.gd"].map(func(file): return FileAccess.get_file_as_string(named.path_join(file)))
	_check("named target renames every owner reference", outputs[0].begins_with("class_name SweetUIEditor\n") and outputs.all(func(text): return bare_name.search(text) == null))
	# Wrappers preload the owner, so they compile before the editor registers SweetUIEditor.
	_check("named wrappers preload their owner", outputs[1].contains('const _SweetUI = preload("sweet_ui.gd")') and outputs[1].contains("var _ui:_SweetUI") and not outputs[1].contains("SweetUIEditor"))
	result = Generator._setup_directory(named, false, "")
	_check("renamed target regenerates on setup", result.error == OK and result.changed)
	var unnamed = named
	var target = FileAccess.get_file_as_string(unnamed.path_join("generated/sweet_ui.gd"))
	var wrappers = FileAccess.get_file_as_string(unnamed.path_join("generated/sweets_generated.gd"))
	_check("unnamed target has no class_name", not target.contains("class_name ") and target.contains('const _SweetUI = preload("sweet_ui.gd")'))
	_check("unnamed wrappers preload their owner", wrappers.contains('const _SweetUI = preload("sweet_ui.gd")') and wrappers.contains("func ui() -> _SweetUI:"))
	_check("unnamed outputs drop the global name", [target, wrappers].all(func(text): return bare_name.search(text) == null))
	var owner_script: GDScript = ResourceLoader.load(unnamed.path_join("generated/sweet_ui.gd"), "", ResourceLoader.CACHE_MODE_IGNORE)
	# Not can_instantiate(): generated scripts aren't @tool, so it's false in the editor (Test CI).
	_check("unnamed target loads", owner_script != null and owner_script.reload(true) == OK)
	if owner_script == null:
		return false
	var parent = Control.new()
	var owner = owner_script.new(parent)
	var button = owner.label().text("Title").ui().button().node()
	_check("unnamed owner chains through ui()", button is Button and button.get_parent() == parent and parent.get_child_count() == 2 and owner.to_root() == owner)
	parent.free()
	return true


static func _test_custom(directory: String) -> bool:
	DirAccess.make_dir_recursive_absolute(directory)
	var base_path = directory.path_join("base.gd")
	var custom_path = directory.path_join("custom.gd")
	var source = directory.path_join("sweet_ui_source.gd")
	var target = directory.path_join("sweet_ui.gd")
	var wrappers = directory.path_join("sweets_generated.gd")
	var sweets = directory.path_join("sweets.gd")
	_write(base_path, """extends Control
enum Mode { FIRST, SECOND }
var title: String
var mode: Mode
@export var labels: Array[String]
@export var counts: Dictionary[String, int]
signal title_changed(value: String)
""")
	_write(custom_path, """extends "./base.gd"
static var constructed := 0
var score := 0
func _init() -> void:
	constructed += 1
func bump() -> void:
	score += 1
""")
	var custom: GDScript = load(custom_path)
	var source_text = """extends RefCounted
const Target = preload("./custom.gd")
const TYPES = {"SwFancy": {"node": Target, "factory": "fancy"}}
const RE_EXPORT = %s
class SwControl extends RefCounted:
	var _control
	func expand() -> SwControl:
		_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return self
class SwFancy extends SwControl:
	#! set title, mode, labels, counts, title_changed, tooltip_text
	func bump() -> SwFancy:
		_control.bump()
		return self
	func as_target() -> Target:
		return _control
"""
	var template = """extends RefCounted
var _node: Node
func _init(parent: Node) -> void:
	_node = parent
func probe():
	var node := fancy().expand().node()
	node.bump()
	return node
func probe_static():
	var node := Sweets.fancy().c()
	node.bump()
	return node
"""
	for re_export in [false, true]:
		_write(source, source_text % str(re_export))
		custom.constructed = 0
		var result = Generator.build_candidate(source, target, wrappers, sweets, template)
		_check("custom prototypes compile in both modes", result.error == OK)
		if result.error != OK:
			_failures.append(result.message)
			return false
		_check("generation does not instantiate custom targets", custom.constructed == 0)
		var parent = Control.new()
		var owner = result.validation.new(parent)
		var labels: Array[String] = ["a"]
		var counts: Dictionary[String, int] = {"one": 1}
		var wrapped = owner.fancy().expand().title("Custom").labels(labels).counts(counts).mode(1).tooltip_text("Native").bump()
		_check("custom factory preserves target type and owner", wrapped.node().get_script() == custom and wrapped.ui() == owner and wrapped.node().get_parent() == parent)
		_check("custom inherited setters and handwritten operations execute", wrapped.node().title == "Custom" and wrapped.node().mode == 1 and wrapped.node().labels == ["a"] and wrapped.node().counts == {"one": 1} and wrapped.node().score == 1 and wrapped.node().tooltip_text == "Native")
		_check("source preload alias remains usable in methods", wrapped.as_target() == wrapped.node())
		_check("node accessor infers custom methods", owner.probe().score == 1)
		var inferred_static = owner.probe_static()
		_check("c accessor infers custom methods", inferred_static.score == 1)
		inferred_static.free()
		var received: Array = []
		wrapped.title_changed(func(value: String): received.append(value))
		wrapped.node().title_changed.emit("signal")
		_check("custom inherited signal connects", received == ["signal"])
		var supplied = custom.new()
		var adopted = owner.fancy_from(supplied)
		_check("custom from helper keeps supplied object", adopted.node() == supplied and supplied.get_parent() == parent)
		var static_api: GDScript = result.validation.get_script_constant_map().Sweets
		var detached = static_api.fancy()
		_check("custom static factory creates detached target", detached.node().get_script() == custom and detached.node().get_parent() == null and detached.ui() == null)
		var existing = static_api.fancy(supplied)
		_check("custom static factory preserves existing parent", existing.node() == supplied and supplied.get_parent() == parent and existing.ui() == null)
		detached.node().free()
		parent.free()
		owner = null
		wrapped = null
		adopted = null
		detached = null
		existing = null
		static_api = null
		_check("custom validation types release", Generator._clear_validation(result.validation) == OK)
		result = Generator._generate_file(target, source, wrappers, sweets, template)
		_check("custom runtime files write", result.error == OK)
		var runtime: GDScript = ResourceLoader.load(sweets, "", ResourceLoader.CACHE_MODE_IGNORE)
		var runtime_wrapper = runtime.fancy().title("Runtime")
		_check("generated custom imports compile and execute", runtime_wrapper.node().get_script() == custom and runtime_wrapper.node().title == "Runtime")
		runtime_wrapper.node().free()
	var saved = FileAccess.get_file_as_string(wrappers)
	for body in ["extends Node\n", "extends Control\nfunc _init(required: int):\n\tname = str(required)\n", "@abstract\nextends Control\n"]:
		var invalid_path = directory.path_join("invalid_%d.gd" % body.hash())
		_write(invalid_path, body)
		_write(source, (source_text % "false").replace('./custom.gd', invalid_path))
		var result = Generator._generate_file(target, source, wrappers, sweets, template)
		_check("unsupported custom target preserves output", result.error != OK and FileAccess.get_file_as_string(wrappers) == saved)
	return true


static func _write(path: String, source: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(source)


static func _remove(path: String) -> void:
	for directory in DirAccess.get_directories_at(path):
		_remove(path.path_join(directory))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


static func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures.append("FAIL " + label)
