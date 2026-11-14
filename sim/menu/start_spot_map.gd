class_name StartSpotMap
extends Control
## Top-down sketch of the field for choosing where the robot starts: drag the
## robot to place it, turn it with the mouse wheel or the steer keys. Blue's
## wall is on the left.

signal changed

const _BACKGROUND := Color(0.1, 0.11, 0.13)
const _LINE := Color(1.0, 1.0, 1.0, 0.35)
const _BLUE := Color(0.11, 0.33, 0.85)
const _RED := Color(0.84, 0.16, 0.18)
const _WHEEL_STEP := deg_to_rad(15.0)
const _KEY_TURN_RATE := 2.5

## Starting pose in field coordinates.
var spot := Vector2.ZERO
var heading := 0.0
var alliance := "blue"
## Robot footprint including bumpers: length, width.
var footprint := Vector2(0.85, 0.8)
## Reef centres and their distance from centre to face, for the sketch.
var reefs: Array = []
var reef_face_distance := 0.0

var _dragging := false


func _ready() -> void:
	custom_minimum_size = Vector2(640.0, 640.0 * Frc.FIELD_WIDTH / Frc.FIELD_LENGTH)
	mouse_default_cursor_shape = Control.CURSOR_MOVE


func _process(dt: float) -> void:
	var turn := Input.get_axis("turn_right", "turn_left")
	if is_visible_in_tree() and turn != 0.0:
		heading = wrapf(heading + turn * _KEY_TURN_RATE * dt, -PI, PI)
		changed.emit()
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		if button.pressed:
			_move_to(button.position)
	elif button and button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_turn(_WHEEL_STEP)
	elif button and button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_turn(-_WHEEL_STEP)
	elif motion and _dragging:
		_move_to(motion.position)


func _draw() -> void:
	var scale_px := size.x / Frc.FIELD_LENGTH
	draw_rect(Rect2(Vector2.ZERO, size), _BACKGROUND)
	# Each alliance's half, tinted; the robot has to start in its own.
	draw_rect(Rect2(0.0, 0.0, 0.5 * size.x, size.y), Color(_BLUE, 0.12 if alliance == "blue" else 0.04))
	draw_rect(Rect2(0.5 * size.x, 0.0, 0.5 * size.x, size.y), Color(_RED, 0.12 if alliance == "red" else 0.04))
	draw_line(Vector2(0.5 * size.x, 0.0), Vector2(0.5 * size.x, size.y), _LINE, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), _LINE, false, 2.0)
	for i in reefs.size():
		var centre := _to_map(Vector2(reefs[i][0], reefs[i][1]))
		var corners := PackedVector2Array()
		for k in 7:
			# Corners sit between the faces, a little further out than them.
			var angle := PI / 6.0 + k * PI / 3.0
			corners.append(centre + Vector2(cos(angle), -sin(angle)) * reef_face_distance / cos(PI / 6.0) * scale_px)
		draw_polyline(corners, _BLUE if i == 0 else _RED, 2.0)

	var half := 0.5 * footprint * scale_px
	var colour := _BLUE if alliance == "blue" else _RED
	# Screen y runs down, so a field heading turns the other way on the map.
	draw_set_transform(_to_map(spot), -heading)
	draw_rect(Rect2(-half, 2.0 * half), colour)
	draw_rect(Rect2(-half, 2.0 * half), Color.WHITE, false, 2.0)
	draw_colored_polygon(
			PackedVector2Array([Vector2(half.x, 0.0), Vector2(0.2 * half.x, -0.6 * half.y), Vector2(0.2 * half.x, 0.6 * half.y)]),
			Color.WHITE)
	draw_set_transform(Vector2.ZERO)


func _to_map(field: Vector2) -> Vector2:
	return Vector2(field.x, Frc.FIELD_WIDTH - field.y) * size.x / Frc.FIELD_LENGTH


func _move_to(pixel: Vector2) -> void:
	var field := Vector2(pixel.x, size.y - pixel.y) * Frc.FIELD_LENGTH / size.x
	# Keep the whole robot inside the field and on its own alliance's side.
	var margin := 0.5 * footprint.length()
	var low := margin if alliance == "blue" else 0.5 * Frc.FIELD_LENGTH + margin
	var high := 0.5 * Frc.FIELD_LENGTH - margin if alliance == "blue" else Frc.FIELD_LENGTH - margin
	spot = Vector2(clampf(field.x, low, high), clampf(field.y, margin, Frc.FIELD_WIDTH - margin))
	changed.emit()
	queue_redraw()


func _turn(amount: float) -> void:
	heading = wrapf(heading + amount, -PI, PI)
	changed.emit()
	queue_redraw()
