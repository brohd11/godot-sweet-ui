extends VBoxContainer
## One node tree shared by every preview tab: it is repointed at the active host
## rather than each tab owning a tree, so it can also live in a separate dock.

const NodeTree = preload("uid://dsbpnuf6nc8l8") #! resolve ResourceView.NodeTree

const PreviewHost = preload("res://addons/sweet_ui/src/editor/preview_host.gd")

var node_tree: NodeTree
## The panel that receives scripts dropped on the tree.
var drop_target: Control

var _host: PreviewHost


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	node_tree = NodeTree.new()
	node_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node_tree.object_selected.connect(_on_object_selected)
	node_tree.path_activated.connect(_activate_path)
	node_tree.set_drag_forwarding(Callable(), _can_drop, _drop)
	add_child(node_tree)


func get_host() -> PreviewHost:
	return _host if is_instance_valid(_host) else null


func set_host(host: PreviewHost) -> void:
	if not is_instance_valid(host):
		host = null
	if host == get_host():
		return
	var old = get_host()
	# Unrouted while repointing: clearing the old root emits a null selection meant for nobody.
	_host = null
	if old != null:
		old.tree_state = node_tree.get_tree_state()
		old.preview_changed.disconnect(node_tree.set_root_node)
	if host != null:
		node_tree.set_root_node(host.preview, host.tree_state)
		host.preview_changed.connect(node_tree.set_root_node)
	else:
		node_tree.clear_root()
	_host = host


func _on_object_selected(object: Object) -> void:
	if get_host() != null:
		_host.select_object(object)


func _activate_path(path: String) -> void:
	if not Engine.is_editor_hint() or not ResourceLoader.exists(path):
		return
	if path.get_extension().to_lower() in ["tscn", "scn"]:
		EditorInterface.open_scene_from_path(path)
	else:
		var resource = load(path)
		if resource is Script:
			EditorInterface.edit_script(resource)
		else:
			EditorInterface.edit_resource(resource)


func _can_drop(position: Vector2, data: Variant) -> bool:
	return is_instance_valid(drop_target) and drop_target._can_drop_script(position, data)


func _drop(position: Vector2, data: Variant) -> void:
	if _can_drop(position, data):
		drop_target._drop_script(position, data, get_host())
