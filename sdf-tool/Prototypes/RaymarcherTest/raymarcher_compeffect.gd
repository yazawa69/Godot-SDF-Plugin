@tool
class_name PostProcessRaymarcher
extends CompositorEffect

# example sdf
var params_buffer: RID
var sdf_transform: Vector3
var sdf_rotation: Vector3
var sdf_scaling: Vector3 = Vector3.ONE
var sdf_color: Color = Color.WHITE

# example light
var light_buffer: RID
var light_direction: Vector3
var light_color: Vector3
var light_intensity: float

# cam
var cam_buffer: RID

var rd: RenderingDevice
var shader: RID
var pipeline: RID

# created once for depth
var nearest_sampler: RID


func _init() -> void:
	self.effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	self.access_resolved_depth = true
	rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(_initialize_compute)


# System notifications, we want to react on the notification that
# alerts us we are about to be destroyed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if shader.is_valid():
			# Freeing our shader will also free any dependents such as the pipeline!
			rd.free_rid(shader)
		if light_buffer.is_valid(): rd.free_rid(light_buffer)
		if cam_buffer.is_valid(): rd.free_rid(cam_buffer)
		if params_buffer.is_valid(): rd.free_rid(params_buffer)


#region Code in this region runs on the rendering thread.
# Compile our shader at initialization.
func _initialize_compute() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd:
		return

	# Compile our shader.
	var shader_file := load("res://Prototypes/RaymarcherTest/raymarcher_shader.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()

	shader = rd.shader_create_from_spirv(shader_spirv)
	if shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)
	
	# TODO: always create the buffers in init and only update it in _render_callback() or check if .is_valid() in _render_callback()
	params_buffer = rd.storage_buffer_create(64) # 4^6 byte stores exactly 16 Float32's
	
	# create once for depth sampler
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	nearest_sampler = rd.sampler_create(ss)


# Called by the rendering thread every frame.
func _render_callback(p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
	if rd and pipeline.is_valid():
		var scene_data := p_render_data.get_render_scene_data()
		var buffers : RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
		# Get our render scene buffers object, this gives us access to our render buffers.
		# Note that implementation differs per renderer hence the need for the cast.
		var render_scene_buffers := p_render_data.get_render_scene_buffers()
		if render_scene_buffers:
			# Get our render size, this is the 3D render resolution!
			var size: Vector2i = render_scene_buffers.get_internal_size()
			if size.x == 0 and size.y == 0:
				return

			# We can use a compute shader here.
			@warning_ignore("integer_division")
			var x_groups := (size.x - 1) / 8 + 1
			@warning_ignore("integer_division")
			var y_groups := (size.y - 1) / 8 + 1
			var z_groups := 1

			# Create push constant.
			# Must be aligned to 16 bytes and be in the same order as defined in the shader.
			var push_constant := PackedFloat32Array([size.x, size.y, 0.0, 0.0])

			# Loop through views just in case we're doing stereo rendering. No extra cost if this is mono.
			var view_count: int = render_scene_buffers.get_view_count()
			for view in view_count:

				# Create a uniform set, this will be cached, the cache will be cleared if our viewports configuration is changed.
				var input_image: RID = render_scene_buffers.get_color_layer(view)
				var uniform := RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
				uniform.binding = 0
				uniform.add_id(input_image)
				
				# sdf parameters
				var params: PackedByteArray = PackedFloat32Array([
					sdf_transform.x, sdf_transform.y, sdf_transform.z, 0.0,
					sdf_rotation.x, sdf_rotation.y, sdf_rotation.z, 0.0,
					sdf_scaling.x, sdf_scaling.y, sdf_scaling.z, 0.0,
					sdf_color.r, sdf_color.g, sdf_color.b, sdf_color.a,
				]).to_byte_array()
				rd.buffer_update(params_buffer, 0, 64, params)
				var params_uniform := RDUniform.new()
				params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
				params_uniform.binding = 1
				params_uniform.add_id(params_buffer)
				
				# cam buffer (probably better to do it with push constants)
				var cam_to_world := Projection(scene_data.get_cam_transform())
				var inv_proj := scene_data.get_view_projection(view).inverse()
				var cam_bytes := PackedByteArray()
				cam_bytes.append_array(matrix_to_bytes(cam_to_world))
				cam_bytes.append_array(matrix_to_bytes(inv_proj))
				if not cam_buffer.is_valid():
					cam_buffer = rd.storage_buffer_create(cam_bytes.size(), cam_bytes)
				else: 
					rd.buffer_update(cam_buffer, 0, cam_bytes.size(), cam_bytes)
				var cam_uniform := RDUniform.new()
				cam_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
				cam_uniform.binding = 2
				cam_uniform.add_id(cam_buffer)
				
				# light buffer (probably better as push constant)
				light_direction = light_direction.normalized()
				var l_bytes := PackedFloat32Array([
					light_direction.x, light_direction.y, light_direction.z, 0.0,
					light_color.x, light_color.y, light_color.z, 0.0,
					light_intensity, 0.0, 0.0, 0.0,
				]).to_byte_array()
				if not light_buffer.is_valid():
					light_buffer = rd.storage_buffer_create(l_bytes.size(), l_bytes)
				else:
					rd.buffer_update(light_buffer, 0, l_bytes.size(), l_bytes)
				var l_uniform := RDUniform.new()
				l_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
				l_uniform.binding = 3
				l_uniform.add_id(light_buffer)
				
				# Depth Texture uniform
				var depth_tex = buffers.get_depth_layer(view)
				var depth_uniform := RDUniform.new()
				depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
				depth_uniform.binding = 4
				depth_uniform.add_id(nearest_sampler)
				depth_uniform.add_id(depth_tex)
				
				var bindings: Array = [uniform, params_uniform, cam_uniform, 
										l_uniform, depth_uniform]
				
				var uniform_set := UniformSetCacheRD.get_cache(shader, 0, bindings)

				# Run our compute shader.
				var compute_list := rd.compute_list_begin()
				rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
				rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
				rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
				rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
				rd.compute_list_end()
#endregion

func matrix_to_bytes(p: Projection) -> PackedByteArray:
	return PackedFloat32Array([
		p.x.x, p.x.y, p.x.z, p.x.w,
		p.y.x, p.y.y, p.y.z, p.y.w,
		p.z.x, p.z.y, p.z.z, p.z.w,
		p.w.x, p.w.y, p.w.z, p.w.w
	]).to_byte_array()
