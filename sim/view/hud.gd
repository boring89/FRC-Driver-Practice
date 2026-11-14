class_name Hud
extends CanvasLayer
## On-screen telemetry: speed, heading, battery and per-wheel slip.

var robot: SwerveRobot
var camera: CameraRig

var _label := Label.new()


func _ready() -> void:
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)


func _process(_dt: float) -> void:
	if robot == null:
		return
	var slips := PackedStringArray()
	for m in robot.modules:
		slips.append("%.2f" % m.slip_speed)
	var lines := PackedStringArray([
		"%s    %d FPS" % [robot.config["name"], Engine.get_frames_per_second()],
		"Speed  %.2f m/s    Heading  %.0f deg" % [robot.ground_speed(), rad_to_deg(robot.yaw())],
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
		var names := PackedStringArray()
		for preset: Dictionary in superstructure.presets:
			names.append(preset["name"])
		lines.append("%s    [%s]" % ["   ".join(joints), superstructure.preset_name])
		lines.append("")
		lines.append("Number keys / buttons: %s" % "  ".join(names))
	lines.append_array([
		"",
		"Left stick / WASD: move    Right stick / Q E: turn",
		"Start / R: reset    Back / C: camera (%s)    Esc: quit" % CameraRig.MODE_NAMES[camera.mode],
	])
	_label.text = "\n".join(lines)
