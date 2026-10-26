extends RefCounted

const RE_EXPORT = false
const TYPES = {}


class SwControl extends RefCounted:
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
	func color(value: Color) -> SwColorRect:
		_control.color = value
		return self
