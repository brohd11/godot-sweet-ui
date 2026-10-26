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

Sweets provides typed fluent wrappers:

```gdscript
var sweets = CodeUI.Sweets.new(self)
var rect := sweets.color_rect().expand().full_rect().color(Color.GREEN).node()
# rect is a ColorRect. Pass a parent to color_rect() to override the default.
```

`control()` and `color_rect()` create and attach one native node, then return a
RefCounted wrapper. With no explicit or default parent, the node stays unattached.
`create(Type, parent)` returns a native node; `ins(Type, parent)` returns a dynamic
wrapper for supported native types, or null for unsupported types.

Edit the prototypes and `TYPES` catalog in
`_export_ignore/generate/sweets_source.gd`, then run this in Editor Console:

```text
script SweetsGen call generate
```

The generator flattens prototype inheritance and specializes fluent return types.
All wrapper classes live in `src/class/sweets_generated.gd`. Sweets reexports them
and contains their typed factories inside its `### GENERATED START` /
`### GENERATED END` region. The generator validates both outputs before writing
and skips unchanged files. Keep manual helpers outside the marked region.
Generator and prototype files stay out of releases; commit both runtime files
and preserve their UIDs.

Prototypes contain operation methods over `_control`; constructors and typed
`node()` accessors are generated. Additional state, prototype constants, static
methods, and `super` calls are unsupported. Derived methods replace inherited ones.

Run the package's checks with `test code_ui` in Editor Console, or headlessly:

```sh
godot --headless --path . --script res://addons/code_ui/_export_ignore/test/run_headless.gd
```
