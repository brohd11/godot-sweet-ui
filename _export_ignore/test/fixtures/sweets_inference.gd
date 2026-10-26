extends RefCounted

const Sweets = preload("res://addons/code_ui/src/class/sweets.gd")

var parent := Control.new()
var inferred_rect := Sweets.new(parent).color_rect().expand().full_rect().color(Color.GREEN).node()
