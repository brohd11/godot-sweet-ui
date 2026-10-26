extends RefCounted

const UI = preload("res://addons/sweet_ui/src/sweet_ui.gd")
const Wrappers = preload("res://addons/sweet_ui/src/gen/sweets_generated.gd")
const Generator = preload("res://addons/sweet_ui/_export_ignore/generate/sweets_gen.gd")
const Inference = preload("res://addons/sweet_ui/_export_ignore/test/fixtures/sweets_inference.gd")

static var _failures: Array[String]
static var _checks: int


class CountedRect extends ColorRect:
	static var created := 0

	func _init() -> void:
		created += 1


static func run_tests() -> Dictionary:
	_failures = []
	_checks = 0
	var original_target = FileAccess.get_file_as_string(Generator.TARGET)
	var original_classes = FileAccess.get_file_as_string(Generator.CLASSES_TARGET)
	_test_runtime()
	_test_controls()
	_test_generation()
	_test_setter_tags()
	_check("tests preserve production entry script", FileAccess.get_file_as_string(Generator.TARGET) == original_target)
	_check("tests preserve production wrapper classes", FileAccess.get_file_as_string(Generator.CLASSES_TARGET) == original_classes)
	var output: Array = ["Sweet UI factories: %d checks, %d failures" % [_checks, _failures.size()]]
	output.append_array(_failures)
	return {"result": _failures.size(), "output": output, "completed": true}


static func _test_runtime() -> void:
	var parent = Control.new()
	var other_parent = Control.new()
	var sweets = UI.new(parent)
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
		if property.name in ["inferred_button", "inferred_label", "inferred_grid"]:
			var expected = {"inferred_button": "Button", "inferred_label": "Label", "inferred_grid": "GridContainer"}
			_check("native type inferred for " + str(property.name), property.class_name == expected[property.name])
	_check("entire fluent chain infers ColorRect", inferred_type == "ColorRect")
	var fixture = Inference.new()
	_check("inferred chain executes", fixture.inferred_rect.color == Color.GREEN)
	fixture.parent.free()
	parent.free()
	other_parent.free()


