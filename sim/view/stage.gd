class_name Stage
extends RefCounted
## Lighting shared by every 3D scene: one sun plus sky light, with shadow
## detail following the graphics quality setting.


static func add_lighting(parent: Node) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = Settings.quality > 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if Settings.quality == 2 \
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 30.0
	parent.add_child(sun)

	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	parent.add_child(world)
