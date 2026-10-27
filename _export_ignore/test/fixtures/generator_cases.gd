extends RefCounted

const TARGET_PREFIX = "## Handwritten prefix with trailing spaces.  \n" + """extends RefCounted

var _node: Node
"""
const TARGET_SUFFIX = '\nconst HANDWRITTEN_AFTER = "SweetUI stays literal"\n'
const INFERENCE_MEMBERS = """
var probe_parent := Control.new()
var mode_inferred := color_rect(probe_parent).expand().full_rect().color(Color.GREEN).node()
var static_inferred := Sweets.color_rect().expand().full_rect().color(Color.GREEN).node()
var from_inferred := color_rect_from(ColorRect.new(), probe_parent).expand().color(Color.BLUE).node()
var static_from_inferred := Sweets.color_rect(from_inferred).expand().c()
"""
const ADDED_INFERENCE_MEMBERS = """
var probe_parent := Control.new()
var added_inferred := check_box(probe_parent).expand().text("Extra").node()
var added_static_inferred := Sweets.check_box().expand().text("Static extra").node()
"""

const CONTROL_BODY = """class SwControl extends RefCounted:
	var _control: Control

	func expand() -> SwControl:
		_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return self

	func full_rect() -> SwControl:
		_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return self


"""
const RECT_BODY = """class SwColorRect extends SwControl:
	#! set color
	pass
"""
const BASIC_BODY = CONTROL_BODY + RECT_BODY
const RENAMED_BODY = CONTROL_BODY + """class SwRect extends SwControl:
	#! set color
	pass
"""
const MISSING_NATIVE_BODY = CONTROL_BODY + """class SwMissing extends SwControl:
	pass
"""
const ADDITIONAL_BODY = BASIC_BODY + """

class SwCheckBox extends SwControl:
	#! set text, button_pressed
	pass
"""
const OVERRIDE_BODY = CONTROL_BODY + """class SwColorRect extends SwControl:
	#! set color

	func full_rect() -> SwColorRect:
		_control.tooltip_text = "SwControl super static -> SwControl:"
		return self

	func note(
		value: String = "SwControl -> SwControl:",
	) -> SwColorRect:
		_control.tooltip_text = value
		return self
"""
const UNSUPPORTED_BODY = CONTROL_BODY + """class SwColorRect extends SwControl:
	func unsupported() -> SwColorRect:
		super.full_rect()
		return self
"""

const TAG_CONTROL_BODY = '''# Only genuine class-body comments should be processed.
#! set missing_root_property
const NOT_A_TAG = """
#! set missing_string_property
"""
class SwControl extends RefCounted:
	#! set tooltip_text, visible, mouse_entered
	var _control: Control
	func marker() -> String:
		#! set missing_function_property
		return "#! set another_missing_property"


'''
const COLOR_OVERRIDE = """	func color(value: Color) -> SwColorRect:
		_control.modulate = value
		return self
"""
const SIGNAL_OVERRIDE = """	func pressed(callable: Callable) -> SwButton:
		_control.pressed.connect(callable, Object.CONNECT_ONE_SHOT)
		return self
"""
const UI_CONFLICT = """	func ui():
		return self
"""


static func source(body: String = BASIC_BODY, settings: Dictionary = {}, alternate_format: bool = false) -> String:
	var text = "extends RefCounted\n\n"
	var names = settings.keys()
	names.sort()
	for name: String in names:
		var declaration = "const %s\t=\t%s # fixture setting\n" if alternate_format else "const %s = %s\n"
		text += declaration % [name, var_to_str(settings[name])]
	return text + "\n" + body


static func target(members: String = "", constants: String = "") -> String:
	return TARGET_PREFIX + constants + members + """

func _init(node: Node) -> void:
	_node = node


""" + TARGET_SUFFIX


static func tag_body(rect_methods: String = "", button_methods: String = "", color_members: String = "color, tooltip_text, color") -> String:
	return TAG_CONTROL_BODY + """class SwColorRect extends SwControl:
	#! set %s
	#! set custom_minimum_size
%s	pass #! set missing_inline_property


class SwButton extends SwControl:
	#! set text, pressed, pressed
	#! set disabled, text
%s	pass


class SwLineEdit extends SwControl:
	#! set text, text_changed
	pass
""" % [color_members, rect_methods, button_methods]
