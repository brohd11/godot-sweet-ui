extends RefCounted

const RE_EXPORT = false
const TYPES = {}


class SwControl extends RefCounted:
	#! set tooltip_text, custom_minimum_size, mouse_filter, visible
	var _control: Control

	func expand(v := true, h := true) -> SwControl:
		if v:
			_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if h:
			_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return self

	func full_rect() -> SwControl:
		_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return self


class SwColorRect extends SwControl:
	#! set color
	pass


class SwButton extends SwControl:
	#! set text, icon, disabled, toggle_mode, button_pressed
	pass


class SwLabel extends SwControl:
	#! set text, label_settings, horizontal_alignment, vertical_alignment, autowrap_mode
	pass


class SwLineEdit extends SwControl:
	#! set text, placeholder_text, editable, secret
	pass


class SwTextEdit extends SwControl:
	#! set text, placeholder_text, editable, wrap_mode
	pass


class SwTextureRect extends SwControl:
	#! set texture, expand_mode, stretch_mode
	pass


class SwProgressBar extends SwControl:
	#! set value, min_value, max_value, show_percentage
	pass


class SwHBoxContainer extends SwControl:
	#! set alignment
	pass


class SwVBoxContainer extends SwControl:
	#! set alignment
	pass


class SwGridContainer extends SwControl:
	#! set columns
	pass


class SwMarginContainer extends SwControl:
	func margin(val:int, left:=true, right:=true, top:=true, bottom:=true):
		if left:
			_control.add_theme_constant_override("margin_left", val)
		if right:
			_control.add_theme_constant_override("margin_right", val)
		if top:
			_control.add_theme_constant_override("margin_top", val)
		if bottom:
			_control.add_theme_constant_override("margin_bottom", val)
		return self
	pass


class SwPanelContainer extends SwControl:
	pass


class SwScrollContainer extends SwControl:
	#! set follow_focus, horizontal_scroll_mode, vertical_scroll_mode, scroll_horizontal, scroll_vertical
	pass


class SwCenterContainer extends SwControl:
	#! set use_top_left
	pass


class SwHSplitContainer extends SwControl:
	#! set split_offset, collapsed
	pass


class SwVSplitContainer extends SwControl:
	#! set split_offset, collapsed
	pass
