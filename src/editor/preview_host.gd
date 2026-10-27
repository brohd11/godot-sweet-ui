extends VBoxContainer

const EDITOR_META = &"ui_editor"
const NodeTree = preload("uid://dsbpnuf6nc8l8") #! resolve ResourceView.NodeTree

signal tree_width_changed(width: int)

const TREE_MIN_WIDTH = 140
const HIGHLIGHT_ALPHA = 0.25

var script_path: String
var preview: Control
var status: Label
var canvas: Control
var highlight: ColorRect
var split: HSplitContainer
var node_tree: NodeTree

var _tree_side: Side = SIDE_LEFT
var _tree_width := 200
var _inspected_node: WeakRef
var _selected: WeakRef
var _inspect_enabled := true
var _highlight_enabled := true
var _highlighted: WeakRef

var _fingerprint: String
var _rebuild_queued := false
var _stopped := false


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Drop a Control script onto this tab to preview it."
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	node_tree = NodeTree.new()
	node_tree.custom_minimum_size.x = TREE_MIN_WIDTH
	node_tree.size_flags_horizontal = Control.SIZE_FILL
	node_tree.object_selected.connect(_inspect_object)
	node_tree.object_selected.connect(_highlight_object)
	node_tree.path_activated.connect(_activate_path)
	split.add_child(node_tree)
	var preview_area = VBoxContainer.new()
	preview_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(preview_area)
	preview_area.add_child(status)
	canvas = Control.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.clip_contents = true
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_area.add_child(canvas)
	# A canvas sibling of the preview stays out of the node tree and the user's hierarchy.
	highlight = ColorRect.new()
	highlight.name = "Highlight"
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight.color = Color(0.4, 0.6, 1.0, HIGHLIGHT_ALPHA)
	highlight.hide()
	canvas.add_child(highlight)
	split.dragged.connect(_on_split_dragged)
	_apply_tree_width()
	set_process(false)


func _ready() -> void:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var accent = Engine.get_singleton(&"EditorInterface").get_editor_theme().get_color(&"accent_color", &"Editor")
		highlight.color = Color(accent, HIGHLIGHT_ALPHA)
	if not script_path.is_empty():
		queue_rebuild()


func _process(_delta: float) -> void:
	_update_highlight()


func poll_saved_file() -> void:
	if script_path.is_empty():
		return
	var fingerprint = _saved_fingerprint()
	if fingerprint != _fingerprint:
		_fingerprint = fingerprint
		queue_rebuild()


func queue_rebuild() -> void:
	if _stopped or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func clean_up() -> void:
	_stopped = true
	_clear_preview()


func _rebuild() -> void:
	_rebuild_queued = false
	if _stopped or not is_inside_tree():
		return
	_fingerprint = _saved_fingerprint()
	_clear_preview()
	if script_path.is_empty():
		return
	if not FileAccess.file_exists(script_path):
		_show_error("Script not found: %s" % script_path)
		return

	# A new node resets instance state; bypassing the cache also refreshes saved code.
	var script = ResourceLoader.load(script_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if script == null:
		_show_error("Could not load script. See Godot's debugger for details.")
		return
	var error = script.reload(true)
	if error != OK:
		_show_error("Could not compile script (%s). See Godot's debugger for details." % error_string(error))
		return
	if not ClassDB.is_parent_class(script.get_instance_base_type(), &"Control"):
		_show_error("Preview scripts must extend Control.")
		return
	for method in script.get_script_method_list():
		if method.name == &"_init" and method.args.size() > method.default_args.size():
			_show_error("Preview scripts need a constructor with no required arguments.")
			return

	# Explicit new() executes non-tool scripts too; can_instantiate() rejects them in the editor.
	var instance = script.new()
	if not is_instance_valid(instance) or not instance is Control:
		if is_instance_valid(instance) and instance is Node:
			instance.free()
		_show_error("Could not construct Control. See Godot's debugger for details.")
		return
	preview = instance
	if preview.name.is_empty():
		preview.name = script_path.get_file().get_basename()
	preview.set_meta(EDITOR_META, true)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status.hide()
	canvas.add_child(preview)
	node_tree.set_root_node(preview)


func _clear_preview() -> void:
	_release_inspected_node()
	_highlight_object(null)
	node_tree.clear_root()
	if is_instance_valid(preview):
		if preview.get_parent() != null:
			preview.get_parent().remove_child(preview)
		preview.free()
	preview = null


func set_tree_layout(tree_visible: bool, side: Side, width: int) -> void:
	_tree_width = maxi(width, TREE_MIN_WIDTH)
	set_tree_side(side)
	node_tree.visible = tree_visible


func set_tree_side(side: Side) -> void:
	_tree_side = SIDE_RIGHT if side == SIDE_RIGHT else SIDE_LEFT
	split.move_child(node_tree, 0 if _tree_side == SIDE_LEFT else 1)
	_apply_tree_width()


func _apply_tree_width() -> void:
	# In Godot 4.6 the split baseline is the edge beside the non-expanding child.
	split.split_offset = _tree_width * (1 if _tree_side == SIDE_LEFT else -1)


func _on_split_dragged(offset: int) -> void:
	_tree_width = maxi(TREE_MIN_WIDTH, offset * (1 if _tree_side == SIDE_LEFT else -1))
	tree_width_changed.emit(_tree_width)


func set_inspect_enabled(enabled: bool) -> void:
	_inspect_enabled = enabled
	if not enabled:
		_release_inspected_node()
	elif _selected != null and is_visible_in_tree():
		# Only the visible tab reclaims the inspector, so hidden tabs don't override it.
		_inspect_object(_selected.get_ref())


func _inspect_object(object: Object) -> void:
	_selected = weakref(object) if is_instance_valid(object) else null
	_release_inspected_node()
	if not _inspect_enabled or not Engine.is_editor_hint() or not is_instance_valid(object):
		return
	if object is Node:
		_inspected_node = weakref(object)
		object.tree_exiting.connect(_release_inspected_node)
	EditorInterface.inspect_object(object, "", true)


func _release_inspected_node() -> void:
	if _inspected_node == null:
		return
	var object = _inspected_node.get_ref() as Node
	_inspected_node = null
	if is_instance_valid(object):
		object.tree_exiting.disconnect(_release_inspected_node)
		if Engine.is_editor_hint() and EditorInterface.get_inspector().get_edited_object() == object:
			EditorInterface.inspect_object(null)


func set_highlight_enabled(enabled: bool) -> void:
	_highlight_enabled = enabled
	_update_highlight()


func _highlight_object(object: Object) -> void:
	_highlighted = weakref(object) if object is Control else null
	_update_highlight()


## Polled while a target is selected, so relayout, ancestor moves and tab switches are followed.
func _update_highlight() -> void:
	var target = _highlighted.get_ref() as Control if _highlighted != null else null
	var tracking = _highlight_enabled and is_instance_valid(target)
	set_process(tracking)
	highlight.visible = tracking and target.is_visible_in_tree()
	if not highlight.visible:
		return
	if highlight.get_index() != canvas.get_child_count() - 1:
		canvas.move_child(highlight, -1)
	var rect = target.get_global_rect()
	highlight.global_position = rect.position
	highlight.size = rect.size


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


func _show_error(message: String) -> void:
	status.text = message
	status.show()


func _saved_fingerprint() -> String:
	return FileAccess.get_sha256(script_path) if FileAccess.file_exists(script_path) else "missing"
