extends VBoxContainer
## The Sweet UI node tree as its own dock, following the tab the hub marks active.
## Created on demand from the preview panel's options; restored by DockManager.

const TreeView = preload("res://addons/sweet_ui/src/editor/tree_view.gd")
const PreviewHost = preload("res://addons/sweet_ui/src/editor/preview_host.gd")

const DOCK_NAME = "SweetUITree"

var dock_button: Button
var dock_manager: DockManager
var tree_view: TreeView
var title: Label

var _hub: SweetUIEditor


func _init() -> void:
	custom_minimum_size = Vector2(160, 200)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header = HBoxContainer.new()
	add_child(header)
	title = Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(title)
	dock_button = Button.new()
	dock_button.tooltip_text = "Move or float"
	dock_button.theme_type_variation = &"FlatButton"
	header.add_child(dock_button)
	tree_view = TreeView.new()
	add_child(tree_view)


func get_dock_name() -> String:
	return DOCK_NAME


# Registered once rather than on enter/exit, since DockManager reparents us when moving docks.
func _ready() -> void:
	if not SweetUIEditor.instance_valid():
		return
	_hub = SweetUIEditor.get_instance()
	_hub.active_host_changed.connect(_on_active_host_changed)
	_hub.register_tree_dock(self)
	_on_active_host_changed(_hub.active_host)


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	# Parks collapse state on the host before the embedded tree takes it back.
	tree_view.set_host(null)
	if is_instance_valid(_hub):
		_hub.unregister_tree_dock(self)


func _on_active_host_changed(host: PreviewHost) -> void:
	tree_view.drop_target = _hub.active_panel
	tree_view.set_host(host)
	host = tree_view.get_host()
	title.text = "" if host == null else host.script_path.get_file()
	title.tooltip_text = "" if host == null else host.script_path
