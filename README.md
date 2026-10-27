# Sweet UI

Syntactic sugar and live previews for Godot UI.

Enable **Sweet UI** in Project Settings → Plugins to create the project-owned files:

```text
scripts/sweet_ui/
    sweet_ui_source.gd
    generated/
        sweet_ui.gd
        sweets.gd
        sweets_generated.gd
```

Commit this directory, including its `.uid` files. `sweet_ui/generation/targets` in
Project Settings maps each output directory to the class name it declares, defaulting to
`{"res://scripts/sweet_ui": "SweetUI"}`. Each target has its own source, so a plugin can
generate a separate build that wraps its own controls without clashing with the project's
`SweetUI`:

```gdscript
# sweet_ui/generation/targets
{"res://scripts/sweet_ui": "SweetUI", "res://addons/my_plugin/src/ui": ""}

const PluginUI = preload("res://addons/my_plugin/src/ui/generated/sweet_ui.gd")
var ui = PluginUI.new(self)
```

An empty name generates an unnamed build that is used by preloading it. Class names must
be unique, and target directories cannot be nested inside one another. Move an existing
directory through Godot before changing its entry; generation rejects a class name that
already exists at another location. The former `sweet_ui/generation/directory` setting
migrates to a single `SweetUI` entry.

The source is a complete editable copy of the default prototypes. Enabling the plugin
creates it only when absent and generates runtime files on first setup or when an
output is missing. Existing source files are never overwritten by setup or addon updates.
Changes to source require explicit regeneration. Future default-prototype improvements
can be adopted manually from the addon's source template.

All runtime code lives under `generated/` and works without the Sweet UI addon. Game
export presets can exclude `addons/sweet_ui/*` and `scripts/sweet_ui/sweet_ui_source.gd`
(adjust the latter for a custom directory). Generated wrappers for custom controls
still need those controls and their dependencies. Sweet UI does not modify export presets.

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
argument overrides the default parent. Attached wrappers use
`SwColorRect.with_parent(control, parent, ui)` with an existing native control,
its parent, and the owning `SweetUI` instance. This calls
`parent.add_child(control)` directly. `wrapper.ui()` returns that same typed owner,
so chains can resume building controls: `ui.label().text("Title").ui().button()`.
Callers must supply valid parents; invalid parents surface normal Godot errors.

Every instance factory also has a typed `_from` companion for attaching an existing
node, including subclasses of the native type:

```gdscript
var rect := sweets.color_rect_from(MyColorRect.new()).expand().color(Color.GREEN).node()
var label := sweets.label_from(Label.new(), column).text("Existing node").c()
```

These helpers preserve the supplied instance and set the wrapper's `SweetUI` owner.
The optional parent overrides the current default parent. Supply a valid, unparented
node; these helpers call `add_child()` and do not automatically reparent.
`node()` and its shorthand `c()` infer the wrapper's native type (`ColorRect` above).
Accessing subclass-only members still requires a cast to the subclass.

Use `SweetUI.Sweets` to create controls before attaching them:

```gdscript
const Sweets = SweetUI.Sweets

var rect := Sweets.color_rect().expand().color(Color.GREEN).node()
add_child(rect)
```

Every generated instance factory has a static counterpart with an optional typed node:
`Sweets.color_rect(existing_rect)`. Omitting the argument or passing `null` creates a
new, unattached node. Supplying a node wraps that same instance without changing its
parent. Both APIs return the same typed wrappers and support the same fluent operations.
Static wrappers return `null` from `ui()`. Attaching a node later does not assign a
SweetUI owner to its wrapper.
Callers must attach or free detached nodes; releasing a wrapper does not free its node.

`SwColorRect.new(control)` wraps an existing control without changing its parent.
Direct three-argument constructor calls must migrate to
`SwColorRect.with_parent(control, parent, ui)`.

