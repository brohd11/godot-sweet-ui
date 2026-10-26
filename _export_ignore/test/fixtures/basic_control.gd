extends VBoxContainer

const Context = preload("res://addons/code_ui/src/code_ui.gd")

var context_in_init := false
var context_in_enter := false
var context_in_ready := false
var child_context := false
var presses := 0


func _init() -> void:
	context_in_init = Context.is_editor(self)


func _enter_tree() -> void:
	context_in_enter = Context.is_editor(self)


func _ready() -> void:
	context_in_ready = Context.is_editor(self)
	var button = Button.new()
	button.text = "Code UI preview"
	button.pressed.connect(func(): presses += 1)
	add_child(button)
	child_context = Context.is_editor(button)
