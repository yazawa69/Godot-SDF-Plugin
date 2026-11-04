@tool
extends WorldEnvironment

@onready var directional_light_3d = $"../DirectionalLight3D"
@onready var sdf_sphere_prototype = $"../SDFSphere_Prototype"

var _raymarchEffect: PostProcessRaymarcher

func _ready():
	#TODO: make loop that finds the right one
	_raymarchEffect = self.compositor.compositor_effects[0]

func _process(delta):
	_raymarchEffect.sdf_transform = sdf_sphere_prototype.position
	_raymarchEffect.sdf_rotation = sdf_sphere_prototype.rotation
	_raymarchEffect.sdf_scaling = sdf_sphere_prototype.scale
	_raymarchEffect.sdf_color = sdf_sphere_prototype.material_override.albedo_color
	
	_raymarchEffect.light_direction = directional_light_3d.global_transform.basis.z
	var lcol = directional_light_3d.light_color
	_raymarchEffect.light_color = Vector3(lcol.r, lcol.g, lcol.b)
	_raymarchEffect.light_intensity = directional_light_3d.light_energy
