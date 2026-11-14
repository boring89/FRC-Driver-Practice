class_name Hud
extends CanvasLayer
## Debug overlay, hidden until F3: telemetry and a reminder of the controls as
## currently bound.

var robot: SwerveRobot
var camera: CameraRig
var driver: DriverInput

var _label := Label.new()


func _ready() -> void:
	visible = false
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		visible = not visible


func _process(_dt: float) -> void:
	if robot == null or not visible:
		return
	var slips := PackedStringArray()
	for m in robot.modules:
		slips.append("%.2f" % m.slip_speed)
	var lines := PackedStringArray([
		"%s    %d FPS" % [robot.config["name"], Engine.get_frames_per_second()],
		"Speed  %.2f m/s    Heading  %.0f deg    Drive speed %d%%" % [
			robot.ground_speed(), rad_to_deg(robot.yaw()), roundi(100.0 * driver.speed_scale)],
		"Battery  %.1f V    %.0f A" % [robot.battery.voltage, robot.battery.current],
		"Wheel slip (m/s)  " + "  ".join(slips),
	])
	var superstructure := robot.superstructure
	if superstructure and not superstructure.joints.is_empty():
		var joints := PackedStringArray()
		for joint in superstructure.joints:
			if joint.prismatic:
				joints.append("%s %.2f m" % [joint.name, joint.position])
			else:
				joints.append("%s %.0f deg" % [joint.name, rad_to_deg(joint.position)])
		lines.append("%s    [%s]" % ["   ".join(joints), superstructure.preset_name])
	if robot.intake:
		lines.append("Mode: %s    Holding: %s" % [
			"algae" if driver.algae_mode else "coral", robot.intake.held.kind if robot.intake.held else "nothing"])
	lines.append("")
	for group: Array in [
		["l1", "l2", "l3", "l4", "stow"],
		["intake", "place", "special", "mode_toggle", "climb"],
		["align_left", "align_right", "camera", "feed_coral", "reset"],
	]:
		var help := PackedStringArray()
		for id: String in group:
			help.append("%s: %s" % [Settings.describe(id), _label_of(id)])
		lines.append("    ".join(help))
	lines.append("Camera: %s    Esc: menu" % CameraRig.MODE_NAMES[camera.mode])
	_label.text = "\n".join(lines)


func _label_of(id: String) -> String:
	for action: Array in Settings.ACTIONS:
		if action[0] == id:
			return action[1]
	return id
