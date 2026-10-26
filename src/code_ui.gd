class_name CodeUI
extends RefCounted

const Sweets = preload("res://addons/code_ui/src/class/sweets/sweets.gd")

const EDITOR_META = &"ui_editor"


## Preview context is available after construction, including to attached children.
static func is_editor(node: Node) -> bool:
	if not Engine.is_editor_hint():
		return false
	while is_instance_valid(node):
		if node.get_meta(EDITOR_META, false) == true:
			return true
		node = node.get_parent()
	return false
