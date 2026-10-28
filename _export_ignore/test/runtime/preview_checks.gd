extends RefCounted

const Context = preload("res://scripts/sweet_ui/generated/sweet_ui.gd")
const PreviewPanel = preload("res://addons/sweet_ui/src/editor/preview_panel.gd")
const Host = preload("res://addons/sweet_ui/src/editor/preview_host.gd")
const TreeView = preload("res://addons/sweet_ui/src/editor/tree_view.gd")
const BASIC = "res://addons/sweet_ui/_export_ignore/test/runtime/fixtures/basic_control.gd"
const REQUIRED = "res://addons/sweet_ui/_export_ignore/test/runtime/fixtures/required_argument.gd"

static var _failures: Array[String]
static var _checks: int
static var _viewport: SubViewport


static func run_tests() -> Dictionary:
	_failures = []
	_checks = 0
	var tree = Engine.get_main_loop() as SceneTree
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(800, 600)
	_viewport.gui_disable_input = true
	tree.root.add_child(_viewport)
	_test_context()
	await _test_tabs_and_lifecycle()
	await _test_tree_layout()
	await _test_highlight()
	await _test_pick()
	await _test_saved_changes()
	_viewport.free()
	_viewport = null
	var output: Array = ["Sweet UI: %d checks, %d failures" % [_checks, _failures.size()]]
	output.append_array(_failures)
	return {"result": _failures.size(), "output": output, "completed": true}


static func _test_context() -> void:
	_check("null has no preview context", Context.is_editor(null) == false)
	var root = Control.new()
	var child = Control.new()
	root.add_child(child)
	_check("ordinary controls have no preview context", Context.is_editor(child) == false)
	root.set_meta(Context.EDITOR_META, true)
	_check("root marker follows editor hint", Context.is_editor(root) == Engine.is_editor_hint())
	_check("children inherit preview context", Context.is_editor(child) == Engine.is_editor_hint())
	child.set_meta(Context.EDITOR_META, false)
	_check("false child marker does not hide ancestor context", Context.is_editor(child) == Engine.is_editor_hint())
	root.free()


