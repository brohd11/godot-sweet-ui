extends VBoxContainer

const TabBarContainer = preload("uid://dhohyyr2xlven") #! resolve UIRuntime.Tabs.TabBarContainer
const PreviewHost = preload("res://addons/sweet_ui/src/editor/preview_host.gd")

signal layout_changed

var dock_button: Button
var tabs: TabBarContainer
var add_button: Button
var refresh_button: Button
var _poll_timer: Timer
var _restoring := false
var _stopped := false


func _init() -> void:
	custom_minimum_size = Vector2(260, 280)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock_button = Button.new()
	dock_button.tooltip_text = "Move or float Sweet UI"
	dock_button.theme_type_variation = &"FlatButton"


func _ready() -> void:
	tabs = TabBarContainer.new()
	add_child(tabs)
	var bar = tabs.get_tab_bar()
	bar.drag_to_rearrange_enabled = true
	bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	bar.close_with_middle_mouse = true
	bar.tab_close_pressed.connect(close_tab)
	bar.active_tab_rearranged.connect(_on_tab_rearranged)
	bar.set_drag_forwarding(Callable(), _can_drop_on_bar, _drop_on_bar)
	tabs.tab_changed.connect(_on_tab_changed)

	var header = tabs.get_tab_bar_hbox()
	add_button = Button.new()
	add_button.text = "+"
	add_button.tooltip_text = "New preview tab"
	add_button.theme_type_variation = &"FlatButton"
	add_button.pressed.connect(new_tab)
	header.add_child(add_button)
	refresh_button = Button.new()
	refresh_button.text = "Reload"
	refresh_button.tooltip_text = "Recreate the selected preview from its saved script."
	refresh_button.theme_type_variation = &"FlatButton"
	refresh_button.pressed.connect(_refresh_selected)
	header.add_child(refresh_button)
	header.add_child(dock_button)
	if Engine.is_editor_hint():
		var editor_theme = EditorInterface.get_editor_theme()
		add_button.text = ""
		add_button.icon = editor_theme.get_icon(&"Add", &"EditorIcons")
		refresh_button.text = ""
		refresh_button.icon = editor_theme.get_icon(&"Reload", &"EditorIcons")

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.5
	_poll_timer.timeout.connect(_poll_saved_files)
	add_child(_poll_timer)
	_poll_timer.start()
	new_tab()


func new_tab() -> PreviewHost:
	if _stopped:
		return null
	var host = PreviewHost.new()
	host.name = "New preview"
	host.set_drag_forwarding(Callable(), _can_drop_script, _drop_script.bind(host))
	tabs.add_tab(host)
	tabs.set_current_tab(tabs.get_tab_count() - 1)
	_notify_layout_changed()
	return host


func open_script(path: String, tab_index := -1) -> void:
	if _stopped:
		return
	path = ProjectSettings.localize_path(path).simplify_path()
	if not path.begins_with("res://") or path.get_extension().to_lower() != "gd":
		return
	for i in tabs.get_tab_count():
		if tabs.get_tab_control(i).script_path == path:
			tabs.set_current_tab(i)
			return
	var host: PreviewHost
	if tab_index >= 0 and tab_index < tabs.get_tab_count():
		host = tabs.get_tab_control(tab_index)
	elif tabs.get_tab_count() > 0 and tabs.get_current_tab_control().script_path.is_empty():
		host = tabs.get_current_tab_control()
	else:
		host = new_tab()
	host.script_path = path
	var index = host.get_index()
	tabs.get_tab_bar().set_tab_title(index, path.get_file())
	tabs.get_tab_bar().set_tab_tooltip(index, path)
	tabs.set_current_tab(index)
	host.queue_rebuild()
	_notify_layout_changed()


func close_tab(index: int) -> void:
	if index < 0 or index >= tabs.get_tab_count():
		return
	var host = tabs.get_tab_control(index)
	host.clean_up()
	# Remove the bar entry while its control still exists, then resync selection after detaching it.
	tabs.remove_tab(index, false)
	tabs.get_tab_parent().remove_child(host)
	host.queue_free()
	if tabs.get_tab_count() > 0:
		tabs.set_current_tab(tabs.get_tab_bar().current_tab)
	elif not _restoring:
		new_tab()
	_notify_layout_changed()


func get_dock_data() -> Dictionary:
	var paths: Array[String] = []
	for i in tabs.get_tab_count():
		paths.append(tabs.get_tab_control(i).script_path)
	return {"scripts": paths, "selected_tab": tabs.get_tab_bar().current_tab}


func set_dock_data(data: Dictionary) -> void:
	_restoring = true
	for i in range(tabs.get_tab_count() - 1, -1, -1):
		close_tab(i)
	for path in data.get("scripts", []):
		if path is not String:
			continue
		var host = new_tab()
		if not path.is_empty():
			open_script(path, host.get_index())
	if tabs.get_tab_count() == 0:
		new_tab()
	tabs.set_current_tab(clampi(int(data.get("selected_tab", 0)), 0, tabs.get_tab_count() - 1))
	_restoring = false


func clean_up() -> void:
	_stopped = true
	_poll_timer.stop()
	for i in tabs.get_tab_count():
		tabs.get_tab_control(i).clean_up()


func _poll_saved_files() -> void:
	if _stopped:
		return
	for i in tabs.get_tab_count():
		tabs.get_tab_control(i).poll_saved_file()


func _refresh_selected() -> void:
	if tabs.get_tab_count() > 0:
		var host = tabs.get_current_tab_control()
		if not host.script_path.is_empty():
			host.queue_rebuild()


func _on_tab_changed(_index: int) -> void:
	refresh_button.disabled = tabs.get_tab_count() == 0 or tabs.get_current_tab_control().script_path.is_empty()
	_notify_layout_changed()


func _on_tab_rearranged(_index: int) -> void:
	_notify_layout_changed()


func _notify_layout_changed() -> void:
	if not _restoring and not _stopped:
		layout_changed.emit()


func _script_from_drop(data: Variant) -> String:
	if data is not Dictionary:
		return ""
	var files = data.get("files", [])
	if files is not Array and files is not PackedStringArray:
		return ""
	if data.get("type") != "files" or files.size() != 1 or not files[0] is String:
		return ""
	var path: String = files[0]
	return path if path.get_extension().to_lower() == "gd" and FileAccess.file_exists(path) else ""


func _can_drop_script(_position: Vector2, data: Variant) -> bool:
	return not _script_from_drop(data).is_empty()


func _drop_script(_position: Vector2, data: Variant, host: PreviewHost = null) -> void:
	var path = _script_from_drop(data)
	if not path.is_empty():
		open_script(path, host.get_index() if is_instance_valid(host) else -1)


func _can_drop_on_bar(position: Vector2, data: Variant) -> bool:
	return tabs.get_tab_bar().get_tab_idx_at_point(position) >= 0 and _can_drop_script(position, data)


func _drop_on_bar(position: Vector2, data: Variant) -> void:
	if _can_drop_on_bar(position, data):
		open_script(_script_from_drop(data), tabs.get_tab_bar().get_tab_idx_at_point(position))
