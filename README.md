# Code UI

Enable **Code UI** in Project Settings → Plugins. Press **+** in the tab-bar row
to open an empty tab, then drop a `.gd` Control script onto its header or page.
Each script gets an interactive preview with the editor's theme. Saved changes
rebuild the preview within half a second; the **Reload** icon recreates it manually.
The dock menu in the same row can move or float the panel.

Scripts can use their normal lifecycle, including without `@tool`:

```gdscript
extends VBoxContainer

func _ready() -> void:
	var label = Label.new()
	label.text = "Hello from code"
	add_child(label)
	if CodeUI.is_editor(self):
		return
	# Connect runtime services here.
```

`CodeUI.is_editor(node)` checks the node and its ancestors for preview metadata.
The marker is set before tree entry, so it is available in `_enter_tree()` and
`_ready()`, and to attached children. It is unavailable in `_init()` and always
returns false outside the editor. Constructors must work without arguments.

Previews are recreated from saved files; instance state is discarded. Only the
opened script is watched. Changes to dependencies may need Godot's normal script
reload before using Refresh. Scene files, required constructor arguments, and
unsaved script buffers are not supported. Runtime errors appear in Godot's debugger.

Run the package's checks with `test code_ui` in Editor Console, or headlessly:

```sh
godot --headless --path . --script res://addons/code_ui/_export_ignore/test/run_headless.gd
```