static func _test_tabs_and_lifecycle() -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var panel = PreviewPanel.new()
	_viewport.add_child(panel)
	_check("starts with an empty preview tab", panel.tabs.get_tab_count() == 1)
	var header = panel.tabs.get_tab_bar_hbox()
	_check("Add, Options and Dock share the tab-bar row", panel.add_button.get_parent() == header and panel.options_button.get_parent() == header and panel.dock_button.get_parent() == header)
	_check("valid file drop accepted", panel._can_drop_script(Vector2.ZERO, {"type": "files", "files": [BASIC]}))
	_check("multiple file drop rejected", not panel._can_drop_script(Vector2.ZERO, {"type": "files", "files": [BASIC, REQUIRED]}))
	_check("unrelated drag rejected", not panel._can_drop_script(Vector2.ZERO, {"type": "nodes", "nodes": []}))
	panel._drop_script(Vector2.ZERO, {"type": "files", "files": [BASIC]})
	await tree.process_frame
	var host = panel.tabs.get_current_tab_control()
	var node_tree = panel.tree_view.node_tree
	_check("file drop fills the empty tab", panel.tabs.get_tab_count() == 1)
	_check("non-tool preview instantiated", is_instance_valid(host.preview))
	if is_instance_valid(host.preview):
		var control = host.preview
		_check("tree binds the actual preview and ready children", node_tree.current_scene_instance == control and node_tree.tree_items.has(control.get_child(0)))
		_check("preview root has a readable script name", node_tree.get_root().get_text(0) == "basic_control")
		var activated_paths: Array[String] = []
		node_tree.path_activated.connect(func(path: String): activated_paths.append(path))
		node_tree._on_button_clicked(node_tree.tree_items[control], 0, node_tree.SCRIPT_BUTTON, MOUSE_BUTTON_LEFT)
		_check("script button activates the attached script", activated_paths == [BASIC])
		_check("fixture is non-tool", not control.get_script().is_tool())
		_check("constructor precedes marker", not control.context_in_init)
		_check("enter_tree sees marker", control.context_in_enter == Engine.is_editor_hint())
		_check("ready sees marker", control.context_in_ready == Engine.is_editor_hint())
		_check("ready children see marker", control.child_context == Engine.is_editor_hint())
		control.get_child(0).pressed.emit()
		_check("preview signals work", control.presses == 1)
		panel._refresh_selected()
		await tree.process_frame
		_check("Refresh frees old instance", not is_instance_valid(control))
		_check("Refresh resets instance state", is_instance_valid(host.preview) and host.preview.presses == 0)
		_check("Refresh binds only the new preview tree", node_tree.current_scene_instance == host.preview and node_tree.tree_items.size() == 2)
	panel.open_script(BASIC)
	_check("duplicate script selects existing tab", panel.tabs.get_tab_count() == 1 and panel.tabs.get_tab_bar().current_tab == 0)
	panel.add_button.pressed.emit()
	var empty_host = panel.tabs.get_current_tab_control()
	await tree.process_frame
	_check("Add opens a selected empty tab", panel.tabs.get_tab_count() == 2 and empty_host.script_path.is_empty())
	_check("empty preview stays idle", empty_host.preview == null and not empty_host.status.text.contains("not found"))
	panel._drop_script(Vector2.ZERO, {"type": "files", "files": [BASIC]}, empty_host)
	_check("duplicate drop selects original tab", panel.tabs.get_tab_bar().current_tab == 0 and empty_host.script_path.is_empty())
	panel.tabs.set_current_tab(1)
	var empty_state = panel.get_dock_data()
	panel.set_dock_data(empty_state)
	_check("empty tabs restore in place", panel.get_dock_data() == empty_state)
	await tree.process_frame
	var tab_position = panel.tabs.get_tab_bar().get_tab_rect(1).get_center()
	var drop_data = {"type": "files", "files": [REQUIRED]}
	_check("empty tab header accepts script drops", panel._can_drop_on_bar(tab_position, drop_data))
	panel._drop_on_bar(tab_position, drop_data)
	_check("header drop fills its own tab", panel.tabs.get_tab_control(1).script_path == REQUIRED)
	panel.open_script(REQUIRED)
	await tree.process_frame
	var required_host = panel.tabs.get_current_tab_control()
	_check("required constructor arguments show status", required_host.preview == null and required_host.status.visible)
	_check("failed preview leaves an empty tree", node_tree.current_scene_instance == null and node_tree.tree_items.is_empty())
	var state = panel.get_dock_data()
	_check("saved tab order", state.scripts == [BASIC, REQUIRED])
	panel.set_dock_data(state)
	await tree.process_frame
	_check("layout restores tabs and selection", panel.get_dock_data() == state)
	panel.tabs.get_tab_bar().move_tab(1, 0)
	panel.tabs.get_tab_bar().active_tab_rearranged.emit(0)
	_check("tab order follows rearrangement", panel.get_dock_data().scripts == [REQUIRED, BASIC])
	var parent = Control.new()
	_viewport.add_child(parent)
	panel.reparent(parent)
	await tree.process_frame
	_check("redocking keeps polling active", not panel._poll_timer.is_stopped())
	var pending = panel.tabs.get_tab_control(0)
	pending.queue_rebuild()
	panel.close_tab(0)
	await tree.process_frame
	_check("closing cancels pending rebuild", not is_instance_valid(pending))
	_check("closing keeps remaining tab metadata aligned", panel.tabs.get_tab_control(0).script_path == BASIC and panel.get_dock_data().scripts == [BASIC])
	var remaining = panel.tabs.get_tab_control(0)
	remaining.queue_rebuild()
	panel.clean_up()
	await tree.process_frame
	_check("cleanup stops polling and pending builds", panel._poll_timer.is_stopped() and remaining.preview == null)
	_check("cleanup releases tree roots and subscriptions", node_tree.current_scene_instance == null and node_tree._watched.is_empty())
	parent.free()
	var empty_panel = PreviewPanel.new()
	_viewport.add_child(empty_panel)
	empty_panel.close_tab(0)
	_check("closing last tab leaves a fresh empty tab", empty_panel.tabs.get_tab_count() == 1 and empty_panel.tabs.get_current_tab_control().script_path.is_empty())
	empty_panel.clean_up()
	empty_panel.free()