static func _test_controls() -> void:
	var parent = Control.new()
	var sweets = UI.new(parent)
	var native_types = ["Button", "Label", "LineEdit", "TextEdit", "TextureRect", "ProgressBar",
		"HBoxContainer", "VBoxContainer", "GridContainer", "MarginContainer", "PanelContainer",
		"ScrollContainer", "CenterContainer", "HSplitContainer", "VSplitContainer"]
	for native_type: String in native_types:
		var wrapper = sweets.call(native_type.to_snake_case())
		_check("factory constructs and attaches " + native_type, wrapper.node().is_class(native_type) and wrapper.node().get_parent() == parent)
		_check("inherited setters stay fluent for " + native_type, wrapper.tooltip_text("Preview").custom_minimum_size(Vector2(80, 24)).mouse_filter(Control.MOUSE_FILTER_IGNORE).visible(false) == wrapper)
		_check("inherited setters apply for " + native_type, wrapper.node().tooltip_text == "Preview" and wrapper.node().custom_minimum_size == Vector2(80, 24) and not wrapper.node().visible)
	var texture = GradientTexture2D.new()
	var button = sweets.button().text("Go").icon(texture).toggle_mode(true).button_pressed(true).disabled(true)
	_check("Button setters", button.node().text == "Go" and button.node().icon == texture and button.node().button_pressed and button.node().disabled)
	var presses: Array = []
	_check("signal connection returns same wrapper", button.pressed(func(): presses.append(true)) == button)
	button.node().pressed.emit()
	_check("inherited Button pressed signal connects", presses == [true])
	for method in button.get_script().get_script_method_list():
		if method.name == &"pressed":
			_check("signal callback argument is typed Callable", method.args.size() == 1 and method.args[0].type == TYPE_CALLABLE)
	var settings = LabelSettings.new()
	var label = sweets.label().text("Hello").label_settings(settings).horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER).vertical_alignment(VERTICAL_ALIGNMENT_BOTTOM).autowrap_mode(TextServer.AUTOWRAP_WORD_SMART)
	_check("Label setters include resource and enums", label.node().text == "Hello" and label.node().label_settings == settings and label.node().horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and label.node().autowrap_mode == TextServer.AUTOWRAP_WORD_SMART)
	var line = sweets.line_edit().text("Secret").placeholder_text("Enter text").editable(false).secret(true)
	_check("LineEdit setters", line.node().text == "Secret" and line.node().placeholder_text == "Enter text" and not line.node().editable and line.node().secret)
	var text = sweets.text_edit().text("Multiline").placeholder_text("Enter text").editable(false).wrap_mode(TextEdit.LINE_WRAPPING_BOUNDARY)
	_check("TextEdit setters", text.node().text == "Multiline" and text.node().placeholder_text == "Enter text" and not text.node().editable and text.node().wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY)
	var image = sweets.texture_rect().texture(texture).expand_mode(TextureRect.EXPAND_IGNORE_SIZE).stretch_mode(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_check("TextureRect setters", image.node().texture == texture and image.node().expand_mode == TextureRect.EXPAND_IGNORE_SIZE and image.node().stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	var progress = sweets.progress_bar().min_value(0.0).max_value(200.0).value(50.0).show_percentage(false)
	_check("inherited Range properties", progress.node().value == 50.0 and progress.node().max_value == 200.0 and not progress.node().show_percentage)
	var row = sweets.h_box_container().alignment(BoxContainer.ALIGNMENT_CENTER)
	var column = sweets.v_box_container().alignment(BoxContainer.ALIGNMENT_END)
	_check("BoxContainer alignment", row.node().alignment == BoxContainer.ALIGNMENT_CENTER and column.node().alignment == BoxContainer.ALIGNMENT_END)
	_check("GridContainer columns", sweets.grid_container().columns(3).node().columns == 3)
	var scroll = sweets.scroll_container().follow_focus(true).horizontal_scroll_mode(ScrollContainer.SCROLL_MODE_DISABLED).vertical_scroll_mode(ScrollContainer.SCROLL_MODE_SHOW_ALWAYS).scroll_horizontal(0).scroll_vertical(0)
	_check("ScrollContainer setters", scroll.node().follow_focus and scroll.node().horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and scroll.node().vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_ALWAYS)
	_check("CenterContainer setter", sweets.center_container().use_top_left(true).node().use_top_left)
	_check("HSplitContainer setters", sweets.h_split_container().split_offset(60).collapsed(true).node().collapsed)
	_check("VSplitContainer setters", sweets.v_split_container().split_offset(60).collapsed(true).node().collapsed)
	var signatures: Dictionary = {}
	for method in label.get_script().get_script_method_list():
		signatures[method.name] = method
	_check("string setter argument is typed", signatures.text.args[0].type == TYPE_STRING)
	_check("global enum setter argument is typed", signatures.horizontal_alignment.args[0].class_name == "HorizontalAlignment")
	_check("resource setter argument is typed", signatures.label_settings.args[0].class_name == "LabelSettings")
	parent.free()


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
	original = original.replace("class_name SweetUI\n", "")
	var source = FileAccess.get_file_as_string(Generator.SOURCE)
	var temp_dir = OS.get_environment("TMPDIR")
	if temp_dir.is_empty():
		temp_dir = "/tmp"
	temp_dir = temp_dir.path_join("sweets_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var target = temp_dir.path_join("sweet_ui.gd")
	var prototype = temp_dir.path_join("prototype.gd")
	var classes_path = temp_dir.path_join("gen/sweets_generated.gd")
	_test_source_options(original, source, prototype, target, classes_path)
	var prefix = "## Handwritten prefix with trailing spaces.  \n" + original.left(original.find(Generator.START))
	var suffix = '\nconst HANDWRITTEN_AFTER = "preserve this"\n'
	var initial = prefix + Generator.START + "\n# stale generated content\n" + Generator.END + suffix
	_write(target, initial)
	_write(target + ".uid", "uid://test_sentinel\n")
	_check("wrapper output directory starts absent", not DirAccess.dir_exists_absolute(classes_path.get_base_dir()))
	result = Generator._generate_file(target, Generator.SOURCE, classes_path)
	_check("generation replaces stale region", result.error == OK and result.changed)
	_check("generation creates wrapper output directory", DirAccess.dir_exists_absolute(classes_path.get_base_dir()))
	_write(classes_path + ".uid", "uid://classes_sentinel\n")
	var generated = FileAccess.get_file_as_string(target)
	var generated_classes = FileAccess.get_file_as_string(classes_path)
	_check("both generated outputs are written", generated_classes.contains("class SwColorRect") and generated.contains("sweets_generated.gd"))
	_check("handwritten prefix preserved byte for byte", generated.begins_with(prefix + Generator.START + "\n"))
	_check("handwritten suffix preserved byte for byte", generated.ends_with(Generator.END + suffix))
	_check("uid preserved", FileAccess.get_file_as_string(target + ".uid") == "uid://test_sentinel\n")
	var modified = FileAccess.get_modified_time(target)
	result = Generator._generate_file(target, Generator.SOURCE, classes_path)
	_check("second generation skips writing", result.error == OK and not result.changed)
	_check("unchanged generation preserves file timestamp", FileAccess.get_modified_time(target) == modified)
	_check("repeated generation deterministic", generated == FileAccess.get_file_as_string(target))
	_write(classes_path, generated_classes + "# stale\n")
	result = Generator._generate_file(target, Generator.SOURCE, classes_path)
	_check("classes can regenerate without changing SweetUI", result.error == OK and result.changed and FileAccess.get_modified_time(target) == modified and FileAccess.get_file_as_string(classes_path) == generated_classes)
	_check("generated classes uid preserved", FileAccess.get_file_as_string(classes_path + ".uid") == "uid://classes_sentinel\n")
	var crlf = initial.replace("\n", "\r\n")
	result = Generator.build_candidate(crlf, Generator.SOURCE, target, classes_path)
	_check("CRLF handwritten text preserved", result.error == OK and result.source.begins_with(prefix.replace("\n", "\r\n")) and result.source.ends_with(suffix.replace("\n", "\r\n")))
	if result.error == OK:
		var again = Generator.build_candidate(result.source, Generator.SOURCE, target, classes_path)
		_check("CRLF generation is idempotent", again.error == OK and again.source == result.source)
		_check("CRLF generation keeps consistent line endings", not result.source.replace("\r\n", "").contains("\r"))
	_write(temp_dir.path_join("payload.gd"), "extends RefCounted\nconst VALUE = 42\n")
	var relative = initial.replace("extends RefCounted\n", 'extends RefCounted\nconst PAYLOAD = preload("./payload.gd")\n')
	_write(target, relative)
	result = Generator._generate_file(target, Generator.SOURCE, classes_path)
	_check("validation preserves handwritten relative preloads", result.error == OK and FileAccess.get_file_as_string(target).contains('const PAYLOAD = preload("./payload.gd")'))
	for malformed in [initial.replace(Generator.START, "# missing"), initial.replace(Generator.END, "# missing"), initial + Generator.START + "\n", Generator.END + "\n" + Generator.START]:
		_write(target, malformed)
		result = Generator._generate_file(target, Generator.SOURCE, classes_path)
		_check("malformed markers rejected without writing", result.error != OK and FileAccess.get_file_as_string(target) == malformed)
		_check("malformed markers leave generated classes intact", FileAccess.get_file_as_string(classes_path) == generated_classes)
	_write(target, initial)
	result = Generator._generate_file(target, temp_dir.path_join("absent.gd"), classes_path)
	_check("missing prototypes leave target intact", result.error != OK and FileAccess.get_file_as_string(target) == initial)
	_write(prototype, source.replace("const TYPES = {}", 'const TYPES = {"SwMissing": {"node": "ColorRect"}}'))
	result = Generator._generate_file(target, prototype, classes_path)
	_check("missing template leaves target intact", result.error != OK and FileAccess.get_file_as_string(target) == initial)
	var override = '\tfunc full_rect() -> SwColorRect:\n\t\t_control.tooltip_text = "SwControl super static -> SwControl:"\n\t\treturn self\n\n'
	var multiline = '\n\tfunc note(\n\t\tvalue: String = "SwControl -> SwControl:",\n\t) -> SwColorRect:\n\t\t_control.tooltip_text = value\n\t\treturn self\n'
	_write(prototype, source.replace("class SwColorRect extends SwControl:\n", "class SwColorRect extends SwControl:\n" + override + multiline))
	result = Generator.build_candidate(initial, prototype, target, classes_path)
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
	var unsupported = "\tfunc unsupported() -> SwColorRect:\n\t\tsuper.full_rect()\n\t\treturn self\n\n"
	_write(prototype, source.replace("class SwColorRect extends SwControl:\n", "class SwColorRect extends SwControl:\n" + unsupported))
	result = Generator._generate_file(target, prototype, classes_path)
	_check("unsupported super calls leave target intact", result.error != OK and FileAccess.get_file_as_string(target) == initial)
	for file in DirAccess.get_files_at(classes_path.get_base_dir()):
		DirAccess.remove_absolute(classes_path.get_base_dir().path_join(file))
	DirAccess.remove_absolute(classes_path.get_base_dir())
	for file in DirAccess.get_files_at(temp_dir):
		DirAccess.remove_absolute(temp_dir.path_join(file))
	DirAccess.remove_absolute(temp_dir)


static func _test_source_options(original: String, source: String, prototype: String, target: String, classes_path: String) -> void:
	var inferred = source.replace("const TYPES = {}\n", "").replace("const RE_EXPORT = false\n", "")
	_write(prototype, inferred)
	var result = Generator.build_candidate(original, prototype, target, classes_path)
	_check("catalog and reexport settings are optional", result.error == OK)
	if result.error == OK:
		_check("prototype names infer native and snake_case factory", result.source.contains("func color_rect(") and result.source.contains("ColorRect.new()"))
	_write(prototype, source.replace("const TYPES = {}", 'const TYPES = {"SwColorRect": {"factory": "rectangle"}}'))
	result = Generator.build_candidate(original, prototype, target, classes_path)
	_check("factory-only override preserves inferred native type", result.error == OK and result.source.contains("func rectangle(") and result.source.contains("ColorRect.new()"))
	_write(prototype, source.replace("SwColorRect", "SwRect").replace("const TYPES = {}", 'const TYPES = {"SwRect": {"node": "ColorRect"}}'))
	result = Generator.build_candidate(original, prototype, target, classes_path)
	_check("native-only override preserves inferred factory name", result.error == OK and result.source.contains("func rect(") and result.source.contains("ColorRect.new()"))
	for bad_source in [source.replace("SwColorRect", "SwMissing"), source.replace("const TYPES = {}", 'const TYPES = {"SwColorRect": {"factory": "control"}}')]:
		_write(prototype, bad_source)
		result = Generator.build_candidate(original, prototype, target, classes_path)
		_check("unresolved types and factory conflicts rejected", result.error != OK)
	var with_inference = original.replace("var _node: Node", "var _node: Node\nvar probe_parent := Control.new()\nvar mode_inferred := color_rect(probe_parent).expand().full_rect().color(Color.GREEN).node()")
	for enabled in [false, true]:
		_write(prototype, source.replace("const RE_EXPORT = false", "const RE_EXPORT = " + str(enabled).to_lower()))
		result = Generator.build_candidate(with_inference, prototype, target, classes_path)
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


static func _test_setter_tags() -> void:
	var temp_dir = OS.get_environment("TMPDIR")
	if temp_dir.is_empty():
		temp_dir = "/tmp"
	temp_dir = temp_dir.path_join("sweets_tags_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var prototype = temp_dir.path_join("prototype.gd")
	var target = temp_dir.path_join("sweet_ui.gd")
	var classes_path = temp_dir.path_join("gen/sweets_generated.gd")
	var original = FileAccess.get_file_as_string(Generator.TARGET).replace("class_name SweetUI\n", "")
	var source = '''extends RefCounted
# Only genuine class-body comments should be processed.
#! set missing_root_property
const NOT_A_TAG = """
#! set missing_string_property
"""
class SwControl:
	#! set tooltip_text, visible, mouse_entered
	var _control: Control
	func marker() -> String:
		#! set missing_function_property
		return "#! set another_missing_property"
class SwColorRect extends SwControl:
	#! set color, tooltip_text, color
	#! set custom_minimum_size
	pass #! set missing_inline_property
class SwButton extends SwControl:
	#! set text, pressed, pressed
	#! set disabled, text
	pass
class SwLineEdit extends SwControl:
	#! set text, text_changed
	pass
'''
	_write(prototype, source)
	var result = Generator.build_candidate(original, prototype, target, classes_path)
	_check("class-body tags ignore strings and function bodies", result.error == OK)
	if result.error == OK:
		_check("repeated setter tags deduplicate", result.classes_source.count("func color(") == 1)
		var parent = Control.new()
		var sweets = result.validation.new(parent)
		var wrapper = sweets.color_rect().tooltip_text("Inherited").color(Color.GREEN).custom_minimum_size(Vector2(32, 16)).visible(false)
		_check("inherited and multiple tags remain fluent", wrapper.node().tooltip_text == "Inherited" and wrapper.node().color == Color.GREEN and not wrapper.node().visible and wrapper.node().custom_minimum_size == Vector2(32, 16))
		_check("method strings preserve tag text", wrapper.marker() == "#! set another_missing_property")
		var events: Array = []
		var button = sweets.button().text("Go").pressed(func(): events.append("pressed")).disabled(false)
		button.node().pressed.emit()
		_check("mixed properties and signals across repeated tags", button.node().text == "Go" and events == ["pressed"])
		_check("repeated signal tags deduplicate", result.classes_source.count("func pressed(") == 1)
		wrapper.mouse_entered(func(): events.append("entered"))
		wrapper.node().mouse_entered.emit()
		_check("inherited signal tags connect", events == ["pressed", "entered"])
		var line = sweets.line_edit().text_changed(func(value: String): events.append(value))
		line.node().text_changed.emit("typed")
		_check("signal callback receives native arguments", events.back() == "typed")
		parent.free()
	var custom_method = "\tfunc color(value: Color) -> SwColorRect:\n\t\t_control.modulate = value\n\t\treturn self\n"
	_write(prototype, source.replace("class SwColorRect extends SwControl:\n", "class SwColorRect extends SwControl:\n" + custom_method))
	result = Generator.build_candidate(original, prototype, target, classes_path)
	_check("handwritten setter override compiles", result.error == OK)
	if result.error == OK:
		_check("handwritten setter emitted once", result.classes_source.count("func color(") == 1)
		var parent = Control.new()
		var sweets = result.validation.new(parent)
		var wrapper = sweets.color_rect().color(Color.RED)
		_check("handwritten method takes precedence", wrapper.node().modulate == Color.RED and wrapper.node().color == Color.WHITE)
		parent.free()
	var custom_signal = "\tfunc pressed(callable: Callable) -> SwButton:\n\t\t_control.pressed.connect(callable, Object.CONNECT_ONE_SHOT)\n\t\treturn self\n"
	_write(prototype, source.replace("class SwButton extends SwControl:\n", "class SwButton extends SwControl:\n" + custom_signal))
	result = Generator.build_candidate(original, prototype, target, classes_path)
	_check("handwritten signal override compiles", result.error == OK)
	if result.error == OK:
		_check("handwritten signal method emitted once", result.classes_source.count("func pressed(") == 1)
		var parent = Control.new()
		var sweets = result.validation.new(parent)
		var events: Array = []
		var button = sweets.button().pressed(func(): events.append(true))
		button.node().pressed.emit()
		button.node().pressed.emit()
		_check("handwritten signal method takes precedence", events == [true])
		parent.free()
	# Store a valid pair, then prove invalid tags leave both outputs untouched.
	_write(target, original)
	var initial = Generator._generate_file(target, prototype, classes_path)
	_check("tag output pair writes successfully", initial.error == OK)
	var saved_target = FileAccess.get_file_as_string(target)
	var saved_classes = FileAccess.get_file_as_string(classes_path)
	for invalid_tag in ["missing_property", "missing_signal", "color,", "color; text"]:
		_write(prototype, source.replace("#! set color, tooltip_text, color", "#! set " + invalid_tag))
		result = Generator._generate_file(target, prototype, classes_path)
		_check("invalid setter tag rejected: " + invalid_tag, result.error != OK)
		_check("invalid setter tag preserves both outputs", FileAccess.get_file_as_string(target) == saved_target and FileAccess.get_file_as_string(classes_path) == saved_classes)
	for file in DirAccess.get_files_at(classes_path.get_base_dir()):
		DirAccess.remove_absolute(classes_path.get_base_dir().path_join(file))
	DirAccess.remove_absolute(classes_path.get_base_dir())
	for file in DirAccess.get_files_at(temp_dir):
		DirAccess.remove_absolute(temp_dir.path_join(file))
	DirAccess.remove_absolute(temp_dir)


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
