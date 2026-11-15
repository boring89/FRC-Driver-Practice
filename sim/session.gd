class_name Session
extends RefCounted
## What the practice scene should load and how the match is set up: chosen in
## the menus, with defaults so the scene also runs on its own.

const MATCH_LENGTHS := [75, 135, 150, 195, 315]
const AUTO_FEED_LIMITS := [0, 2, 4, 6]

static var year := 2025
static var robot_config := "res://data/robots/2910_2025.json"
static var alliance := "blue"
## Starting pose in field coordinates; NAN until one is chosen, which means
## the alliance's default spot.
static var start_position := Vector2(NAN, NAN)
static var start_heading := 0.0
## No clock and no end: the match just keeps score.
static var free_practice := false
static var match_seconds := 135
## Coral the human players keep lying ready on the floor; 0 feeds only when asked.
static var auto_feed_limit := 4


## Field heading the driver looks along from behind their alliance wall.
static func driver_heading() -> float:
	return PI if alliance == "red" else 0.0


## Where a robot starts when the driver has not placed it: just short of the
## centre of the field on its own side, facing its own reef.
static func default_start() -> Vector3:
	var spot := Vector2(7.1, 2.0)
	if alliance == "red":
		return Vector3(Frc.FIELD_LENGTH - spot.x, Frc.FIELD_WIDTH - spot.y, 0.0)
	return Vector3(spot.x, spot.y, PI)


## The starting pose as (x, y, heading).
static func start_pose() -> Vector3:
	if is_nan(start_position.x):
		return default_start()
	return Vector3(start_position.x, start_position.y, start_heading)
