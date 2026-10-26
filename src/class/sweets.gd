
var _node:Node

func _init(node:Node=null) -> void:
	if is_instance_valid(node):
		_node = node

func create(type:Variant, parent:Node=null) -> Node:
	var ins = type.new()
	if not is_instance_valid(parent):
		parent = _node
	parent.add_child(ins)
	return ins

func full_rect(control:Control):
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
