extends RefCounted

const UI = preload("res://scripts/sweet_ui/generated/sweet_ui.gd")
const Sweets = UI.Sweets

class CustomRect extends ColorRect:
	pass

var parent := Control.new()
var ui := UI.new(parent)
var inferred_rect := UI.new(parent).color_rect().expand().full_rect().color(Color.GREEN).node()
var inferred_button := UI.new(parent).button().expand().text("Go").disabled(true).pressed(func(): pass).node()
var inferred_label := UI.new(parent).label().text("Hello").horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER).node()
var inferred_grid := UI.new(parent).grid_container().expand().columns(3).node()
var inferred_ui := ui.label().ui()
var inferred_after_ui := ui.color_rect().ui().button().text("After ui()").node()
var inferred_static_rect := Sweets.color_rect().expand().full_rect().color(Color.GREEN).node()
var inferred_static_button := UI.Sweets.button().text("Static").pressed(func(): pass).node()
var static_label := Sweets.label()
var inferred_static_ui := static_label.ui()
var supplied_rect := CustomRect.new()
var inferred_from_node := ui.color_rect_from(supplied_rect).expand().color(Color.GREEN).node()
var inferred_from_c := ui.color_rect_from(ColorRect.new()).color(Color.BLUE).c()
var inferred_static_from_node := Sweets.color_rect(ColorRect.new()).expand().color(Color.RED).node()
var inferred_static_from_c := Sweets.color_rect(supplied_rect).expand().c()
