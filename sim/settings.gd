class_name Settings
extends RefCounted
## Player settings: graphics options and the keyboard and gamepad bindings of
## every action, stored in user://settings.cfg.

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High"]
const FPS_LIMITS := [0, 60, 120, 144, 240]

## Every bindable action: id, label, default key, default gamepad input.
## A gamepad input is {"button": index} or {"axis": index} (a trigger).
## Driving itself stays on the sticks and is not listed for the gamepad.
const ACTIONS := [
	["move_forward", "Drive forward", KEY_W, {}],
	["move_back", "Drive back", KEY_S, {}],
	["move_left", "Drive left", KEY_A, {}],
	["move_right", "Drive right", KEY_D, {}],
	["turn_left", "Turn left", KEY_Q, {}],
	["turn_right", "Turn right", KEY_E, {}],
	["intake", "Intake", KEY_SPACE, {"axis": JOY_AXIS_TRIGGER_RIGHT}],
	["score", "Score", KEY_F, {"axis": JOY_AXIS_TRIGGER_LEFT}],
	["spit", "Spit back out", KEY_G, {"button": JOY_BUTTON_RIGHT_STICK}],
	["feed_coral", "Feed coral at station", KEY_H, {"button": JOY_BUTTON_RIGHT_SHOULDER}],
	["preload_coral", "Preload coral", KEY_L, {"button": JOY_BUTTON_LEFT_SHOULDER}],
	["reset", "Reset", KEY_R, {"button": JOY_BUTTON_START}],
	["camera", "Next camera", KEY_C, {"button": JOY_BUTTON_BACK}],
	["pose_editor", "Pose editor", KEY_TAB, {}],
]
const _PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L-stick", JOY_BUTTON_RIGHT_STICK: "R-stick",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-up", JOY_BUTTON_DPAD_DOWN: "D-down",
	JOY_BUTTON_DPAD_LEFT: "D-left", JOY_BUTTON_DPAD_RIGHT: "D-right",
}
const _PAD_AXIS_NAMES := {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}

static var quality := 1
static var fullscreen := false
static var vsync := true
static var fps_limit := 0
## Action id -> physical keycode (0 for none).
static var keys := {}
## Action id -> gamepad input (empty for none).
static var pads := {}


static func reset_bindings() -> void:
	for action: Array in ACTIONS:
		keys[action[0]] = action[2]
		pads[action[0]] = (action[3] as Dictionary).duplicate()


static func load_file() -> void:
	reset_bindings()
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	quality = file.get_value("graphics", "quality", quality)
	fullscreen = file.get_value("graphics", "fullscreen", fullscreen)
	vsync = file.get_value("graphics", "vsync", vsync)
	fps_limit = file.get_value("graphics", "fps_limit", fps_limit)
	Session.year = file.get_value("session", "year", Session.year)
	Session.robot_config = file.get_value("session", "robot_config", Session.robot_config)
	for action: Array in ACTIONS:
		keys[action[0]] = file.get_value("keys", action[0], keys[action[0]])
		pads[action[0]] = file.get_value("pads", action[0], pads[action[0]])


static func save_file() -> void:
	var file := ConfigFile.new()
	file.set_value("graphics", "quality", quality)
	file.set_value("graphics", "fullscreen", fullscreen)
	file.set_value("graphics", "vsync", vsync)
	file.set_value("graphics", "fps_limit", fps_limit)
	file.set_value("session", "year", Session.year)
	file.set_value("session", "robot_config", Session.robot_config)
	for action: Array in ACTIONS:
		file.set_value("keys", action[0], keys[action[0]])
		file.set_value("pads", action[0], pads[action[0]])
	file.save(PATH)


## Puts the current settings into effect: bindings, window and render options.
static func apply(tree: SceneTree) -> void:
	if keys.is_empty():
		reset_bindings()
	for action: Array in ACTIONS:
		var id: String = action[0]
		if InputMap.has_action(id):
			InputMap.erase_action(id)
		InputMap.add_action(id, 0.5)
		if keys[id] != 0:
			var key := InputEventKey.new()
			key.physical_keycode = keys[id]
			InputMap.action_add_event(id, key)
		var pad: Dictionary = pads[id]
		if pad.has("button"):
			var button := InputEventJoypadButton.new()
			button.button_index = pad["button"]
			InputMap.action_add_event(id, button)
		elif pad.has("axis"):
			var motion := InputEventJoypadMotion.new()
			motion.axis = pad["axis"]
			motion.axis_value = 1.0
			InputMap.action_add_event(id, motion)

	var viewport := tree.root
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	viewport.scaling_3d_scale = 0.75 if quality == 0 else 1.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if quality == 2 else 2048, true)
	DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_limit


static func key_name(id: String) -> String:
	return "—" if keys.get(id, 0) == 0 else OS.get_keycode_string(keys[id])


static func pad_name(id: String) -> String:
	var pad: Dictionary = pads.get(id, {})
	if pad.has("button"):
		return _PAD_BUTTON_NAMES.get(pad["button"], "Button %d" % pad["button"])
	if pad.has("axis"):
		return _PAD_AXIS_NAMES.get(pad["axis"], "Axis %d" % pad["axis"])
	return "—"


## "Space / RT" style summary of what triggers an action, for on-screen help.
static func describe(id: String) -> String:
	var names := PackedStringArray()
	for text in [key_name(id), pad_name(id)]:
		if text != "—":
			names.append(text)
	return " / ".join(names)
