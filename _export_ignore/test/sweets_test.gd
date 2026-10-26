extends RefCounted

const Sweets = preload("res://addons/code_ui/src/class/sweets.gd")
const Wrappers = preload("res://addons/code_ui/src/class/sweets_generated.gd")
const Generator = preload("res://addons/code_ui/_export_ignore/generate/sweets_gen.gd")
const Inference = preload("res://addons/code_ui/_export_ignore/test/fixtures/sweets_inference.gd")

static var _failures: Array[String]
static var _checks: int


class CountedRect extends ColorRect:
	static var created := 0

	func _init() -> void:
		created += 1


static func run_tests() -> Dictionary:
	_failures = []
	_checks = 0
	_test_runtime()
	_test_generation()
	var output: Array = ["Sweets: %d checks, %d failures" % [_checks, _failures.size()]]
	output.append_array(_failures)
	return {"result": _failures.size(), "output": output, "completed": true}


static func _test_runtime() -> void:
	var parent = Control.new()
	var other_parent = Control.new()
	var sweets = Sweets.new(parent)
	var node_count = Node.get_orphan_node_ids().size()
	var wrapper = sweets.color_rect()
	_check("factory allocates exactly one node", Node.get_orphan_node_ids().size() == node_count + 1)
	_check("default parent", wrapper.node().get_parent() == parent)
	_check("fluent calls return same wrapper", wrapper.expand().full_rect().color(Color.GREEN) == wrapper)
	_check("color applied", wrapper.node().color == Color.GREEN)
	_check("horizontal expand applied", wrapper.node().size_flags_horizontal == Control.SIZE_EXPAND_FILL)
	_check("vertical expand applied", wrapper.node().size_flags_vertical == Control.SIZE_EXPAND_FILL)
	_check("full rect applied", wrapper.node().anchor_right == 1.0 and wrapper.node().anchor_bottom == 1.0)
	var explicit = sweets.color_rect(other_parent)
	_check("explicit parent overrides default", explicit.node().get_parent() == other_parent)
	var control = sweets.control().expand(false, true)
	_check("expand flags preserve unselected axis", control.node().size_flags_vertical == Control.SIZE_FILL)
	CountedRect.created = 0
	node_count = Node.get_orphan_node_ids().size()
	var direct = Wrappers.SwColorRect.new(CountedRect.new(), other_parent)
	_check("direct construction allocates exactly one node", CountedRect.created == 1 and Node.get_orphan_node_ids().size() == node_count + 1)
	_check("direct wrapper keeps original instance", direct.node().get_script() == CountedRect)
	_check("direct constructor attaches to parent", direct.node().get_parent() == other_parent)
	var wrapper_script: GDScript = Wrappers.SwControl
	for method in wrapper_script.get_script_method_list():
		if method.name == &"_init":
			_check("direct constructor requires both arguments", method.args.size() == 2 and method.default_args.is_empty())
	var inferred_type = ""
	var script: GDScript = Inference
	for property in script.get_script_property_list():
		if property.name == "inferred_rect":
			inferred_type = property.class_name
	_check("entire fluent chain infers ColorRect", inferred_type == "ColorRect")
	var fixture = Inference.new()
	_check("inferred chain executes", fixture.inferred_rect.color == Color.GREEN)
	fixture.parent.free()
	parent.free()
	other_parent.free()


