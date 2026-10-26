extends VBoxContainer

const Context = preload("res://addons/code_ui/src/code_ui.gd")

var script_path: String
var preview: Control
var status: Label
var canvas: Control

var _fingerprint: String
var _rebuild_queued := false
var _stopped := false


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Drop a Control script onto this tab to preview it."
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	canvas = Control.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.clip_contents = true
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)


func _ready() -> void:
	if not script_path.is_empty():
		queue_rebuild()


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
	preview.set_meta(Context.EDITOR_META, true)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status.hide()
	canvas.add_child(preview)


func _clear_preview() -> void:
	if is_instance_valid(preview):
		if preview.get_parent() != null:
			preview.get_parent().remove_child(preview)
		preview.free()
	preview = null


func _show_error(message: String) -> void:
	status.text = message
	status.show()


func _saved_fingerprint() -> String:
	return FileAccess.get_sha256(script_path) if FileAccess.file_exists(script_path) else "missing"
