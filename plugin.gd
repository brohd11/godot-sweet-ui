@tool
extends EditorPlugin

const PreviewPanel = preload("res://addons/sweet_ui/src/editor/preview_panel.gd")

var _docks: DockManager.InstanceManager
var _panel: PreviewPanel


func _get_plugin_name() -> String:
	return "Sweet UI"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Control", &"EditorIcons")


func _enter_tree() -> void:
	_panel = PreviewPanel.new()
	_docks = DockManager.InstanceManager.new(self, false)
	var dock = _docks.new_persistent_dock_manager(_panel, DockManager.Slot.BOTTOM_PANEL)
	_panel.layout_changed.connect(dock.save_layout_data)


func _get_window_layout(_configuration: ConfigFile) -> void:
	if _docks != null:
		_docks.save_layout_data()


func _exit_tree() -> void:
	if is_instance_valid(_panel):
		_panel.clean_up()
	if _docks != null:
		_docks.clean_up()
	_docks = null