static func _test_tree_layout() -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var panel = PreviewPanel.new()
	panel.size = Vector2(800, 500)
	_viewport.add_child(panel)
	panel.open_script(BASIC)
	await tree.process_frame
	await tree.process_frame
	var view = panel.tree_view
	var split = panel.tree_split
	_check("tab bar keeps the full width above the tree split", panel.tabs.get_tab_bar_hbox().get_parent() == panel.tabs and panel.tabs.get_tab_parent().get_parent() == split)
	_check("tree starts visible on the left", view.visible and split.get_child(0) == view)
	_check("default tree width is applied (got %s, split %s, offset %s)" % [view.size, split.size, split.split_offset], is_equal_approx(view.size.x, 200.0))
	panel.set_tree_visible(false)
	_check("tree can be hidden", not view.visible)
	panel.set_tree_visible(true)
	panel.set_tree_side(SIDE_RIGHT)
	await tree.process_frame
	await tree.process_frame
	_check("side switching moves the tree", split.get_child(1) == view)
	_check("side switching retains tree width (got %s, split %s, offset %s)" % [view.size, split.size, split.split_offset], is_equal_approx(view.size.x, 200.0))
	split.dragged.emit(-240)
	await tree.process_frame
	await tree.process_frame
	_check("dragged width is saved", panel.get_dock_data().tree_width == 240)
	_check("right-side width matches layout (got %s, split %s, offset %s)" % [view.size, split.size, split.split_offset], is_equal_approx(view.size.x, 240.0))
	var saved = panel.get_dock_data()
	panel.set_dock_data(saved)
	await tree.process_frame
	await tree.process_frame
	_check("shared tree layout round trips", panel.get_dock_data() == saved)
	_check("restored layout reaches the split", split.get_child(1) == view and split.split_offset == -240)
	panel.set_dock_data({"scripts": [BASIC], "selected_tab": 0})
	await tree.process_frame
	await tree.process_frame
	_check("legacy dock data uses default tree layout", panel.get_dock_data().tree_visible and panel.get_dock_data().tree_side == SIDE_LEFT and panel.get_dock_data().tree_width == 200)
	var first = panel.tabs.get_current_tab_control()
	var child = Button.new()
	first.preview.add_child(child)
	await tree.process_frame
	await tree.process_frame
	_check("preview interaction can add live tree rows", view.node_tree.tree_items.has(child))
	view.node_tree.tree_items[first.preview].collapsed = true
	view.node_tree.set_selected(view.node_tree.tree_items[child], 0)
	_check("tree selection reaches the active tab", first._selected != null and first._selected.get_ref() == child)
	var second = panel.new_tab()
	_check("new tab repoints the shared tree", view.get_host() == second and view.node_tree.current_scene_instance == null)
	_check("repointing keeps the old tab's selection", first._selected != null and first._selected.get_ref() == child)
	panel.tabs.set_current_tab(0)
	_check("switching back restores collapse and selection", view.get_host() == first and view.node_tree.tree_items[first.preview].collapsed and view.node_tree.get_selected() == view.node_tree.tree_items[child])
	panel.set_tree_docked(true)
	_check("docking hides and unbinds the embedded tree", not view.visible and view.get_host() == null)
	var other = TreeView.new()
	_viewport.add_child(other)
	other.set_host(first)
	_check("another tree view picks up the parked state", other.node_tree.current_scene_instance == first.preview and other.node_tree.tree_items[first.preview].collapsed)
	other.set_host(null)
	other.free()
	panel.set_tree_docked(false)
	_check("undocking rebinds the embedded tree", view.visible and view.get_host() == first)
	panel.clean_up()
	panel.free()


