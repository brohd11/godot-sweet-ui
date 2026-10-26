extends RefCounted

const UI = preload("res://addons/sweet_ui/src/sweet_ui.gd")

var parent := Control.new()
var ui := UI.new(parent)
var inferred_rect := UI.new(parent).color_rect().expand().full_rect().color(Color.GREEN).node()
var inferred_button := UI.new(parent).button().expand().text("Go").disabled(true).pressed(func(): pass).node()
var inferred_label := UI.new(parent).label().text("Hello").horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER).node()
var inferred_grid := UI.new(parent).grid_container().expand().columns(3).node()
var inferred_ui := ui.label().ui()
var inferred_after_ui := ui.color_rect().ui().button().text("After ui()").node()
