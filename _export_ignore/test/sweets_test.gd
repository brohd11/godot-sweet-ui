extends RefCounted

const UI = preload("res://addons/sweet_ui/src/sweet_ui.gd")
const Wrappers = preload("res://addons/sweet_ui/src/gen/sweets_generated.gd")
const Generator = preload("res://addons/sweet_ui/_export_ignore/generate/sweets_gen.gd")
const Cases = preload("res://addons/sweet_ui/_export_ignore/test/fixtures/generator_cases.gd")
const Inference = preload("res://addons/sweet_ui/_export_ignore/test/fixtures/sweets_inference.gd")

static var _failures: Array[String]
static var _checks: int
static var _validations: Array[GDScript]
static var _temp_dirs: Array[String]


class CountedRect extends ColorRect:
	static var created := 0

	func _init() -> void:
		created += 1


static func run_tests() -> Dictionary:
	_failures = []
	_checks = 0
	_validations = []
	_temp_dirs = []
	var original_target = FileAccess.get_file_as_string(Generator.TARGET)
	var original_classes = FileAccess.get_file_as_string(Generator.CLASSES_TARGET)
	var original_sweets = FileAccess.get_file_as_string(Generator.SWEETS_TARGET)
	_check("runtime checks complete", _test_runtime())
	_check("static checks complete", _test_static())
	_check("supplied node checks complete", _test_supplied_nodes())
	_check("control checks complete", _test_controls())
	_check("committed output checks complete", _test_committed_output())
	_check("generation checks complete", _test_generation())
	_check("source option checks complete", _test_source_options())
	_check("additional wrapper checks complete", _test_additional_wrapper())
	_check("setter tag checks complete", _test_setter_tags())
	for validation in _validations:
		_check("temporary validation releases its type cycle", Generator._clear_validation(validation) == OK)
	_validations.clear()
	for path in _temp_dirs:
		_remove_workspace(path)
		_check("temporary workspace removed", not DirAccess.dir_exists_absolute(path))
	_temp_dirs.clear()
	_check("tests preserve production entry script", FileAccess.get_file_as_string(Generator.TARGET) == original_target)
	_check("tests preserve production wrapper classes", FileAccess.get_file_as_string(Generator.CLASSES_TARGET) == original_classes)
	_check("tests preserve production static helpers", FileAccess.get_file_as_string(Generator.SWEETS_TARGET) == original_sweets)
	var output: Array = ["Sweet UI factories: %d checks, %d failures" % [_checks, _failures.size()]]
	output.append_array(_failures)
	return {"result": _failures.size(), "output": output, "completed": true}


