@tool
extends EditorPlugin

const Generator = preload("res://addons/sweet_ui/src/generator/sweet_ui_generator.gd")


func _get_plugin_name() -> String:
	return "Sweet UI"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Control", &"EditorIcons")


func _enter_tree() -> void:
	Generator._report(Generator.setup())
	SweetUIEditor.register_node(self)


func _get_window_layout(_configuration: ConfigFile) -> void:
	if SweetUIEditor.instance_valid():
		SweetUIEditor.get_instance().save_layout_data()


func _exit_tree() -> void:
	SweetUIEditor.unregister_node(self)
