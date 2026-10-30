# Sweet UI

Syntactic sugar for building UI with code in Godot. Also has a dock which will instance scripts and reload on save.

Godot 4.6+

The library is essentially a wrapper for each kind of control, allowing quickly setting common flags/variables.
It is generated via code, and can create multiple copies. This makes it easy add custom class wrappers or to have an Editor vs Runtime library. 
The plugin generates the class when the files are missing, or when explicitly ran.

```gdscript
extends Control

const Sw = SweetUI.Sweets

func _build_ui():
	# create the root wrapper
	var ui = SweetUI.new(self)
	# can check if UI is in the SweetUI dock. Runtime safe.
	var in_editor = SweetUI.is_editor(self)
	
	
	# a function named after a node creates the node and adds it as a child
	# to the UI's current node, then returns a wrapper that allows for chained calls
	ui.color_rect().full_rect().color(Color.BLACK).name("BG")
	
	# We want a reference to this node, so we can return it with node() or c() for short
	var marg = ui.margin_container().margin(20).full_rect().node()

	# passing a node through the constuctor adds it as a child to the passed node
	# chaining commands on newlines within parentheses allows for no backslash/line continuation
	var vbox = (ui.v_box_container(marg)
				.name("Content")
				.full_rect()
				.node())
	
	
	# rebase will set SweetUI's current node to the passed node. New nodes will be added there.
	(ui.rebase(ui.h_box_container(vbox).name("H").node()) # rebase to an hbox container added to the vbox
		.spacer() # rebase returns "ui", which has the spacer func
		.label().text("This is a title").ui() # create a label, set the text, then return to "ui"
		.spacer()
		.to_root()) # resets SweetUI's current node to the original passed in via new()
	
	ui.rebase(vbox)
	
	# custom types can be wrapped in a generic node that it extends from
	# you can also create your own via the generator
	var tab_container = (ui.v_box_container_from(MyTabBarContainer.new())
		.custom_minimum_size(Vector2(1000, 10))
		.expand()
		.node() as MyTabBarContainer)
	
	# the Sweets class (const Sw = SweetUI.Sweets) provides standalone wrappers
	# for where you don't want to add as a child right away
	tab_container.add_tab(
		Sw.color_rect()
		.color(Color.RED if in_editor else Color.BLUE)
		.node())
	tab_container.add_tab(Sw.color_rect().color(Color.GREEN).node())
	
```

## Install

This plugin uses external dependencies packaged with [Package Exporter](https://github.com/brohd11/godot-package-exporter.git),
download the latest package from releases, it includes the required dependencies.
The "require" key in plugin.cfg|addon.cfg lists all dependency repos.

You can also use [gdaddon](https://github.com/brohd11/gdaddon) to manage the installation.
It is a TUI package/repo manager that can install and update addons for you.

In your project:
```
gdaddon install brohd11/godot-sweet-ui/release
```

## Class Generation

Enable **Sweet UI** in Project Settings → Plugins to create the library files. Default location:

```text
res://scripts/sweet_ui/
    sweet_ui_source.gd
    generated/
        sweet_ui.gd
        sweets.gd
        sweets_generated.gd
```

This is generated inside of your project and out of the plugin so that it can be commited in your project. The library doesn't rely on the plugin's code at all.

`sweet_ui/generation/targets` in Project Settings maps output directories to an optional class name.
Default: `{"res://scripts/sweet_ui": "SweetUI"}`

Each one gets unique copies, allowing for different usecases between sets.
For example, a plugin that declares it's own custom controls:

```gdscript
# sweet_ui/generation/targets
{"res://scripts/sweet_ui": "SweetUI", "res://addons/my_plugin/src/ui": ""}

const PluginUI = preload("res://addons/my_plugin/src/ui/generated/sweet_ui.gd")
var ui = PluginUI.new(self)
```

An empty name generates an unnamed build that can be used by preloading it.

The generated `sweet_ui_source.gd` is the blueprint for the generator. Changes made there are reflected in the generated classes.

Generation is done by [Node Wrapper](https://github.com/brohd11/godot-node-wrapper), which can also generate wrappers for Nodes, Resources and RefCounted types in your own plugins.

## Current Types

- Control
- ColorRect
- Button
- Label
- LineEdit
- TextEdit
- TextureRect
- ProgressBar
- HBox
- VBox
- Grid
- Margin
- Panel
- Scroll
- Center
- HSplit
- VSplit


## Dock

The SweetUI dock loads scripts then instances them inside.

**Note:** The script is instanced fully, unintended logic can be run.
You can use `SweetUI.is_editor(self)` to check if you are in the editor or not.

There is a Tree that displays the node tree from the root down. It can show attached scripts, as well as highlight and inspect selected nodes.
The Tree can be relocated to a separate dock if desired.


## Custom Generation

If you edit the source, open `addons/sweet_ui/src/generator/sweet_ui_generator.gd` 
in the script editor and use **File → Run**. The `_SweetUIGenerator` EditorScript regenerates the
targets. You can also use [Editor Console](https://github.com/brohd11/godot-editor-console) to run it, optionally for a single target directory:

```text
script _SweetUIGenerator call generate
script _SweetUIGenerator call generate res://addons/my_plugin/src/ui
```

The generator discovers top-level `Sw…` classes: `SwColorRect` becomes the native
type `ColorRect` with factory func `color_rect()`. It flattens inherited functions,
so a class extending `SwColorRect`, doesn't need to implement ColorRect or Control functions,
they are generated into the class.

`TYPES` is an optional override dictionary; its
entries can supply `node`, `factory`, or both without changing the other default:

```gdscript
const TYPES = {
	"SwRect": {"node": "ColorRect"}, # Generates rect() and rect_from()
	"SwControl": {"factory": "control_node"},
}
```

All three runtime scripts are fully generated; do not edit them directly,
your changes will be lost on the next generation.

### Custom Example

Here is a custom class example.

Note the `#! set ...` comment. You can use this with properties and signals
to autogenerate a simple setter or signal connector func.
It can be spread across multiple lines. Inherited tags are included and duplicate names are removed. A handwritten method
with the same name takes precedence for both setters and signal connections.

Non-property or custom funcs can also be written here, like "select_first()" below.

All wrapper funcs return self, allowing for the chaining commands. This is not added automatically 
to custom functions, so be sure to remember that if you want to chain.

```gdscript
const MyTabContainer = preload("res://scripts/my_tab_container.gd")
const TYPES = {
	"SwMyTabContainer": {"node": MyTabContainer, "factory": "my_tab_container"},
}

class SwMyTabContainer extends SwControl:
	#! set current_tab, tab_changed
	#! set tab_hovered
	func select_first() -> SwMyTabContainer:
		_control.current_tab = 0
		return self
```

Script preload aliases at source-file scope are carried into generated
code, including relative preloads resolved from the source directory.

**Note:** Currently custom classes with constructor args are not supported.

