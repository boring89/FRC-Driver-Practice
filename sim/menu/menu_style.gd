class_name MenuStyle
extends RefCounted
## Look shared by the menu screens: colours and ready-styled controls.

const ACCENT := Color(0.96, 0.62, 0.12)
const PANEL := Color(0.07, 0.08, 0.1, 0.94)
const FIELD := Color(0.13, 0.15, 0.18)
const BUTTON := Color(0.2, 0.23, 0.27)
const BUTTON_HOVER := Color(0.29, 0.33, 0.38)


static func box(color: Color, radius := 6, padding := 7) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style


## Large flat text button for the title screen's menu list.
static func menu_item(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 40)
	button.add_theme_color_override("font_hover_color", ACCENT)
	button.add_theme_color_override("font_pressed_color", ACCENT)
	button.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	button.add_theme_constant_override("outline_size", 8)
	return button


## Solid button; `accent` marks the selected tab or a primary action.
static func button(text: String, font_size := 20, accent := false) -> Button:
	var control := Button.new()
	control.text = text
	control.focus_mode = Control.FOCUS_NONE
	control.add_theme_font_size_override("font_size", font_size)
	paint(control, accent)
	return control


static func paint(control: Button, accent: bool) -> void:
	control.add_theme_stylebox_override("normal", box(ACCENT if accent else BUTTON))
	control.add_theme_stylebox_override("hover", box(ACCENT.lightened(0.15) if accent else BUTTON_HOVER))
	control.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.15) if accent else BUTTON_HOVER))
	control.add_theme_color_override("font_color", Color.BLACK if accent else Color.WHITE)
	control.add_theme_color_override("font_hover_color", Color.BLACK if accent else Color.WHITE)


## Non-interactive name plate, as beside a binding.
static func plate(text: String, font_size := 18) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_stylebox_override("normal", box(FIELD))
	return label
