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
	["move_forward", "Drive Forward", KEY_W, {}],
	["move_back", "Drive Back", KEY_S, {}],
	["move_left", "Drive Left", KEY_A, {}],
	["move_right", "Drive Right", KEY_D, {}],
	["turn_left", "Steer Left", KEY_J, {}],
	["turn_right", "Steer Right", KEY_L, {}],
	["align_left", "Auto Align Left", KEY_Q, {"button": JOY_BUTTON_LEFT_SHOULDER}],
	["align_right", "Auto Align Right", KEY_E, {"button": JOY_BUTTON_RIGHT_SHOULDER}],
	["climb", "Climb", KEY_C, {"button": JOY_BUTTON_DPAD_LEFT}],
	["intake", "Intake", KEY_SHIFT, {"axis": JOY_AXIS_TRIGGER_LEFT}],
	["l1", "L1", KEY_U, {"button": JOY_BUTTON_A}],
	["l2", "L2", KEY_I, {"button": JOY_BUTTON_B}],
	["l3", "L3", KEY_O, {"button": JOY_BUTTON_X}],
	["l4", "L4", KEY_P, {"button": JOY_BUTTON_Y}],
	["place", "Place", KEY_K, {"axis": JOY_AXIS_TRIGGER_RIGHT}],
	["mode_toggle", "Robot Mode Toggle", KEY_SEMICOLON, {"button": JOY_BUTTON_DPAD_UP}],
	["special", "Robot Special", KEY_V, {"button": JOY_BUTTON_DPAD_RIGHT}],
	["stow", "Stow", KEY_Z, {"button": JOY_BUTTON_DPAD_DOWN}],
	["camera", "Swap Camera", KEY_SPACE, {"button": JOY_BUTTON_RIGHT_STICK}],
	["speed_1", "Drive Speed 1", KEY_1, {}],
	["speed_2", "Drive Speed 2", KEY_2, {}],
	["speed_3", "Drive Speed 3", KEY_3, {}],
	["feed_coral", "Feed Coral", KEY_H, {"button": JOY_BUTTON_BACK}],
	["preload_coral", "Preload Coral", KEY_B, {}],
	["reset", "Reset", KEY_R, {"button": JOY_BUTTON_START}],
	["pose_editor", "Pose Editor", KEY_TAB, {}],
]
# Bumped whenever the action set changes, so stale saved bindings are dropped.
const _BINDINGS_VERSION := 2
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
	Session.alliance = file.get_value("session", "alliance", Session.alliance)
	Session.start_position = file.get_value("session", "start_position", Session.start_position)
	Session.start_heading = file.get_value("session", "start_heading", Session.start_heading)
	Session.free_practice = file.get_value("session", "free_practice", Session.free_practice)
	Session.match_seconds = file.get_value("session", "match_seconds", Session.match_seconds)
	if file.get_value("meta", "bindings_version", 0) != _BINDINGS_VERSION:
		return
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
	file.set_value("session", "alliance", Session.alliance)
	file.set_value("session", "start_position", Session.start_position)
	file.set_value("session", "start_heading", Session.start_heading)
	file.set_value("session", "free_practice", Session.free_practice)
	file.set_value("session", "match_seconds", Session.match_seconds)
	file.set_value("meta", "bindings_version", _BINDINGS_VERSION)
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


## Puts one action's keyboard or gamepad binding back to its default.
static func reset_binding(id: String, is_pad: bool) -> void:
	for action: Array in ACTIONS:
		if action[0] == id and is_pad:
			pads[id] = (action[3] as Dictionary).duplicate()
		elif action[0] == id:
			keys[id] = action[2]


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