static func _test_runtime() -> bool:
	var parent = Control.new()
	var other_parent = Control.new()
	var sweets = UI.new(parent)
	var node_count = Node.get_orphan_node_ids().size()
	var wrapper = sweets.color_rect()
	_check("factory allocates exactly one node", Node.get_orphan_node_ids().size() == node_count + 1)
	_check("factory keeps its owner", wrapper.ui() == sweets)
	_check("default parent", wrapper.node().get_parent() == parent)
	_check("fluent calls return same wrapper", wrapper.expand().full_rect().color(Color.GREEN) == wrapper)
	_check("color applied", wrapper.node().color == Color.GREEN)
	_check("horizontal expand applied", wrapper.node().size_flags_horizontal == Control.SIZE_EXPAND_FILL)
	_check("vertical expand applied", wrapper.node().size_flags_vertical == Control.SIZE_EXPAND_FILL)
	_check("full rect applied", wrapper.node().anchor_right == 1.0 and wrapper.node().anchor_bottom == 1.0)
	var explicit = sweets.color_rect(other_parent)
	_check("explicit parent keeps factory owner", explicit.ui() == sweets)
	_check("explicit parent overrides default", explicit.node().get_parent() == other_parent)
	var control = sweets.control().expand(false, true)
	_check("base control keeps factory owner", control.ui() == sweets)
	_check("expand flags preserve unselected axis", control.node().size_flags_vertical == Control.SIZE_FILL)
	CountedRect.created = 0
	node_count = Node.get_orphan_node_ids().size()
	var direct = Wrappers.SwColorRect.with_parent(CountedRect.new(), other_parent, sweets)
	_check("direct construction allocates exactly one node", CountedRect.created == 1 and Node.get_orphan_node_ids().size() == node_count + 1)
	_check("direct wrapper keeps original instance", direct.node().get_script() == CountedRect)
	_check("direct constructor keeps supplied owner", direct.ui() == sweets)
	_check("direct constructor attaches to parent", direct.node().get_parent() == other_parent)
	var wrapper_script: GDScript = Wrappers.SwControl
	for method in wrapper_script.get_script_method_list():
		if method.name == &"_init":
			_check("detached constructor requires one argument", method.args.size() == 1 and method.default_args.is_empty())
		if method.name == &"with_parent":
			_check("attached factory requires three arguments", method.args.size() == 3 and method.default_args.is_empty())
			_check("attached factory types its owner", method.args[2].class_name == "SweetUI")
	var inferred_type = ""
	var script: GDScript = Inference
	for property in script.get_script_property_list():
		if property.name in ["inferred_ui", "inferred_static_ui"]:
			_check("ui accessor infers SweetUI", property.class_name == "SweetUI")
		if property.name == "inferred_rect":
			inferred_type = property.class_name
		if property.name in ["inferred_static_rect", "inferred_static_button"]:
			_check("static chain infers " + str(property.name), property.class_name == ("ColorRect" if property.name == "inferred_static_rect" else "Button"))
		if property.name in ["inferred_from_node", "inferred_from_c", "inferred_static_from_node", "inferred_static_from_c"]:
			_check("supplied node chain infers native ColorRect: " + str(property.name), property.class_name == "ColorRect")
		if property.name in ["inferred_button", "inferred_label", "inferred_grid", "inferred_after_ui"]:
			var expected = {"inferred_button": "Button", "inferred_label": "Label", "inferred_grid": "GridContainer", "inferred_after_ui": "Button"}
			_check("native type inferred for " + str(property.name), property.class_name == expected[property.name])
	_check("entire fluent chain infers ColorRect", inferred_type == "ColorRect")
	var fixture = Inference.new()
	_check("ui accessor executes with same owner", fixture.inferred_ui == fixture.ui)
	_check("chain resumes after ui accessor", fixture.inferred_after_ui.text == "After ui()" and fixture.inferred_after_ui.get_parent() == fixture.parent)
	_check("inferred chain executes", fixture.inferred_rect.color == Color.GREEN)
	_check("static inferred chains execute without parenting", fixture.inferred_static_rect.color == Color.GREEN and fixture.inferred_static_rect.get_parent() == null and fixture.inferred_static_button.text == "Static" and fixture.inferred_static_ui == null)
	_check("subclass inferred chains preserve supplied instance", fixture.inferred_from_node == fixture.supplied_rect and fixture.inferred_static_from_c == fixture.supplied_rect and fixture.supplied_rect.get_parent() == fixture.parent)
	_check("supplied node chains execute setters", fixture.inferred_from_c.color == Color.BLUE and fixture.inferred_static_from_node.color == Color.RED)
	fixture.inferred_static_from_node.free()
	fixture.inferred_static_rect.free()
	fixture.inferred_static_button.free()
	fixture.static_label.node().free()
	fixture.parent.free()
	parent.free()
	other_parent.free()
	return true


static func _test_static() -> bool:
	var native_types = ["Control", "ColorRect", "Button", "Label", "LineEdit", "TextEdit", "TextureRect", "ProgressBar",
		"HBoxContainer", "VBoxContainer", "GridContainer", "MarginContainer", "PanelContainer",
		"ScrollContainer", "CenterContainer", "HSplitContainer", "VSplitContainer"]
	var parent = Control.new()
	var ui = UI.new(parent)
	var static_api: GDScript = UI.Sweets
	for native_type: String in native_types:
		var baseline = Node.get_orphan_node_ids().size()
		var native: Control = ClassDB.instantiate(native_type)
		var native_count = Node.get_orphan_node_ids().size() - baseline
		native.free()
		var node_count = Node.get_orphan_node_ids().size()
		var wrapper = static_api.call(native_type.to_snake_case())
		_check("static factory allocates one native control including its internals: " + native_type, Node.get_orphan_node_ids().size() == node_count + native_count)
		_check("static factory constructs detached " + native_type, wrapper.node().is_class(native_type) and wrapper.node().get_parent() == null)
		_check("static wrapper has no owner for " + native_type, wrapper.ui() == null)
		_check("static operations stay fluent for " + native_type, wrapper.expand().tooltip_text("Detached").visible(false) == wrapper)
		_check("static operations apply for " + native_type, wrapper.node().tooltip_text == "Detached" and not wrapper.node().visible and wrapper.node().size_flags_horizontal == Control.SIZE_EXPAND_FILL)
		parent.add_child(wrapper.node())
		_check("static node attaches normally for " + native_type, wrapper.node().get_parent() == parent and wrapper.ui() == null)
		var supplied = wrapper.node()
		node_count = Node.get_orphan_node_ids().size()
		var existing_wrapper = static_api.call(native_type.to_snake_case(), supplied)
		_check("static supplied node preserves identity and parent: " + native_type, existing_wrapper.node() == supplied and supplied.get_parent() == parent and existing_wrapper.ui() == null)
		_check("static supplied node allocates no nodes: " + native_type, Node.get_orphan_node_ids().size() == node_count)
		parent.remove_child(supplied)
		var attached_wrapper = ui.call(native_type.to_snake_case() + "_from", supplied)
		_check("from helper attaches supplied node with owner: " + native_type, attached_wrapper.node() == supplied and supplied.get_parent() == parent and attached_wrapper.ui() == ui)
		_check("from helper allocates no nodes: " + native_type, Node.get_orphan_node_ids().size() == node_count)
	var presses: Array = []
	var button = UI.Sweets.button().text("Detached").pressed(func(): presses.append(true))
	button.node().pressed.emit()
	_check("detached signal helper connects", presses == [true] and button.node().text == "Detached")
	button.node().free()
	CountedRect.created = 0
	var rect = CountedRect.new()
	var direct = Wrappers.SwColorRect.new(rect)
	_check("detached constructor keeps supplied node", CountedRect.created == 1 and direct.node() == rect and direct.ui() == null)
	_check("detached constructor does not attach", rect.get_parent() == null)
	parent.add_child(rect)
	var existing = Wrappers.SwColorRect.new(rect)
	_check("wrapping existing node preserves parent", existing.node() == rect and rect.get_parent() == parent and existing.ui() == null)
	var added_node = UI.Sweets.label().text("Attach through UI").node()
	var added = ui.add_child(added_node)
	_check("add_child adopts detached node and supplies owner", added.node() == added_node and added.node().get_parent() == parent and added.ui() == ui)
	parent.free()
	return true


