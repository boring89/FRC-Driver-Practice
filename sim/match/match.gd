class_name Match
extends Node
## One practice match: the countdown, and each alliance's score read off the
## state of the field the way referees assess it, so a coral knocked back off
## a branch stops counting.
##
## Scored: coral hanging on a reef branch (one per branch) or lying in a
## reef's trough, algae resting in the net, and algae pushed out through a
## processor. The field config's "match" block gives the points and where
## each of those is.

const _EVALUATE_PERIOD := 0.1
# A piece still moving faster than this has not been scored yet.
const _REST_SPEED := 0.25
# An algae lying in the net never quite stops rocking on its mesh.
const _NET_REST_SPEED := 1.0
# How close a coral's centre must be to where one hangs on a branch.
const _BRANCH_REACH := 0.09

## Seconds left on the clock, or seconds played so far in free practice.
var time_left := 0.0
var running := false
## No clock to run out: the match keeps score until it is restarted.
var free_practice := false
var scores := {"blue": 0, "red": 0}

var _cfg: Dictionary
var _pieces: GamePieces
var _reefs: Array[Vector2] = []
# Where a coral rests on each branch: {"at": field position, "points", "alliance"}.
var _branches: Array[Dictionary] = []
# Algae each alliance has put through its processor.
var _processed := {"blue": 0, "red": 0}
var _since_evaluation := 0.0


func _init(field: Dictionary, pieces: GamePieces) -> void:
	_cfg = field["match"]
	_pieces = pieces
	var reefs: Dictionary = field["reefs"]
	var alliances: Array = _cfg["reef_alliances"]
	var rests: Dictionary = _cfg["branch_rest_m"]
	for i in reefs["centers_m"].size():
		var centre := Vector2(reefs["centers_m"][i][0], reefs["centers_m"][i][1])
		_reefs.append(centre)
		for face in 6:
			var outward := Vector2.from_angle(face * PI / 3.0)
			var along := Vector2.from_angle(face * PI / 3.0 + PI / 2.0)
			for side: float in [-1.0, 1.0]:
				for level: String in rests:
					var inset: float = rests[level][0]
					var spot := centre + outward * (float(reefs["face_distance_m"]) - inset) \
							+ along * float(reefs["branch_offset_m"]) * side
					_branches.append({
						"at": Vector3(spot.x, spot.y, rests[level][1]),
						"points": _cfg["coral_points"][level],
						"alliance": alliances[i],
					})


## Starts a match of `seconds`, or an open-ended one counting up from zero.
func start(seconds: float, open_ended := false) -> void:
	free_practice = open_ended
	time_left = 0.0 if open_ended else seconds
	running = true
	_processed = {"blue": 0, "red": 0}
	scores = {"blue": 0, "red": 0}


func in_endgame() -> bool:
	return running and not free_practice and time_left <= float(_cfg["endgame_seconds"])


func _physics_process(dt: float) -> void:
	if not running:
		return
	time_left = time_left + dt if free_practice else maxf(0.0, time_left - dt)
	var over := not free_practice and time_left == 0.0
	_since_evaluation += dt
	if _since_evaluation >= _EVALUATE_PERIOD or over:
		_since_evaluation = 0.0
		evaluate()
	if over:
		running = false


## Recounts both scores from where the game pieces are right now.
func evaluate() -> void:
	var totals := {}
	for alliance: String in _processed:
		totals[alliance] = int(_processed[alliance]) * int(_cfg["processor"]["points"])
	var occupied := {}
	for piece: GamePiece in _pieces.get_children():
		if piece.held or piece.is_queued_for_deletion():
			piece.on_reef = false
			continue
		var at := Frc.from_godot(piece.global_position)
		var resting := piece.linear_velocity.length() < _REST_SPEED
		if piece.kind == GamePiece.CORAL:
			piece.on_reef = _count_coral(at, resting, totals, occupied)
		elif piece.kind == GamePiece.ALGAE:
			_count_algae(piece, at, totals)
	scores = totals


## Adds what a coral at `at` is worth, once it has come to rest, and returns
## whether it is on a reef at all.
func _count_coral(at: Vector3, resting: bool, totals: Dictionary, occupied: Dictionary) -> bool:
	for i in _branches.size():
		var branch := _branches[i]
		if at.distance_to(branch["at"]) < _BRANCH_REACH:
			# Only one coral counts per branch.
			if resting and not occupied.has(i):
				occupied[i] = true
				totals[branch["alliance"]] += int(branch["points"])
			return true
	var trough: Dictionary = _cfg["trough"]
	for i in _reefs.size():
		if Vector2(at.x, at.y).distance_to(_reefs[i]) < float(trough["radius_m"]) \
				and at.z > float(trough["heights_m"][0]) and at.z < float(trough["heights_m"][1]):
			if resting:
				totals[_cfg["reef_alliances"][i]] += int(_cfg["coral_points"]["l1"])
			return true
	return false


func _count_algae(piece: GamePiece, at: Vector3, totals: Dictionary) -> void:
	var net: Dictionary = _cfg["net"]
	if piece.linear_velocity.length() < _NET_REST_SPEED and absf(at.x - 0.5 * Frc.FIELD_LENGTH) < float(net["half_depth_m"]) \
			and at.z > float(net["min_height_m"]):
		# Each alliance's net is taken to be the half above its own cages.
		totals["blue" if at.y > 0.5 * Frc.FIELD_WIDTH else "red"] += int(net["points"])
		return
	var processor: Dictionary = _cfg["processor"]
	for alliance: String in processor["at_m"]:
		var mouth: Array = processor["at_m"][alliance]
		# Through the wall at the processor: out of the field on that side.
		var outside := at.y < 0.0 if float(mouth[1]) < 0.5 * Frc.FIELD_WIDTH else at.y > Frc.FIELD_WIDTH
		if outside and absf(at.x - float(mouth[0])) < float(processor["half_width_m"]) \
				and at.z < float(processor["max_height_m"]):
			_processed[alliance] += 1
			totals[alliance] += int(processor["points"])
			piece.queue_free()
			return
