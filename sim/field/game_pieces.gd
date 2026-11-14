class_name GamePieces
extends Node3D
## The game pieces on the field. Starts from where the field CAD stages them:
## upright coral with an algae on top at the marks, algae on the reefs, and the
## coral shown racked in the coral stations, which mark where a human player
## feeds from.

# CAD coral racked in a station is tilted; staged coral stands upright.
const _UPRIGHT := 0.9
# Only the top row of each rack is used as a feed slot.
const _TOP_ROW := 0.78
# A fed coral appears this far in front of its rack slot, just inside the
# field, already moving: the slide down the chute itself is not simulated.
const _FEED_REACH := 0.6
const _FEED_SPEED := 1.2

var _staged: Array = []
var _feed_slots: Array = []


static func data_path(year: int) -> String:
	return "res://assets/fields/%d/game_pieces.json" % year


func _init(year: int) -> void:
	for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(data_path(year))):
		var axis: Array = entry["axis"]
		if entry["type"] == GamePiece.ALGAE or absf(axis[2]) > _UPRIGHT:
			_staged.append(entry)
		elif entry["position"][2] > _TOP_ROW:
			_feed_slots.append(entry)


func _ready() -> void:
	reset()


## Clears the field and puts the staged pieces back.
func reset() -> void:
	for piece in get_children():
		piece.queue_free()
	for entry: Dictionary in _staged:
		# Asleep until something touches them, so stacks stay as the CAD has them.
		_spawn(entry, Vector3.ZERO).sleeping = true


## A human player drops a coral into the coral station nearest `near`.
func feed_coral(near: Vector3) -> GamePiece:
	var nearest: Dictionary = _feed_slots[0]
	for slot: Dictionary in _feed_slots:
		if _position(slot).distance_to(near) < _position(nearest).distance_to(near):
			nearest = slot
	# Any slot of that station: they share its side of the field.
	var station := _feed_slots.filter(func(slot: Dictionary) -> bool:
		return _position(slot).distance_to(_position(nearest)) < 1.0)
	var slot: Dictionary = station.pick_random()
	# Racked coral points up and out of the field, so "into the field" is the
	# opposite of its axis along the floor.
	var axis: Array = slot["axis"]
	var inward := Frc.to_godot(Vector3(-axis[0], -axis[1], 0.0)).normalized()
	var coral := _spawn(slot, inward * _FEED_REACH + Vector3(0.0, 0.1, 0.0))
	coral.linear_velocity = inward * _FEED_SPEED
	return coral


func spawn(kind: String) -> GamePiece:
	var piece := GamePiece.create(kind)
	add_child(piece)
	return piece


func _spawn(entry: Dictionary, lift: Vector3) -> GamePiece:
	var axis: Array = entry["axis"]
	var direction := Frc.to_godot(Vector3(axis[0], axis[1], axis[2])).normalized()
	var piece := spawn(entry["type"])
	piece.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, direction)), _position(entry) + lift)
	return piece


func _position(entry: Dictionary) -> Vector3:
	var position_m: Array = entry["position"]
	return Frc.to_godot(Vector3(position_m[0], position_m[1], position_m[2]))