static func _test_supplied_nodes() -> bool:
	var parent = Control.new()
	var other_parent = Control.new()
	var ui = UI.new(parent)
	CountedRect.created = 0
	var supplied = CountedRect.new()
	var wrapper = ui.color_rect_from(supplied).expand().color(Color.GREEN)
	_check("from helper preserves scripted subclass", wrapper.node() == supplied and wrapper.node().get_script() == CountedRect and CountedRect.created == 1)
	_check("from helper applies fluent setters", supplied.color == Color.GREEN and supplied.size_flags_horizontal == Control.SIZE_EXPAND_FILL)
	var explicit = ui.color_rect_from(CountedRect.new(), other_parent)
	_check("from helper supports explicit parent", explicit.node().get_parent() == other_parent and explicit.ui() == ui)
	ui.rebase(other_parent)
	var rebased = ui.color_rect_from(CountedRect.new())
	_check("from helper follows current default parent", rebased.node().get_parent() == other_parent and rebased.ui() == ui)
	ui.to_root()
	var static_supplied = CountedRect.new()
	var node_count = Node.get_orphan_node_ids().size()
	var detached = UI.Sweets.color_rect(static_supplied).color(Color.BLUE)
	_check("static factory wraps detached subclass without allocating", detached.node() == static_supplied and static_supplied.get_parent() == null and detached.ui() == null and Node.get_orphan_node_ids().size() == node_count)
	_check("static factory applies fluent setters to supplied subclass", static_supplied.color == Color.BLUE)
	static_supplied.free()
	node_count = Node.get_orphan_node_ids().size()
	var fresh = UI.Sweets.color_rect(null)
	_check("explicit null creates one native node", fresh.node() is ColorRect and fresh.node().get_parent() == null and fresh.ui() == null and Node.get_orphan_node_ids().size() == node_count + 1)
	fresh.node().free()
	var api: GDScript = UI
	for method in api.get_script_method_list():
		if method.name == &"color_rect_from":
			_check("from helper requires typed node and optional parent", method.args.size() == 2 and method.args[0].class_name == "ColorRect" and method.args[1].class_name == "Node" and method.default_args == [null])
	api = UI.Sweets
	for method in api.get_script_method_list():
		if method.name == &"color_rect":
			_check("static helper accepts optional typed node", method.args.size() == 1 and method.args[0].class_name == "ColorRect" and method.default_args == [null])
	parent.free()
	other_parent.free()
	return true


static func _test_controls() -> bool:
	var parent = Control.new()
	var sweets = UI.new(parent)
	var native_types = ["Button", "Label", "LineEdit", "TextEdit", "TextureRect", "ProgressBar",
		"HBoxContainer", "VBoxContainer", "GridContainer", "MarginContainer", "PanelContainer",
		"ScrollContainer", "CenterContainer", "HSplitContainer", "VSplitContainer"]
	for native_type: String in native_types:
		var wrapper = sweets.call(native_type.to_snake_case())
		_check("wrapper returns owner for " + native_type, wrapper.ui() == sweets)
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
	return true


static func _test_committed_output() -> bool:
	var original = FileAccess.get_file_as_string(Generator.TARGET)
	var result = _build_candidate(original)
	_check("production prototypes and entry script compile", result.error == OK)
	if result.error != OK:
		_failures.append(str(result.get("message", "Generation failed")))
		return false
	_check_output("committed entry script matches prototypes", original, result.source)
	_check_output("committed wrappers match prototypes", FileAccess.get_file_as_string(Generator.CLASSES_TARGET), result.classes_source)
	_check_output("committed static helpers match prototypes", FileAccess.get_file_as_string(Generator.SWEETS_TARGET), result.sweets_source)
	return true


