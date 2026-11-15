class_name GamePieces
extends Node3D
## The game pieces on the field. Starts from where the field CAD stages them:
## upright coral with an algae on top at the marks, algae on the reefs, and the
## coral shown racked in the coral stations, which mark where a human player
## feeds from. The human players can also feed on their own, keeping a few
## coral lying ready in front of their alliance's stations.

# CAD coral racked in a station is tilted; staged coral stands upright.
const _UPRIGHT := 0.9
# Only the top row of each rack is used as a feed slot.
const _TOP_ROW := 0.78
# A fed coral appears this far in front of its rack slot, just inside the
# field, already moving: the slide down the chute itself is not simulated.
const _FEED_REACH := 0.6
const _FEED_SPEED := 1.2
# Feed slots this close together belong to one coral station.
const _STATION_SPAN := 1.0
# How long a human player takes over each coral they feed unasked.
const _AUTO_FEED_PERIOD := 1.5

## How many coral may lie loose on the floor before the human players stop
## feeding unasked; 0 leaves feeding to feed_coral().
var auto_feed_limit := 0
## Whose coral stations feed unasked.
var feed_alliance := "blue"

var _staged: Array = []
# One array of feed slots per coral station.
var _stations: Array = []
var _since_feed := 0.0
# Station the last unasked coral went to, so equally bare stations take turns.
var _last_fed := -1


static func data_path(year: int) -> String:
	return "res://assets/fields/%d/game_pieces.json" % year


func _init(year: int) -> void:
	for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(data_path(year))):
		var axis: Array = entry["axis"]
		if entry["type"] == GamePiece.ALGAE or absf(axis[2]) > _UPRIGHT:
			_staged.append(entry)
		elif entry["position"][2] > _TOP_ROW:
			_station_of(entry).append(entry)


func _ready() -> void:
	reset()


## Clears the field and puts the staged pieces back.
func reset() -> void:
	_since_feed = 0.0
	for piece in get_children():
		piece.queue_free()
	for entry: Dictionary in _staged:
		# Asleep until something touches them, so stacks stay as the CAD has them.
		_spawn(entry, Vector3.ZERO).sleeping = true


func _physics_process(dt: float) -> void:
	if auto_feed_limit <= 0:
		return
	var loose := loose_coral()
	if loose.size() >= auto_feed_limit:
		_since_feed = 0.0
		return
	_since_feed += dt
	if _since_feed >= _AUTO_FEED_PERIOD:
		_since_feed = 0.0
		_last_fed = _barest_station(loose)
		if _last_fed >= 0:
			_feed_from(_stations[_last_fed])


## Coral lying on the field floor for anyone to pick up: not carried, not on a
## reef, and not still standing where it was staged.
func loose_coral() -> Array[GamePiece]:
	var loose: Array[GamePiece] = []
	for piece: GamePiece in get_children():
		if piece.kind != GamePiece.CORAL or piece.held or piece.on_reef or piece.is_queued_for_deletion():
			continue
		var at := Frc.from_godot(piece.global_position)
		var in_field := at.x > 0.0 and at.x < Frc.FIELD_LENGTH and at.y > 0.0 and at.y < Frc.FIELD_WIDTH
		if in_field and absf(piece.global_basis.y.y) < _UPRIGHT:
			loose.append(piece)
	return loose


## A human player drops a coral into the coral station nearest `near`.
func feed_coral(near: Vector3) -> GamePiece:
	var nearest: Array = _stations[0]
	for station: Array in _stations:
		if _position(station[0]).distance_to(near) < _position(nearest[0]).distance_to(near):
			nearest = station
	return _feed_from(nearest)


func spawn(kind: String) -> GamePiece:
	var piece := GamePiece.create(kind)
	add_child(piece)
	return piece


## The station `slot` belongs to, started if this is its first slot.
func _station_of(slot: Dictionary) -> Array:
	for station: Array in _stations:
		if _position(station[0]).distance_to(_position(slot)) < _STATION_SPAN:
			return station
	_stations.append([])
	return _stations.back()


## Index of the feeding alliance's station with the fewest of the `loose` coral
## lying nearer to it than to any other station, or -1 if it has no station.
func _barest_station(loose: Array[GamePiece]) -> int:
	var waiting := {}
	for coral in loose:
		var nearest := 0
		for i in _stations.size():
			if _position(_stations[i][0]).distance_to(coral.global_position) \
					< _position(_stations[nearest][0]).distance_to(coral.global_position):
				nearest = i
		waiting[nearest] = int(waiting.get(nearest, 0)) + 1
	var barest := -1
	# Starting just past the station fed last, so a tie goes to the other one.
	for turn in _stations.size():
		var i := (_last_fed + 1 + turn) % _stations.size()
		var blue: bool = float(_stations[i][0]["position"][0]) < 0.5 * Frc.FIELD_LENGTH
		if blue != (feed_alliance == "blue"):
			continue
		if barest < 0 or int(waiting.get(i, 0)) < int(waiting.get(barest, 0)):
			barest = i
	return barest


## Drops a coral in from any slot of `station`: they share its side of the field.
func _feed_from(station: Array) -> GamePiece:
	var slot: Dictionary = station.pick_random()
	# Racked coral points up and out of the field, so "into the field" is the
	# opposite of its axis along the floor.
	var axis: Array = slot["axis"]
	var inward := Frc.to_godot(Vector3(-axis[0], -axis[1], 0.0)).normalized()
	var coral := _spawn(slot, inward * _FEED_REACH + Vector3(0.0, 0.1, 0.0))
	coral.linear_velocity = inward * _FEED_SPEED
	return coral


func _spawn(entry: Dictionary, lift: Vector3) -> GamePiece:
	var axis: Array = entry["axis"]
	var direction := Frc.to_godot(Vector3(axis[0], axis[1], axis[2])).normalized()
	var piece := spawn(entry["type"])
	piece.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, direction)), _position(entry) + lift)
	return piece


func _position(entry: Dictionary) -> Vector3:
	var position_m: Array = entry["position"]
	return Frc.to_godot(Vector3(position_m[0], position_m[1], position_m[2]))
