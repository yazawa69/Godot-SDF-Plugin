#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;

layout(set = 0, binding = 1) restrict buffer SDFParams {
    vec3 translation;   float _pad0;
    vec3 rotation;      float _pad1;
    vec3 scaling;       float _pad2;
    vec4 color;
} sdf_params;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	vec2 reserved;
} params;

float map(in vec3 pos) {
    return length(pos-sdf_params.translation)-(.25*sdf_params.scaling.x);
}

void main() {
	ivec2 invID = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.raster_size);
	
    // Prevent reading/writing out of bounds.
	if (invID.x >= size.x || invID.y >= size.y) {
		return;
	}

	// Read from the color buffer
	vec4 color = imageLoad(color_image, invID);

    // ---------- RAYMARCHING ----------
    // constructing uv coords
    vec2 uv = (vec2(invID) + 0.5) * 2.0 - vec2(size);
    uv /= float(size.y);
    uv.y = -uv.y;

    // init
    vec3 ro = vec3(0., 0., 2.);
    vec3 rd = normalize(vec3(uv, -1.5));
    
    vec4 col = vec4(0.0, 0.0, 0.0, 0.0);

    // raymarch loop
    float t = 0;
    for (int i=0; i<80; i++) {
        vec3 pos = ro + rd * t; // parametrized line
        float d = map(pos);
        if (d<.0001) break;
        t += d;
        if (t>20.0) break;
    }

    // coloring
    if (t<20.0) {
        col = sdf_params.color;
    }

    // color output
	color = vec4(mix(color.rgb, col.rgb, col.a), 1.0);
    // ---------------------------------

	// Write back to the color buffer
	imageStore(color_image, invID, color);
}