static func _test_generation() -> bool:
	var workspace = _workspace("generation")
	var target: String = workspace.target
	var prototype: String = workspace.prototype
	var classes_path: String = workspace.classes
	var sweets_path: String = workspace.sweets
	var initial = Cases.target()
	var prefix = initial.left(initial.find(Generator.START))
	_write(prototype, Cases.source())
	_write(target, initial)
	_write(target + ".uid", "uid://test_sentinel\n")
	_check("wrapper output directory starts absent", not DirAccess.dir_exists_absolute(classes_path.get_base_dir()))
	var result = Generator._generate_file(target, prototype, classes_path, sweets_path)
	_check("generation replaces stale region", result.error == OK and result.get("changed", false))
	if result.error != OK:
		_failures.append(str(result.get("message", "Generation failed")))
		return false
	_check("generation creates wrapper output directory", DirAccess.dir_exists_absolute(classes_path.get_base_dir()))
	_write(classes_path + ".uid", "uid://classes_sentinel\n")
	var generated = FileAccess.get_file_as_string(target)
	var generated_classes = FileAccess.get_file_as_string(classes_path)
	var generated_sweets = FileAccess.get_file_as_string(sweets_path)
	_write(sweets_path + ".uid", "uid://sweets_sentinel\n")
	_check("all generated outputs are written", generated_classes.contains("class SwColorRect") and generated.contains(classes_path) and generated.contains(sweets_path) and generated_sweets.contains("static func color_rect(node: ColorRect = null)"))
	_check("handwritten prefix preserved byte for byte", generated.begins_with(prefix))
	_check("handwritten suffix preserved byte for byte", generated.ends_with(Cases.TARGET_SUFFIX))
	_check("uid preserved", FileAccess.get_file_as_string(target + ".uid") == "uid://test_sentinel\n")
	var modified = FileAccess.get_modified_time(target)
	var sweets_modified = FileAccess.get_modified_time(sweets_path)
	result = Generator._generate_file(target, prototype, classes_path, sweets_path)
	_check("second generation skips writing", result.error == OK and not result.changed)
	_check("unchanged generation preserves file timestamp", FileAccess.get_modified_time(target) == modified)
	_check("repeated generation deterministic", generated == FileAccess.get_file_as_string(target) and generated_sweets == FileAccess.get_file_as_string(sweets_path))
	_check("unchanged static generation preserves timestamp", FileAccess.get_modified_time(sweets_path) == sweets_modified)
	_write(classes_path, generated_classes + "# stale\n")
	result = Generator._generate_file(target, prototype, classes_path, sweets_path)
	_check("classes regenerate independently", result.error == OK and result.changed and FileAccess.get_modified_time(target) == modified and FileAccess.get_file_as_string(classes_path) == generated_classes and FileAccess.get_file_as_string(sweets_path) == generated_sweets)
	_check("generated classes uid preserved", FileAccess.get_file_as_string(classes_path + ".uid") == "uid://classes_sentinel\n")
	_write(sweets_path, generated_sweets + "# stale\n")
	result = Generator._generate_file(target, prototype, classes_path, sweets_path)
	_check("static helpers regenerate independently", result.error == OK and result.changed and FileAccess.get_modified_time(target) == modified and FileAccess.get_file_as_string(sweets_path) == generated_sweets)
	_check("static helper uid preserved", FileAccess.get_file_as_string(sweets_path + ".uid") == "uid://sweets_sentinel\n")
	var crlf = initial.replace("\n", "\r\n")
	result = _build_candidate(crlf, prototype, target, classes_path, sweets_path)
	_check("CRLF handwritten text preserved", result.error == OK and result.source.begins_with(prefix.replace("\n", "\r\n")) and result.source.ends_with(Cases.TARGET_SUFFIX.replace("\n", "\r\n")))
	if result.error == OK:
		var again = _build_candidate(result.source, prototype, target, classes_path, sweets_path)
		_check("CRLF generation is idempotent", again.error == OK and again.source == result.source)
		_check("CRLF generation keeps consistent line endings", not result.source.replace("\r\n", "").contains("\r"))
	_write(workspace.dir.path_join("payload.gd"), "extends RefCounted\nconst VALUE = 42\n")
	var relative = Cases.target("", '\nconst PAYLOAD = preload("./payload.gd")\n')
	_write(target, relative)
	result = Generator._generate_file(target, prototype, classes_path, sweets_path)
	_check("validation preserves handwritten relative preloads", result.error == OK and FileAccess.get_file_as_string(target).contains('const PAYLOAD = preload("./payload.gd")'))
	for malformed in [initial.replace(Generator.START, "# missing"), initial.replace(Generator.END, "# missing"), initial + Generator.START + "\n", Generator.END + "\n" + Generator.START]:
		_write(target, malformed)
		result = Generator._generate_file(target, prototype, classes_path, sweets_path)
		_check("malformed markers rejected without writing", result.error != OK and FileAccess.get_file_as_string(target) == malformed)
		_check("malformed markers preserve generated scripts", FileAccess.get_file_as_string(classes_path) == generated_classes and FileAccess.get_file_as_string(sweets_path) == generated_sweets)
	_write(target, initial)
	result = Generator._generate_file(target, workspace.dir.path_join("absent.gd"), classes_path, sweets_path)
	_check("missing prototypes preserve all outputs", result.error != OK and FileAccess.get_file_as_string(target) == initial and FileAccess.get_file_as_string(classes_path) == generated_classes and FileAccess.get_file_as_string(sweets_path) == generated_sweets)
	for invalid_source in [Cases.source(Cases.BASIC_BODY, {"TYPES": {"SwMissing": {"node": "ColorRect"}}}), Cases.source(Cases.UNSUPPORTED_BODY)]:
		_write(prototype, invalid_source)
		result = Generator._generate_file(target, prototype, classes_path, sweets_path)
		_check("invalid prototypes preserve all outputs", result.error != OK and FileAccess.get_file_as_string(target) == initial and FileAccess.get_file_as_string(classes_path) == generated_classes and FileAccess.get_file_as_string(sweets_path) == generated_sweets)
	for overrides in [{"SwColorRect": {"factory": "control_from"}}, {"SwControl": {"factory": "color_rect_from"}}]:
		_write(prototype, Cases.source(Cases.BASIC_BODY, {"TYPES": overrides}))
		result = Generator._generate_file(target, prototype, classes_path, sweets_path)
		_check("from name collision rejected in either discovery order", result.error != OK and result.get("message", "").begins_with("Duplicate Sweets factory:"))
		_check("from name collision preserves all outputs", FileAccess.get_file_as_string(target) == initial and FileAccess.get_file_as_string(classes_path) == generated_classes and FileAccess.get_file_as_string(sweets_path) == generated_sweets)
	_write(prototype, Cases.source(Cases.OVERRIDE_BODY))
	result = _build_candidate(initial, prototype, target, classes_path, sweets_path)
	_check("derived overrides and multiline signatures generate", result.error == OK)
	if result.error == OK:
		var compiled: GDScript = result.validation
		_check("validation preserves owner names in strings", compiled.get_script_constant_map().HANDWRITTEN_AFTER == "SweetUI stays literal")
		var parent = Control.new()
		var ui = compiled.new(parent)
		var rect = ui.color_rect()
		_check("temporary generated wrapper keeps typed owner", rect.ui() == ui)
		rect.full_rect()
		_check("derived operation overrides inherited body", rect.node().tooltip_text == "SwControl super static -> SwControl:")
		rect.note()
		_check("signature defaults and string contents preserved", rect.node().tooltip_text == "SwControl -> SwControl:")
		parent.free()
	return true


