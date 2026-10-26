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

var column := sweets.v_box_container().expand().node()
sweets.label(column).text("Settings").horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
sweets.button(column).text("Apply").disabled(false)
```

`Sweets.new(parent)` requires a parent node. `control()` and `color_rect()` create
and attach one native node, then return a RefCounted wrapper. Their optional parent
argument overrides the Sweets parent. Wrapper constructors require both an existing
native control and a parent, and call `parent.add_child(control)` directly.
Callers must supply valid parents; invalid parents surface normal Godot errors.

Alongside Control and ColorRect, Sweets includes Button, Label, LineEdit, TextEdit,
TextureRect, ProgressBar, and HBox, VBox, Grid, Margin, Panel, Scroll, Center, HSplit,
and VSplit containers. Factories follow native snake_case names, including
`h_box_container()`, `v_box_container()`, and `h_split_container()`.

Edit the prototypes in `_export_ignore/generate/sweets_source.gd`, then run this
in Editor Console:

```text
script SweetsGen call generate
```

The generator discovers top-level `Sw…` classes: `SwColorRect` becomes the native
type `ColorRect` and factory `color_rect()`. It flattens prototype inheritance and
specializes fluent return types. `TYPES` is an optional override dictionary; its
entries can supply `node`, `factory`, or both without changing the other default:

```gdscript
const RE_EXPORT = false
const TYPES = {
	"SwRect": {"node": "ColorRect"}, # Generates rect().
	"SwControl": {"factory": "control_node"},
}
```

All wrapper classes live in `src/class/sweets/sweets_generated.gd`.
Sweets contains typed factories inside its
`### GENERATED START` / `### GENERATED END` region. By default, their return types
and constructors use `_Generated.SwColorRect` directly. Set `RE_EXPORT = true` in
the prototype source to also expose aliases such as `CodeUI.Sweets.SwColorRect`.

The generator validates both outputs before writing and skips unchanged files.
Keep manual helpers outside the marked region.
Generator and prototype files stay out of releases; commit both runtime files
and preserve their UIDs.

Use class-body tags for simple fluent property setters:

```gdscript
class SwLabel extends SwControl:
	#! set text, horizontal_alignment, vertical_alignment
	pass
```

Each property produces a method such as `text(value: String) -> SwLabel` that
assigns the native property and returns the wrapper. Types come from Parser's
native API lookup, including resources and enums. Tags accept comma-separated
property names and can be repeated; inherited tags are included and duplicates
are removed. A handwritten method with the same name takes precedence.

Only standalone class-body tags are read. Tag-like strings and comments inside
methods are ignored. Unknown or non-writable properties reject generation before
either runtime file is changed.

Prototypes contain operation methods over `_control`; constructors and typed
`node()` accessors are generated. Additional state, prototype constants, static
methods, and `super` calls are unsupported. Derived methods replace inherited ones.

Run the package's checks with `test code_ui` in Editor Console, or headlessly:

```sh
godot --headless --path . --script res://addons/code_ui/_export_ignore/test/run_headless.gd
```
