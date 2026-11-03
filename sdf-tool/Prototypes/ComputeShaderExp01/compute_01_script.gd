# from godot docs on compute shading
extends Node

func _ready() -> void:
	# create a local rendering device
	var rd : RenderingDevice = RenderingServer.create_local_rendering_device()

	# load glsl shader
	var shader_file : RDShaderFile = load("res://Prototypes/ComputeShaderExp01/compute_example.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	var shader : RID = rd.shader_create_from_spirv(shader_spirv)

	# prepare our data. we use floats in the shader, so we need 32 bit.
	var input := PackedFloat32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	var input_bytes := input.to_byte_array()

	# create a storage buffer that can hold our float values.
	# each float has 4 bytes (32 bit) so 10x4 = 40 bytes
	var buffer : RID = rd.storage_buffer_create(input_bytes.size(), input_bytes)

	# Create a uniform to assign the buffer to the rendering device
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0 # this needs to match the "binding" in our shader file
	uniform.add_id(buffer)
	var uniform_set : RID = rd.uniform_set_create([uniform], shader, 0) # the last parameter (the 0) needs to match the "set" in our shader file

	# create a compute pipeline
	var pipeline : RID = rd.compute_pipeline_create(shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 5, 1, 1)
	rd.compute_list_end()

	# submit to gpu and wait for sync
	rd.submit()
	rd.sync()

	# read back the data from the buffer
	var output_bytes := rd.buffer_get_data(buffer)
	var output := output_bytes.to_float32_array()
	print("Input: ", input)
	print("Output: ", output)
	
	# free all ressources 
	# do it in inverse order to the declaration
	rd.free_rid(pipeline)
	rd.free_rid(uniform_set)
	rd.free_rid(buffer)
	rd.free_rid(shader)
