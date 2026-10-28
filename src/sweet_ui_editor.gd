class_name SweetUIEditor
extends "res://addons/_lib/singleton/src/singleton_ref_count.gd" #! ext Singletons.RefCount
## Owns Sweet UI's docks and publishes the active preview tab, so a tree in a
## separate dock (SweetUITree) can follow whichever panel was used last.

const NodeRefs = preload("res://addons/_lib/editor_node_ref/src/editor_node_ref.gd")

const PreviewPanel = preload("res://addons/sweet_ui/src/editor/preview_panel.gd")
const PreviewHost = preload("res://addons/sweet_ui/src/editor/preview_host.gd")
const TreeDock = preload("res://addons/sweet_ui/src/editor/tree_dock.gd")


#region SingletonAPI

const PE_STRIP_CAST_SCRIPT = preload("res://addons/sweet_ui/src/sweet_ui_editor.gd")

static func get_singleton_name() -> String:
	return "SweetUIEditor"

static func get_instance() -> PE_STRIP_CAST_SCRIPT:
	return _get_instance(PE_STRIP_CAST_SCRIPT)

static func instance_valid() -> bool:
	return _instance_valid(PE_STRIP_CAST_SCRIPT)

static func register_node(node:Node):
	return _register_node(PE_STRIP_CAST_SCRIPT, node)

static func unregister_node(node:Node):
	_unregister_node(PE_STRIP_CAST_SCRIPT, node)

static func call_on_ready(callable, print_err:bool=true):
	_call_on_ready(PE_STRIP_CAST_SCRIPT, callable, print_err)

func _init(node):
	if not is_instance_valid(initial_plugin):
		initial_plugin = node

func _all_unregistered_callback():
	clean_up()

func _get_ready_bool() -> bool:
	return is_instance_valid(panel) and panel.is_node_ready()

#endregion


signal active_host_changed(host: PreviewHost)
signal tree_dock_changed(docked: bool)

var initial_plugin: EditorPlugin
var panel: PreviewPanel
var active_panel: PreviewPanel
var active_host: PreviewHost
var tree_dock: TreeDock

var _docks: DockManager.InstanceManager
var _stopped := false


func _ready() -> void:
	NodeRefs.call_on_ready(_create_docks)


func _create_docks() -> void:
	if _stopped or is_instance_valid(panel):
		return
	panel = PreviewPanel.new()
	# Freeable docks reload on startup, which is how an open tree dock persists.
	_docks = DockManager.InstanceManager.new(initial_plugin, true, true)
	var dock = _docks.new_persistent_dock_manager(panel, DockManager.Slot.BOTTOM_PANEL)
	dock.allow_scene_reload = true
	panel.layout_changed.connect(dock.save_layout_data)


# Emits even when unchanged, so listeners see a tab that loaded a new script.
func set_active(source: PreviewPanel, host: PreviewHost) -> void:
	active_panel = source
	active_host = host
	active_host_changed.emit(host)


func has_tree_dock() -> bool:
	return is_instance_valid(tree_dock)


func open_tree_dock() -> void:
	if _stopped or _docks == null or has_tree_dock():
		return
	var dock = _docks.new_freeable_dock_manager(TreeDock.new(), DockManager.Slot.DOCK_SLOT_LEFT_UR)
	if dock != null:
		dock.allow_scene_reload = true


func close_tree_dock() -> void:
	if has_tree_dock() and is_instance_valid(tree_dock.dock_manager):
		tree_dock.dock_manager.free_instance()


func register_tree_dock(dock: TreeDock) -> void:
	tree_dock = dock
	if not _stopped:
		tree_dock_changed.emit(true)


func unregister_tree_dock(dock: TreeDock) -> void:
	if tree_dock != dock:
		return
	tree_dock = null
	if not _stopped:
		tree_dock_changed.emit(false)


func save_layout_data() -> void:
	if _docks != null:
		_docks.save_layout_data()


func clean_up() -> void:
	_stopped = true
	if is_instance_valid(panel):
		panel.clean_up()
	if _docks != null:
		_docks.clean_up()
	_docks = null