Alongside Control and ColorRect, Sweet UI includes Button, Label, LineEdit, TextEdit,
TextureRect, ProgressBar, and HBox, VBox, Grid, Margin, Panel, Scroll, Center, HSplit,
and VSplit containers. Factories follow native snake_case names, including
`h_box_container()`, `v_box_container()`, and `h_split_container()`.

Enable **Sweet UI** in Project Settings → Plugins. Press **+** in the tab-bar row
to open an empty tab, then drop a `.gd` Control script onto its header or page.
Each script gets an interactive preview with the editor's theme. Saved changes
rebuild the preview within half a second; the **Reload** icon recreates it manually.
The dock menu in the same row can move or float the panel.

The **Tree** toggle shows the live preview hierarchy on the left. Drag the divider
to resize it; visibility and width are shared across tabs and saved with the dock.
The tree follows children added, removed, renamed, or reparented by preview code.
Select a node to inspect its live instance, or use its script button to open the
attached script. Inspector edits affect only that instance and reset on reload.
A selected Control is tinted in the preview. **Highlight Selected** and **Inspect Selected**
in the options menu toggle the tint and the Inspector hand-off; both are shared across
tabs and saved with the dock.
The preview panel also exposes `set_tree_side(SIDE_LEFT)` / `set_tree_side(SIDE_RIGHT)`;
a placement button will be added later.

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

Edit the project's `sweet_ui_source.gd`, then open
`addons/sweet_ui/src/generator/sweet_ui_generator.gd` in the script editor and use
**File → Run**. The shipped `_SweetUIGenerator` EditorScript regenerates every configured
target. Editor Console can also invoke it, optionally for a single target directory:

```text
script _SweetUIGenerator call generate
script _SweetUIGenerator call generate res://addons/my_plugin/src/ui
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

Factory-name overrides also name the instance companion: `rectangle` generates
`rectangle()` and `rectangle_from()`. Names must be unique across both sets of helpers;
collisions reject generation before any output changes.

All three runtime scripts are fully generated; do not edit them directly.
`SweetUI.Sweets` exposes static factories, and both factory surfaces preload the same
wrapper classes. By default, return types use `_Generated.SwColorRect`. Set
`RE_EXPORT = true` in the project source to expose aliases such as
`SweetUI.SwColorRect` and `SweetUI.Sweets.SwColorRect`.

Generation validates the candidate before replacing outputs, skips unchanged files,
and preserves existing UIDs. The generator and parser dependencies stay in the addon;
the editable source and generated runtime files belong to the project.

Custom targets use a file-backed GDScript extending Control:

```gdscript
const MyTabContainer = preload("res://scripts/my_tab_container.gd")
const TYPES = {
	"SwMyTabContainer": {"node": MyTabContainer, "factory": "my_tab_container"},
}

class SwMyTabContainer extends SwControl:
	#! set current_tab, tab_changed
	func select_first() -> SwMyTabContainer:
		_control.current_tab = 0
		return self
```

Merge these definitions into the existing source. Custom targets can inherit script
properties and signals, use native properties and signals, and provide handwritten
operations. Script preload aliases at source-file scope are carried into generated
code, including relative preloads resolved from the source directory. Prototype
`_control` is deliberately untyped; the generated wrapper specializes it to the target.

`ui.my_tab_container_from(existing).expand().node()` and
`SweetUI.Sweets.my_tab_container().c()` infer the custom target type, so its members
remain accessible. Creating factories require a non-abstract target with no required
constructor arguments. Generation inspects scripts without constructing target nodes.
Inner-class and C# targets are not supported.

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
any runtime file is changed.

Prototypes contain operation methods over `_control`; constructors, `with_parent()`, and typed
`node()` / `c()` / `ui()` accessors are generated. Additional state, prototype constants, static
methods, and `super` calls are unsupported. Derived methods replace inherited ones.

The test entry point bootstraps missing runtime files before loading its checks.
Run the package's checks with `test sweet_ui` in Editor Console, or headlessly:

```sh
godot --headless --path . --script res://addons/sweet_ui/_export_ignore/test/run_headless.gd
```
