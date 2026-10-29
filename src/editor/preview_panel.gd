extends VBoxContainer

const UName = preload("uid://b8sil7xrxxs20") #! resolve UtilR.Strings.UName
const Placer = preload("uid://cs6pl78crcr0g") #! resolve UtilR.Nodes.PopupMenus.Placer
const Options = preload("uid://dxdxq2n3imf4q") #! resolve UtilR.Nodes.PopupMenus.Options
const TabBarContainer = preload("uid://dhohyyr2xlven") #! resolve UIRuntime.Tabs.TabBarContainer
const SwUI = preload("uid://b7xssq2oulsuw") #! resolve SweetUI

const PreviewHost = preload("res://addons/sweet_ui/src/editor/preview_host.gd")
const TreeView = preload("res://addons/sweet_ui/src/editor/tree_view.gd")

const TREE_MIN_WIDTH = 140

signal layout_changed

var dock_button: Button
var popup_placer:Placer
var options_button:Button

var tabs: TabBarContainer
var add_button: Button
var tree_split: HSplitContainer
var tree_view: TreeView
var _hub: SweetUIEditor
var _tree_docked := false
var _tree_visible := true
var _tree_side: Side = SIDE_LEFT
var _tree_width := 200
var _highlight_selected := true
var _inspect_selected := true
var _interact_preview := false
var _poll_timer: Timer
var _restoring := false
var _stopped := false


func _init() -> void:
	custom_minimum_size = Vector2(260, 280)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	var ui = SwUI.new(self)
	
	popup_placer = ui.add_node(Placer.new())
	
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

	# The split sits under the tab bar so tabs keep the full dock width.
	tree_split = HSplitContainer.new()
	tree_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(tree_split)
	tree_view = TreeView.new()
	tree_view.custom_minimum_size.x = TREE_MIN_WIDTH
	tree_view.drop_target = self
	tree_split.add_child(tree_view)
	var content: Control = tabs.get_tab_parent()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.reparent(tree_split, false)
	tree_split.dragged.connect(_on_split_dragged)

	if SweetUIEditor.instance_valid():
		_hub = SweetUIEditor.get_instance()
		_hub.tree_dock_changed.connect(set_tree_docked)
		_tree_docked = _hub.has_tree_dock()
	_apply_tree_layout()

	ui.rebase(tabs.get_tab_bar_hbox())
	add_button = (ui.button().icon(ui.ed_icon(&"Add")).tooltip_text("New preview tab")
				.theme_type_variation("FlatButton").pressed(new_tab).c())
	
	options_button = ui.button().icon(ui.ed_icon(&"TripleBar")).pressed(_on_options_pressed).theme_type_variation("FlatButton").c()
	dock_button = ui.button().tooltip_text("Move or float").theme_type_variation("FlatButton").c()
	

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
	host.set_highlight_enabled(_highlight_selected)
	host.set_inspect_enabled(_inspect_selected)
	host.set_interact_enabled(_interact_preview)
	host.name = UName.incremental_name_check_in_nodes("New preview", tabs.get_tab_parent())
	host.set_drag_forwarding(Callable(), _can_drop_script, _drop_script.bind(host))
	host.overlay.set_drag_forwarding(Callable(), _can_drop_script, _drop_script.bind(host))
	tabs.add_tab(host)
	tabs.set_current_tab(tabs.get_tab_count() - 1)
	_notify_layout_changed()
	return host

func _on_options_pressed():
	var current_script_path = tabs.get_current_tab_control().script_path
	var options = Options.new()
	if not (tabs.get_tab_count() == 0 or current_script_path.is_empty()):
		options.add_option("Reload", _refresh_selected, ["Reload"])
		options.add_option("Edit Script", EditorInterface.edit_script.bind(load(current_script_path)), ["Script"])
	if not _tree_docked:
		options.add_option("Hide Tree" if _tree_visible else "Show Tree", set_tree_visible.bind(not _tree_visible), ["FileTree"])
	if is_instance_valid(_hub):
		options.add_radio_option("Tree in Separate Dock", _toggle_tree_dock, _tree_docked)
	options.add_radio_option("Highlight Selected", set_highlight_selected.bind(not _highlight_selected), _highlight_selected)
	options.add_radio_option("Inspect Selected", set_inspect_selected.bind(not _inspect_selected), _inspect_selected)
	options.add_radio_option("Interact with Preview", set_interact_preview.bind(not _interact_preview), _interact_preview)
	
	popup_placer.display_on_control(options, options_button)

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
	return {"scripts": paths, "selected_tab": tabs.get_tab_bar().current_tab,
		"tree_visible": _tree_visible, "tree_side": _tree_side, "tree_width": _tree_width,
		"highlight_selected": _highlight_selected, "inspect_selected": _inspect_selected,
		"interact_preview": _interact_preview}