static func _test_source_options() -> bool:
	var workspace = _workspace("options")
	var target: String = workspace.target
	var prototype: String = workspace.prototype
	var classes_path: String = workspace.classes
	var sweets_path: String = workspace.sweets
	var original = Cases.target()
	_write(prototype, Cases.source())
	var result = _build_candidate(original, prototype, target, classes_path, sweets_path)
	_check("catalog and reexport settings are optional", result.error == OK)
	if result.error == OK:
		var parent = Control.new()
		var ui = result.validation.new(parent)
		_check("prototype names infer native type and factory", ui.color_rect().node() is ColorRect)
		_check("reexports are disabled when omitted", not result.validation.get_script_constant_map().has("SwColorRect"))
		var rect_source: String = result.classes_source.substr(result.classes_source.find("class SwColorRect"))
		_check("handwritten methods and setters sort together alphabetically", rect_source.find("func color(") < rect_source.find("func expand(") and rect_source.find("func expand(") < rect_source.find("func full_rect("))
		parent.free()
	var overrides = [
		{"name": "factory-only", "body": Cases.BASIC_BODY, "types": {"SwColorRect": {"factory": "rectangle"}}, "factory": "rectangle"},
		{"name": "native-only", "body": Cases.RENAMED_BODY, "types": {"SwRect": {"node": "ColorRect"}}, "factory": "rect"},
		{"name": "combined", "body": Cases.RENAMED_BODY, "types": {"SwRect": {"node": "ColorRect", "factory": "rectangle"}}, "factory": "rectangle"},
	]
	for entry in overrides:
		_write(prototype, Cases.source(entry.body, {"TYPES": entry.types}))
		result = _build_candidate(original, prototype, target, classes_path, sweets_path)
		_check(entry.name + " override compiles", result.error == OK)
		if result.error == OK:
			var parent = Control.new()
			var ui = result.validation.new(parent)
			var rect = ui.call(entry.factory)
			_check(entry.name + " override constructs expected node", rect.node() is ColorRect and rect.node().get_parent() == parent and rect.ui() == ui)
			var supplied = ColorRect.new()
			var adopted = ui.call(entry.factory + "_from", supplied)
			_check(entry.name + " from override wraps supplied node", adopted.node() == supplied and supplied.get_parent() == parent and adopted.ui() == ui)
			var wrapped = result.validation.get_script_constant_map().Sweets.call(entry.factory, supplied)
			_check(entry.name + " static override wraps supplied node", wrapped.node() == supplied and supplied.get_parent() == parent and wrapped.ui() == null)
			var detached = result.validation.get_script_constant_map().Sweets.call(entry.factory)
			_check(entry.name + " static override constructs expected node", detached.node() is ColorRect and detached.node().get_parent() == null and detached.ui() == null)
			detached.node().free()
			parent.free()
	var settings = {"TYPES": {"SwColorRect": {"factory": "rectangle"}}, "RE_EXPORT": true}
	_write(prototype, Cases.source(Cases.BASIC_BODY, settings))
	var normal = _build_candidate(original, prototype, target, classes_path, sweets_path)
	_write(prototype, Cases.source(Cases.BASIC_BODY, settings, true))
	var formatted = _build_candidate(original, prototype, target, classes_path, sweets_path)
	_check("settings formatting does not change generation", normal.error == OK and formatted.error == OK and normal.source == formatted.source and normal.classes_source == formatted.classes_source and normal.sweets_source == formatted.sweets_source)
	var invalid_sources = [
		Cases.source(Cases.MISSING_NATIVE_BODY),
		Cases.source(Cases.BASIC_BODY, {"TYPES": {"SwColorRect": {"factory": "control"}}}),
		Cases.source(Cases.BASIC_BODY, {"TYPES": []}),
		Cases.source(Cases.BASIC_BODY, {"RE_EXPORT": "invalid"}),
	]
	for invalid_source in invalid_sources:
		_write(prototype, invalid_source)
		result = _build_candidate(original, prototype, target, classes_path, sweets_path)
		_check("invalid native types, factory conflicts, and settings rejected", result.error != OK)
	var with_inference = Cases.target(Cases.INFERENCE_MEMBERS)
	for enabled in [false, true]:
		_write(prototype, Cases.source(Cases.BASIC_BODY, {"TYPES": {}, "RE_EXPORT": enabled}))
		var production = _build_candidate(FileAccess.get_file_as_string(Generator.TARGET), prototype, target, classes_path, sweets_path)
		_check("handwritten production helpers compile in both reexport modes", production.error == OK)
		if production.error == OK:
			var production_parent = Control.new()
			var production_ui = production.validation.new(production_parent)
			var supplied = ColorRect.new()
			var adopted = production_ui.add_child(supplied)
			_check("handwritten add_child executes in both reexport modes", adopted.node() == supplied and supplied.get_parent() == production_parent and adopted.ui() == production_ui)
			production_parent.free()
		result = _build_candidate(with_inference, prototype, target, classes_path, sweets_path)
		_check("reexport mode compiles: " + str(enabled), result.error == OK)
		if result.error != OK:
			continue
		var compiled: GDScript = result.validation
		_check("alias presence matches reexport setting", compiled.get_script_constant_map().has("SwColorRect") == enabled)
		_write(target, with_inference)
		var written = Generator._generate_file(target, prototype, classes_path, sweets_path)
		_check("reexport outputs written", written.error == OK)
		if written.error != OK:
			continue
		var static_api: GDScript = ResourceLoader.load(sweets_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var static_constants = static_api.get_script_constant_map()
		_check("static alias presence matches reexport setting", static_constants.has("SwColorRect") == enabled)
		var detached_static = static_api.color_rect()
		_check("generated static preload constructs detached node", detached_static.node() is ColorRect and detached_static.node().get_parent() == null and detached_static.ui() == null)
		_check("static factory uses shared wrapper class", detached_static.get_script() == static_constants._Generated.get_script_constant_map().SwColorRect)
		var wrapped_static = static_api.color_rect(detached_static.node())
		_check("generated static preload wraps supplied node in both modes", wrapped_static.node() == detached_static.node() and wrapped_static.ui() == null)
		detached_static.node().free()
		var inferred_type = ""
		for property in compiled.get_script_property_list():
			if property.name == "mode_inferred":
				inferred_type = property.class_name
			if property.name == "static_inferred":
				_check("static fluent inference preserved in both reexport modes", property.class_name == "ColorRect")
			if property.name in ["from_inferred", "static_from_inferred"]:
				_check("supplied node inference preserved in both reexport modes", property.class_name == "ColorRect")
		_check("fluent inference preserved in both reexport modes", inferred_type == "ColorRect")
		var parent = Control.new()
		var ui = compiled.new(parent)
		_check("fluent chain runs in both reexport modes", ui.mode_inferred.color == Color.GREEN)
		_check("static fluent chain runs in both reexport modes", ui.static_inferred.color == Color.GREEN and ui.static_inferred.get_parent() == null)
		_check("supplied node chains run in both reexport modes", ui.from_inferred == ui.static_from_inferred and ui.from_inferred.get_parent() == ui.probe_parent and ui.from_inferred.color == Color.BLUE)
		if enabled:
			var wrapper_type = compiled.get_script_constant_map().SwColorRect
			var wrapper = wrapper_type.with_parent(ColorRect.new(), parent, ui)
			_check("reexported constructor keeps parent and owner", wrapper.node().get_parent() == parent and wrapper.ui() == ui)
			_check("static alias exposes shared wrapper type", static_constants.SwColorRect == static_constants._Generated.get_script_constant_map().SwColorRect)
			var detached = static_constants.SwColorRect.new(ColorRect.new())
			_check("reexported detached constructor keeps null parent and owner", detached.node().get_parent() == null and detached.ui() == null)
			detached.node().free()
		ui.static_inferred.free()
		ui.probe_parent.free()
		parent.free()
	return true


static func _test_additional_wrapper() -> bool:
	var workspace = _workspace("additional")
	_write(workspace.prototype, Cases.source(Cases.ADDITIONAL_BODY))
	var result = _build_candidate(Cases.target(Cases.ADDED_INFERENCE_MEMBERS), workspace.prototype, workspace.target, workspace.classes, workspace.sweets)
	_check("additional supported wrapper compiles", result.error == OK)
	if result.error != OK:
		return false
	var compiled: GDScript = result.validation
	var inferred_type = ""
	for property in compiled.get_script_property_list():
		if property.name == "added_inferred":
			inferred_type = property.class_name
		if property.name == "added_static_inferred":
			_check("additional static wrapper preserves fluent inference", property.class_name == "CheckBox")
	_check("additional wrapper preserves inherited fluent inference", inferred_type == "CheckBox")
	var parent = Control.new()
	var ui = compiled.new(parent)
	var check_box = ui.check_box().expand().text("Added").button_pressed(true)
	_check("additional wrapper inherits operations and native setters", check_box.node().text == "Added" and check_box.node().button_pressed and check_box.node().size_flags_horizontal == Control.SIZE_EXPAND_FILL)
	_check("additional wrapper keeps parent and owner", check_box.node().get_parent() == parent and check_box.ui() == ui)
	_check("additional inferred chain executes", ui.added_inferred.text == "Extra")
	_check("additional static inferred chain executes", ui.added_static_inferred.text == "Static extra" and ui.added_static_inferred.get_parent() == null)
	ui.added_static_inferred.free()
	ui.probe_parent.free()
	parent.free()
	return true


static func _test_setter_tags() -> bool:
	var workspace = _workspace("tags")
	var target: String = workspace.target
	var prototype: String = workspace.prototype
	var classes_path: String = workspace.classes
	var sweets_path: String = workspace.sweets
	var original = Cases.target()
	_write(prototype, Cases.source(Cases.tag_body()))
	var result = _build_candidate(original, prototype, target, classes_path, sweets_path)
	_check("class-body tags ignore strings and function bodies", result.error == OK)
	if result.error == OK:
		_check("repeated setter tags deduplicate", result.classes_source.count("func color(") == 1)
		var parent = Control.new()
		var ui = result.validation.new(parent)
		var wrapper = ui.color_rect().tooltip_text("Inherited").color(Color.GREEN).custom_minimum_size(Vector2(32, 16)).visible(false)
		_check("inherited and multiple tags remain fluent", wrapper.node().tooltip_text == "Inherited" and wrapper.node().color == Color.GREEN and not wrapper.node().visible and wrapper.node().custom_minimum_size == Vector2(32, 16))
		_check("method strings preserve tag text", wrapper.marker() == "#! set another_missing_property")
		var events: Array = []
		var button = ui.button().text("Go").pressed(func(): events.append("pressed")).disabled(false)
		button.node().pressed.emit()
		_check("mixed properties and signals across repeated tags", events == ["pressed"])
		_check("repeated signal tags deduplicate", result.classes_source.count("func pressed(") == 1)
		wrapper.mouse_entered(func(): events.append("entered"))
		wrapper.node().mouse_entered.emit()
		_check("inherited signal tags connect", events == ["pressed", "entered"])
		var line = ui.line_edit().text_changed(func(value: String): events.append(value))
		line.node().text_changed.emit("typed")
		_check("signal callback receives native arguments", events.back() == "typed")
		parent.free()
	_write(prototype, Cases.source(Cases.tag_body(Cases.COLOR_OVERRIDE)))
	result = _build_candidate(original, prototype, target, classes_path, sweets_path)
	_check("handwritten setter override compiles", result.error == OK)
	if result.error == OK:
		_check("handwritten setter emitted once", result.classes_source.count("func color(") == 1)
		var parent = Control.new()
		var ui = result.validation.new(parent)
		var wrapper = ui.color_rect().color(Color.RED)
		_check("handwritten method takes precedence", wrapper.node().modulate == Color.RED and wrapper.node().color == Color.WHITE)
		parent.free()
	_write(prototype, Cases.source(Cases.tag_body("", Cases.SIGNAL_OVERRIDE)))
	result = _build_candidate(original, prototype, target, classes_path, sweets_path)
	_check("handwritten signal override compiles", result.error == OK)
	if result.error == OK:
		var parent = Control.new()
		var ui = result.validation.new(parent)
		var events: Array = []
		var button = ui.button().pressed(func(): events.append(true))
		button.node().pressed.emit()
		button.node().pressed.emit()
		_check("handwritten signal method takes precedence", events == [true])
		parent.free()
	_write(target, original)
	var initial = Generator._generate_file(target, prototype, classes_path, sweets_path)
	_check("all tag outputs write successfully", initial.error == OK)
	if initial.error != OK:
		return false
	var saved_target = FileAccess.get_file_as_string(target)
	var saved_classes = FileAccess.get_file_as_string(classes_path)
	var saved_sweets = FileAccess.get_file_as_string(sweets_path)
	for invalid_tag in ["missing_property", "missing_signal", "color,", "color; text", "ui", "with_parent"]:
		_write(prototype, Cases.source(Cases.tag_body("", "", invalid_tag)))
		result = Generator._generate_file(target, prototype, classes_path, sweets_path)
		_check("invalid setter tag rejected: " + invalid_tag, result.error != OK)
		_check("invalid setter tag preserves all outputs", FileAccess.get_file_as_string(target) == saved_target and FileAccess.get_file_as_string(classes_path) == saved_classes and FileAccess.get_file_as_string(sweets_path) == saved_sweets)
	_write(prototype, Cases.source(Cases.tag_body(Cases.UI_CONFLICT)))
	var conflict = Generator._generate_file(target, prototype, classes_path, sweets_path)
	_check("handwritten ui accessor rejected", conflict.error != OK)
	_check("conflicting accessor preserves outputs", FileAccess.get_file_as_string(target) == saved_target and FileAccess.get_file_as_string(classes_path) == saved_classes and FileAccess.get_file_as_string(sweets_path) == saved_sweets)
	_write(prototype, Cases.source(Cases.tag_body(Cases.UI_CONFLICT.replace("func ui()", "func with_parent()"))))
	conflict = Generator._generate_file(target, prototype, classes_path, sweets_path)
	_check("handwritten attached factory rejected", conflict.error != OK)
	_check("conflicting factory preserves outputs", FileAccess.get_file_as_string(target) == saved_target and FileAccess.get_file_as_string(classes_path) == saved_classes and FileAccess.get_file_as_string(sweets_path) == saved_sweets)
	return true


static func _workspace(label: String) -> Dictionary:
	var temp_dir = OS.get_environment("TMPDIR")
	if temp_dir.is_empty():
		temp_dir = "/tmp"
	temp_dir = temp_dir.path_join("sweets_%s_%d" % [label, Time.get_ticks_usec()])
	_temp_dirs.append(temp_dir)
	_check("temporary workspace created", DirAccess.make_dir_recursive_absolute(temp_dir) == OK)
	return {"dir": temp_dir, "target": temp_dir.path_join("sweet_ui.gd"),
		"prototype": temp_dir.path_join("prototype.gd"), "classes": temp_dir.path_join("gen/sweets_generated.gd"), "sweets": temp_dir.path_join("sweets.gd")}


static func _remove_workspace(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for dir in DirAccess.get_directories_at(path):
		_remove_workspace(path.path_join(dir))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


static func _build_candidate(original: String, source_path: String = Generator.SOURCE, target_path: String = Generator.TARGET, classes_path: String = Generator.CLASSES_TARGET, sweets_path: String = Generator.SWEETS_TARGET) -> Dictionary:
	var result = Generator.build_candidate(original, source_path, target_path, classes_path, sweets_path)
	if result.error == OK:
		_validations.append(result.validation)
	return result


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


static func _check_output(label: String, committed: String, generated: String) -> void:
	_check(label, committed == generated)
	if committed == generated:
		return
	var expected_lines = committed.split("\n")
	var actual_lines = generated.split("\n")
	for i in maxi(expected_lines.size(), actual_lines.size()):
		var expected = var_to_str(expected_lines[i]) if i < expected_lines.size() else "<EOF>"
		var actual = var_to_str(actual_lines[i]) if i < actual_lines.size() else "<EOF>"
		if expected != actual:
			_failures.append("  First difference at line %d (%s, Godot %s): committed %s; generated %s" % [i + 1, OS.get_name(), Engine.get_version_info().string, expected, actual])
			return