static func _test_highlight() -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var panel = PreviewPanel.new()
	panel.size = Vector2(800, 500)
	_viewport.add_child(panel)
	panel.open_script(BASIC)
	await tree.process_frame
	await tree.process_frame
	var host = panel.tabs.get_current_tab_control()
	var child = Button.new()
	child.position = Vector2(30, 20)
	child.size = Vector2(90, 40)
	host.preview.add_child(child)
	await tree.process_frame
	await tree.process_frame
	_check("highlight starts hidden", not host.highlight.visible)
	panel.tree_view.node_tree.object_selected.emit(child)
	_check("selected control is highlighted on top", host.highlight.visible and host.highlight.get_global_rect().is_equal_approx(child.get_global_rect()) and host.highlight.get_index() > host.preview.get_index())
	_check("highlight stays out of the node tree", not panel.tree_view.node_tree.tree_items.has(host.highlight))
	child.size = Vector2(120, 60)
	await tree.process_frame
	_check("highlight follows control layout", host.highlight.get_global_rect().is_equal_approx(child.get_global_rect()))
	var timer = Timer.new()
	host.preview.add_child(timer)
	panel.tree_view.node_tree.object_selected.emit(timer)
	_check("non-Control selection clears highlight", not host.highlight.visible)
	panel.tree_view.node_tree.object_selected.emit(child)
	var second = panel.new_tab()
	await tree.process_frame
	_check("highlight hides with its tab", not host.highlight.visible)
	panel.tabs.set_current_tab(0)
	await tree.process_frame
	_check("highlight returns with its tab", host.highlight.visible)
	panel.set_highlight_selected(false)
	_check("disabling highlight hides it on every tab", not host.highlight.visible and not second._highlight_enabled)
	panel.set_highlight_selected(true)
	_check("re-enabling highlight restores the selection", host.highlight.visible)
	panel.tree_view.node_tree.object_selected.emit(null)
	_check("deselection clears highlight", not host.highlight.visible)
	panel.set_highlight_selected(false)
	var saved = panel.get_dock_data()
	panel.set_dock_data(saved)
	_check("highlight setting round trips", panel.get_dock_data() == saved and not panel.get_dock_data().highlight_selected and not panel.tabs.get_tab_control(0)._highlight_enabled)
	panel.set_dock_data({"scripts": [BASIC], "selected_tab": 0})
	_check("legacy dock data enables highlight", panel.get_dock_data().highlight_selected)
	_check("inspect starts enabled", panel.get_dock_data().inspect_selected and panel.tabs.get_tab_control(0)._inspect_enabled)
	await tree.process_frame
	await tree.process_frame
	host = panel.tabs.get_tab_control(0)
	panel.tree_view.node_tree.object_selected.emit(host.preview)
	_check("selection is remembered for inspection", host._selected != null and host._selected.get_ref() == host.preview)
	second = panel.new_tab()
	panel.set_inspect_selected(false)
	_check("disabling inspect reaches every tab", not host._inspect_enabled and not second._inspect_enabled)
	saved = panel.get_dock_data()
	panel.set_dock_data(saved)
	_check("inspect setting round trips", panel.get_dock_data() == saved and not panel.get_dock_data().inspect_selected and not panel.tabs.get_tab_control(0)._inspect_enabled)
	panel.set_dock_data({"scripts": [BASIC], "selected_tab": 0})
	_check("legacy dock data enables inspect", panel.get_dock_data().inspect_selected)
	panel.clean_up()
	panel.free()


