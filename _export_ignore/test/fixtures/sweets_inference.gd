extends RefCounted

const Sweets = preload("res://addons/code_ui/src/class/sweets/sweets.gd")

var parent := Control.new()
var inferred_rect := Sweets.new(parent).color_rect().expand().full_rect().color(Color.GREEN).node()
var inferred_button := Sweets.new(parent).button().expand().text("Go").disabled(true).pressed(func(): pass).node()
var inferred_label := Sweets.new(parent).label().text("Hello").horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER).node()
var inferred_grid := Sweets.new(parent).grid_container().expand().columns(3).node()
