# Sweet UI

Syntactic sugar and live previews for Godot UI.

Sweet UI provides typed fluent wrappers:

```gdscript
var sweets = SweetUI.new(self)
var rect := sweets.color_rect().expand().full_rect().color(Color.GREEN).node()
# rect is a ColorRect. Pass a parent to color_rect() to override the default.

var column := sweets.v_box_container().expand().node()
sweets.label(column).text("Settings").horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
sweets.button(column).text("Apply").disabled(false).pressed(func(): print("Apply"))
```

`SweetUI.new(parent)` requires a parent node. `control()` and `color_rect()` create
and attach one native node, then return a RefCounted wrapper. Their optional parent
argument overrides the default parent. Wrapper constructors take an existing native
control, its parent, and the owning `SweetUI` instance:
`SwColorRect.new(control, parent, ui)`. They call
`parent.add_child(control)` directly. `wrapper.ui()` returns that same typed owner,
so chains can resume building controls: `ui.label().text("Title").ui().button()`.
Callers must supply valid parents; invalid parents surface normal Godot errors.

Alongside Control and ColorRect, Sweet UI includes Button, Label, LineEdit, TextEdit,
TextureRect, ProgressBar, and HBox, VBox, Grid, Margin, Panel, Scroll, Center, HSplit,
and VSplit containers. Factories follow native snake_case names, including
`h_box_container()`, `v_box_container()`, and `h_split_container()`.

Enable **Sweet UI** in Project Settings → Plugins. Press **+** in the tab-bar row
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
	if SweetUI.is_editor(self):
		return
	# Connect runtime services here.
```

`SweetUI.is_editor(node)` checks the node and its ancestors for preview metadata.
The marker is set before tree entry, so it is available in `_enter_tree()` and
`_ready()`, and to attached children. It is unavailable in `_init()` and always
returns false outside the editor. Constructors must work without arguments.

Previews are recreated from saved files; instance state is discarded. Only the
opened script is watched. Changes to dependencies may need Godot's normal script
reload before using Refresh. Scene files, required constructor arguments, and
unsaved script buffers are not supported. Runtime errors appear in Godot's debugger.

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

All wrapper classes live in `src/gen/sweets_generated.gd`.
`src/sweet_ui.gd` contains typed factories inside its
`### GENERATED START` / `### GENERATED END` region. By default, their return types
and constructors use `_Generated.SwColorRect` directly. Set `RE_EXPORT = true` in
the prototype source to also expose aliases such as `SweetUI.SwColorRect`.

The generator uses fixed output paths for the entry script and wrapper classes.
It validates both outputs before writing, creates missing output directories, and
skips unchanged files.
Keep manual helpers outside the marked region.
Generator and prototype files stay out of releases; commit both runtime files
and preserve their UIDs.

Use class-body tags for fluent property setters and signal connections:

```gdscript
class SwLabel extends SwControl:
	#! set text, horizontal_alignment, vertical_alignment
	pass
```

Each property produces a method such as `text(value: String) -> SwLabel` that
assigns the native property and returns the wrapper. Types come from Parser's
native API lookup, including resources and enums. Signal names instead produce a
connection method such as `pressed(callable: Callable) -> SwButton`, which calls
`_control.pressed.connect(callable)` and returns the wrapper.

Split longer lists across repeated tags; properties and signals can be mixed:

```gdscript
class SwButton extends SwControl:
	#! set text, icon, disabled
	#! set toggle_mode, button_pressed, pressed
	pass
```

Inherited tags are included and duplicate names are removed. A handwritten method
with the same name takes precedence for both setters and signal connections.

Only standalone class-body tags are read. Tag-like strings and comments inside
methods are ignored. Unknown members or non-writable properties reject generation before
either runtime file is changed.

Prototypes contain operation methods over `_control`; constructors and typed
`node()` / `ui()` accessors are generated. Additional state, prototype constants, static
methods, and `super` calls are unsupported. Derived methods replace inherited ones.

Run the package's checks with `test sweet_ui` in Editor Console, or headlessly:

```sh
godot --headless --path . --script res://addons/sweet_ui/_export_ignore/test/run_headless.gd
```