static func _test_pick() -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var panel = PreviewPanel.new()
	panel.size = Vector2(800, 500)
	_viewport.add_child(panel)
	panel.open_script(BASIC)
	await tree.process_frame
	await tree.process_frame
	var host = panel.tabs.get_current_tab_control()
	var overlay = host.overlay
	var node_tree = panel.tree_view.node_tree
	var button: Button = host.preview.get_child(0)
	_check("overlay sits on top of the canvas and stops mouse input", overlay.get_index() == host.canvas.get_child_count() - 1 and overlay.mouse_filter == Control.MOUSE_FILTER_STOP and overlay.visible)
	_check("overlay covers the preview", overlay.get_global_rect().is_equal_approx(host.preview.get_global_rect()))
	node_tree.tree_items[host.preview].collapsed = true
	_click_control(overlay, button, MOUSE_BUTTON_LEFT)
	_check("left click reveals and selects the control's row", node_tree.get_selected() == node_tree.tree_items[button] and not node_tree.tree_items[host.preview].collapsed)
	_check("left click selects and highlights the control", host._selected != null and host._selected.get_ref() == button and host.highlight.visible)
	_check("picking does not press preview controls", host.preview.presses == 0)
	_click(overlay, overlay.size - Vector2(5, 5), MOUSE_BUTTON_LEFT)
	_check("empty space picks the preview root", node_tree.get_selected() == node_tree.tree_items[host.preview] and host._selected.get_ref() == host.preview)
	var requests: Array = []
	host.context_requested.connect(func(control: Control, _position: Vector2): requests.append(control))
	_click_control(overlay, button, MOUSE_BUTTON_RIGHT)
	_check("right click requests a menu for the control", requests == [button])
	_check("right click keeps the selection", node_tree.get_selected() == node_tree.tree_items[host.preview])
	host.select_object(null)
	_click(overlay, overlay.size - Vector2(5, 5), MOUSE_BUTTON_LEFT)
	_check("picking the selected row reselects it on the host", host._selected != null and host._selected.get_ref() == host.preview)
	panel.set_interact_preview(true)
	_check("interact mode hides the overlay", not overlay.visible)
	var saved = panel.get_dock_data()
	panel.set_dock_data(saved)
	_check("interact setting round trips", panel.get_dock_data() == saved and not panel.tabs.get_tab_control(0).overlay.visible)
	panel.set_dock_data({"scripts": [BASIC], "selected_tab": 0})
	_check("legacy dock data picks by default", not panel.get_dock_data().interact_preview and panel.tabs.get_tab_control(0).overlay.visible)
	panel.clean_up()
	panel.free()


static func _click_control(overlay: Control, target: Control, button_index: MouseButton) -> void:
	_click(overlay, overlay.get_global_transform().affine_inverse() * target.get_global_rect().get_center(), button_index)


static func _click(overlay: Control, position: Vector2, button_index: MouseButton) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	event.position = position
	overlay._gui_input(event)


static func _test_saved_changes() -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var temp_dir = OS.get_environment("TMPDIR")
	if temp_dir.is_empty():
		temp_dir = "/tmp"
	var path = temp_dir.path_join("sweet_ui_preview_%d.gd" % Time.get_ticks_usec())
	var host = Host.new()
	host.script_path = path
	_write(path, "extends Label\nfunc _ready():\n\ttext = \"before\"\n")
	_viewport.add_child(host)
	var view = TreeView.new()
	_viewport.add_child(view)
	view.set_host(host)
	await tree.process_frame
	_check("saved source builds", is_instance_valid(host.preview) and host.preview.text == "before")
	var before = host.preview
	host.poll_saved_file()
	await tree.process_frame
	_check("unchanged files keep the same instance", host.preview == before)
	_write(path, "extends Label\nfunc _ready():\n\ttext = \"after\"\n")
	host.poll_saved_file()
	await tree.process_frame
	_check("saved change refreshes compiled code", is_instance_valid(host.preview) and host.preview.text == "after")
	_check("saved change frees old node", not is_instance_valid(before))
	_write(path, "extends RefCounted\n")
	host.poll_saved_file()
	await tree.process_frame
	_check("non-Control scripts show status", host.preview == null and host.status.visible)
	_check("invalid saved script clears the tree", view.node_tree.tree_items.is_empty() and view.node_tree.current_scene_instance == null)
	_write(path, "extends Label\nfunc _ready():\n\ttext = \"recovered\"\n")
	host.poll_saved_file()
	await tree.process_frame
	_check("corrected script recovers", is_instance_valid(host.preview) and host.preview.text == "recovered")
	_check("corrected script repopulates the tree", view.node_tree.current_scene_instance == host.preview and view.node_tree.tree_items.has(host.preview))
	DirAccess.remove_absolute(path)
	host.poll_saved_file()
	await tree.process_frame
	_check("deleted scripts show status", host.preview == null and host.status.visible)
	_write(path, "extends Control\n")
	host.poll_saved_file()
	await tree.process_frame
	_check("recreated scripts recover", is_instance_valid(host.preview) and not host.status.visible)
	host.clean_up()
	view.free()
	host.free()
	DirAccess.remove_absolute(path)


static func _write(path: String, source: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("temporary fixture write", false)
		return
	file.store_string(source)
	file.close()


static func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures.append("FAIL " + label)
