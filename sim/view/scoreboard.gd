class_name Scoreboard
extends CanvasLayer
## The only thing on screen during a match: both alliances' scores either
## side of the match clock, in a strip along the bottom.

const _BLUE := Color(0.11, 0.33, 0.85)
const _RED := Color(0.84, 0.16, 0.18)
const _CLOCK := Color(0.07, 0.08, 0.1, 0.92)
const _ENDGAME := Color(0.96, 0.62, 0.12)
const _CORNER := 14

var game: Match

var _blue_score := Label.new()
var _red_score := Label.new()
var _clock := Label.new()
var _phase := Label.new()


func _ready() -> void:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 0)
	strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(strip)
	strip.add_child(_score_block("BLUE", _blue_score, _BLUE, true))

	var middle := PanelContainer.new()
	middle.custom_minimum_size = Vector2(210.0, 0.0)
	var middle_style := StyleBoxFlat.new()
	middle_style.bg_color = _CLOCK
	middle_style.set_content_margin_all(6)
	middle.add_theme_stylebox_override("panel", middle_style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", -6)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.add_child(stack)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.add_theme_font_size_override("font_size", 54)
	stack.add_child(_clock)
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase.add_theme_font_size_override("font_size", 15)
	_phase.modulate = Color(1.0, 1.0, 1.0, 0.7)
	stack.add_child(_phase)
	strip.add_child(middle)

	strip.add_child(_score_block("RED", _red_score, _RED, false))


func _process(_dt: float) -> void:
	if game == null:
		return
	_blue_score.text = str(game.scores["blue"])
	_red_score.text = str(game.scores["red"])
	var seconds := floori(game.time_left) if game.free_practice else ceili(game.time_left)
	_clock.text = "%d:%02d" % [seconds / 60, seconds % 60]
	_clock.add_theme_color_override("font_color", _ENDGAME if game.in_endgame() else Color.WHITE)
	if game.free_practice:
		_phase.text = "FREE PRACTICE"
	elif not game.running:
		_phase.text = "MATCH OVER"
	elif game.in_endgame():
		_phase.text = "ENDGAME"
	else:
		_phase.text = "TELEOP"


## An alliance's half of the strip: its name over its score, rounded on the
## outer end.
func _score_block(alliance: String, score: Label, color: Color, left: bool) -> PanelContainer:
	var block := PanelContainer.new()
	block.custom_minimum_size = Vector2(170.0, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_content_margin_all(6)
	if left:
		style.corner_radius_top_left = _CORNER
		style.corner_radius_bottom_left = _CORNER
	else:
		style.corner_radius_top_right = _CORNER
		style.corner_radius_bottom_right = _CORNER
	block.add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", -8)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	block.add_child(stack)
	var name_label := Label.new()
	name_label.text = alliance
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.modulate = Color(1.0, 1.0, 1.0, 0.8)
	stack.add_child(name_label)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_size_override("font_size", 54)
	stack.add_child(score)
	return block