func set_dock_data(data: Dictionary) -> void:
	_restoring = true
	_tree_visible = bool(data.get("tree_visible", true))
	_tree_side = SIDE_RIGHT if int(data.get("tree_side", SIDE_LEFT)) == SIDE_RIGHT else SIDE_LEFT
	_tree_width = maxi(int(data.get("tree_width", 200)), TREE_MIN_WIDTH)
	_highlight_selected = bool(data.get("highlight_selected", true))
	_inspect_selected = bool(data.get("inspect_selected", true))
	_interact_preview = bool(data.get("interact_preview", false))

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
	_apply_tree_layout()
	_restoring = false


func set_tree_visible(tree_visible:bool) -> void:
	_tree_visible = tree_visible
	_apply_tree_layout()


func set_highlight_selected(enabled: bool) -> void:
	_highlight_selected = enabled
	for i in tabs.get_tab_count():
		tabs.get_tab_control(i).set_highlight_enabled(enabled)
	_notify_layout_changed()


func set_inspect_selected(enabled: bool) -> void:
	_inspect_selected = enabled
	for i in tabs.get_tab_count():
		tabs.get_tab_control(i).set_inspect_enabled(enabled)
	_notify_layout_changed()


func set_interact_preview(enabled: bool) -> void:
	_interact_preview = enabled
	for i in tabs.get_tab_count():
		tabs.get_tab_control(i).set_interact_enabled(enabled)
	_notify_layout_changed()


## Placement control is available to callers; its toolbar UI can be added later.
func set_tree_side(side: Side) -> void:
	_tree_side = SIDE_RIGHT if side == SIDE_RIGHT else SIDE_LEFT
	_apply_tree_layout()


## Driven by the hub: while the tree has its own dock, the embedded one is hidden and unbound.
func set_tree_docked(docked: bool) -> void:
	_tree_docked = docked
	_apply_tree_layout()
	_sync_active_host()


func _toggle_tree_dock() -> void:
	if not is_instance_valid(_hub):
		return
	if _tree_docked:
		_hub.close_tree_dock()
	else:
		_hub.open_tree_dock()


func _on_split_dragged(offset: int) -> void:
	_tree_width = maxi(TREE_MIN_WIDTH, offset * (1 if _tree_side == SIDE_LEFT else -1))
	_apply_tree_layout()


func _apply_tree_layout() -> void:
	tree_view.visible = _tree_visible and not _tree_docked
	tree_split.move_child(tree_view, 0 if _tree_side == SIDE_LEFT else 1)
	# In Godot 4.6 the split baseline is the edge beside the non-expanding child.
	tree_split.split_offset = _tree_width * (1 if _tree_side == SIDE_LEFT else -1)
	_notify_layout_changed()


func get_current_host() -> PreviewHost:
	# The bar can lead its controls mid-close, so only trust an index both agree on.
	var index: int = tabs.get_tab_bar().current_tab
	if index < 0 or index >= tabs.get_tab_count() or index >= tabs.get_tab_parent().get_child_count():
		return null
	return tabs.get_tab_control(index)


func _sync_active_host() -> void:
	if _stopped:
		return
	var host = get_current_host()
	tree_view.set_host(null if _tree_docked else host)
	if is_instance_valid(_hub):
		_hub.set_active(self, host)


func clean_up() -> void:
	_stopped = true
	_poll_timer.stop()
	tree_view.set_host(null)
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
	_sync_active_host()
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