static func _test_generation() -> void:
	var original = FileAccess.get_file_as_string(Generator.TARGET)
	var result = Generator.build_candidate(original)
	_check("committed generated output matches prototypes", result.error == OK and result.source == original)
	if result.error != OK:
		_failures.append(str(result.get("message", "Generation failed")))
		return
	_check("wrapper bodies live in separate generated file", not result.source.contains("class SwColorRect") and result.classes_source.contains("class SwColorRect"))
	_check("reexports disabled by default", not result.source.contains("const SwColorRect ="))
	_check("disabled reexports qualify factory return and constructor", result.source.contains("-> _Generated.SwColorRect:") and result.source.contains("return _Generated.SwColorRect.new(ColorRect.new(), parent)"))
	_check("unused runtime map removed", not result.source.contains("_MAP"))
	_check("attachment helper removed", not result.classes_source.contains("_Helpers") and not result.classes_source.contains("func _add_child"))
	_check("constructors attach directly", result.classes_source.contains("parent.add_child(control)"))
	_check("factory uses required default parent directly", result.source.contains("parent = _node\n") and not result.source.contains("else null"))
	_check("generated wrapper file matches prototypes", FileAccess.get_file_as_string(result.classes_path) == result.classes_source)
	var source = FileAccess.get_file_as_string(Generator.SOURCE)
	var temp_dir = OS.get_environment("TMPDIR")
	if temp_dir.is_empty():
		temp_dir = "/tmp"
	temp_dir = temp_dir.path_join("sweets_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var target = temp_dir.path_join("sweets.gd")
	var prototype = temp_dir.path_join("prototype.gd")
	var classes_path = temp_dir.path_join("sweets_generated.gd")
	_test_source_options(original, source, prototype)
	var prefix = "## Handwritten prefix with trailing spaces.  \n" + original.left(original.find(Generator.START))
	var suffix = '\nconst HANDWRITTEN_AFTER = "preserve this"\n'
	var initial = prefix + Generator.START + "\n# stale generated content\n" + Generator.END + suffix
	_write(target, initial)
	_write(target + ".uid", "uid://test_sentinel\n")
	_write(classes_path + ".uid", "uid://classes_sentinel\n")
	result = Generator._generate_file(target)
	_check("generation replaces stale region", result.error == OK and result.changed)
	var generated = FileAccess.get_file_as_string(target)
	var generated_classes = FileAccess.get_file_as_string(classes_path)
	_check("both generated outputs are written", generated_classes.contains("class SwColorRect") and generated.contains("sweets_generated.gd"))
	_check("handwritten prefix preserved byte for byte", generated.begins_with(prefix + Generator.START + "\n"))
	_check("handwritten suffix preserved byte for byte", generated.ends_with(Generator.END + suffix))
	_check("uid preserved", FileAccess.get_file_as_string(target + ".uid") == "uid://test_sentinel\n")
	_check("generated classes uid preserved", FileAccess.get_file_as_string(classes_path + ".uid") == "uid://classes_sentinel\n")
	var modified = FileAccess.get_modified_time(target)
	result = Generator._generate_file(target)
	_check("second generation skips writing", result.error == OK and not result.changed)
	_check("unchanged generation preserves file timestamp", FileAccess.get_modified_time(target) == modified)
	_check("repeated generation deterministic", generated == FileAccess.get_file_as_string(target))
	_write(classes_path, generated_classes + "# stale\n")
	result = Generator._generate_file(target)
	_check("classes can regenerate without changing Sweets", result.error == OK and result.changed and FileAccess.get_modified_time(target) == modified and FileAccess.get_file_as_string(classes_path) == generated_classes)
	var crlf = initial.replace("\n", "\r\n")
	result = Generator.build_candidate(crlf)
	_check("CRLF handwritten text preserved", result.error == OK and result.source.begins_with(prefix.replace("\n", "\r\n")) and result.source.ends_with(suffix.replace("\n", "\r\n")))
	if result.error == OK:
		var again = Generator.build_candidate(result.source)
		_check("CRLF generation is idempotent", again.error == OK and again.source == result.source)
		_check("CRLF generation keeps consistent line endings", not result.source.replace("\r\n", "").contains("\r"))
	_write(temp_dir.path_join("payload.gd"), "extends RefCounted\nconst VALUE = 42\n")
	var relative = initial.replace("extends RefCounted\n", 'extends RefCounted\nconst PAYLOAD = preload("./payload.gd")\n')
	_write(target, relative)
	result = Generator._generate_file(target)
	_check("validation preserves handwritten relative preloads", result.error == OK and FileAccess.get_file_as_string(target).contains('const PAYLOAD = preload("./payload.gd")'))
	for malformed in [initial.replace(Generator.START, "# missing"), initial.replace(Generator.END, "# missing"), initial + Generator.START + "\n", Generator.END + "\n" + Generator.START]:
		_write(target, malformed)
		result = Generator._generate_file(target)
		_check("malformed markers rejected without writing", result.error != OK and FileAccess.get_file_as_string(target) == malformed)
		_check("malformed markers leave generated classes intact", FileAccess.get_file_as_string(classes_path) == generated_classes)
	_write(target, initial)
	result = Generator._generate_file(target, temp_dir.path_join("absent.gd"))
	_check("missing prototypes leave target intact", result.error != OK and FileAccess.get_file_as_string(target) == initial)
	_write(prototype, source.replace("const TYPES = {}", 'const TYPES = {"SwMissing": {"node": "ColorRect"}}'))
	result = Generator._generate_file(target, prototype)
	_check("missing template leaves target intact", result.error != OK and FileAccess.get_file_as_string(target) == initial)
	var override = '\tfunc full_rect() -> SwColorRect:\n\t\t_control.tooltip_text = "SwControl super static -> SwControl:"\n\t\treturn self\n\n'
	var multiline = '\n\tfunc note(\n\t\tvalue: String = "SwControl -> SwControl:",\n\t) -> SwColorRect:\n\t\t_control.tooltip_text = value\n\t\treturn self\n'
	_write(prototype, source.replace("class SwColorRect extends SwControl:\n", "class SwColorRect extends SwControl:\n" + override) + multiline)
	result = Generator.build_candidate(initial, prototype)
	_check("derived overrides and multiline signatures generate", result.error == OK)
	if result.error == OK:
		var compiled: GDScript = result.validation
		_check("custom generated source compiles", compiled.get_script_method_list().any(func(method): return method.name == &"color_rect"))
		var custom_parent = Control.new()
		var custom = compiled.new(custom_parent)
		var custom_rect = custom.color_rect()
		custom_rect.full_rect()
		_check("derived operation overrides inherited body", custom_rect.node().tooltip_text == "SwControl super static -> SwControl:")
		custom_rect.note()
		_check("signature defaults and string contents preserved", custom_rect.node().tooltip_text == "SwControl -> SwControl:")
		custom_parent.free()
	_write(prototype, source.replace("\t\t_control.color = value", "\t\tsuper.full_rect()\n\t\t_control.color = value"))
	result = Generator._generate_file(target, prototype)
	_check("unsupported super calls leave target intact", result.error != OK and FileAccess.get_file_as_string(target) == initial)
	for file in DirAccess.get_files_at(temp_dir):
		DirAccess.remove_absolute(temp_dir.path_join(file))
	DirAccess.remove_absolute(temp_dir)


static func _test_source_options(original: String, source: String, prototype: String) -> void:
	var inferred = source.replace("const TYPES = {}\n", "").replace("const RE_EXPORT = false\n", "")
	_write(prototype, inferred)
	var result = Generator.build_candidate(original, prototype)
	_check("catalog and reexport settings are optional", result.error == OK)
	if result.error == OK:
		_check("prototype names infer native and snake_case factory", result.source.contains("func color_rect(") and result.source.contains("ColorRect.new()"))
	_write(prototype, source.replace("const TYPES = {}", 'const TYPES = {"SwColorRect": {"factory": "rectangle"}}'))
	result = Generator.build_candidate(original, prototype)
	_check("factory-only override preserves inferred native type", result.error == OK and result.source.contains("func rectangle(") and result.source.contains("ColorRect.new()"))
	_write(prototype, source.replace("SwColorRect", "SwRect").replace("const TYPES = {}", 'const TYPES = {"SwRect": {"node": "ColorRect"}}'))
	result = Generator.build_candidate(original, prototype)
	_check("native-only override preserves inferred factory name", result.error == OK and result.source.contains("func rect(") and result.source.contains("ColorRect.new()"))
	for bad_source in [source.replace("SwColorRect", "SwMissing"), source.replace("const TYPES = {}", 'const TYPES = {"SwColorRect": {"factory": "control"}}')]:
		_write(prototype, bad_source)
		result = Generator.build_candidate(original, prototype)
		_check("unresolved types and factory conflicts rejected", result.error != OK)
	var with_inference = original.replace("var _node: Node", "var _node: Node\nvar probe_parent := Control.new()\nvar mode_inferred := color_rect(probe_parent).expand().full_rect().color(Color.GREEN).node()")
	for enabled in [false, true]:
		_write(prototype, source.replace("const RE_EXPORT = false", "const RE_EXPORT = " + str(enabled).to_lower()))
		result = Generator.build_candidate(with_inference, prototype)
		_check("reexport mode compiles: " + str(enabled), result.error == OK)
		if result.error != OK:
			continue
		var compiled: GDScript = result.validation
		_check("alias presence matches reexport setting", compiled.get_script_constant_map().has("SwColorRect") == enabled)
		var inferred_type = ""
		for property in compiled.get_script_property_list():
			if property.name == "mode_inferred":
				inferred_type = property.class_name
		_check("fluent inference preserved in both reexport modes", inferred_type == "ColorRect")
		var default_parent = Control.new()
		var sweets = compiled.new(default_parent)
		_check("fluent chain runs in both reexport modes", sweets.mode_inferred.color == Color.GREEN)
		sweets.probe_parent.free()
		default_parent.free()
		if enabled:
			var parent = Control.new()
			var wrapper_type = compiled.get_script_constant_map().SwColorRect
			var wrapper = wrapper_type.new(ColorRect.new(), parent)
			_check("reexported constructor accepts parent", wrapper.node().get_parent() == parent)
			parent.free()


static func _write(path: String, source: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("temporary file writable", false)
		return
	file.store_string(source)
	file.close()


static func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures.append("FAIL " + label)
