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

layout(set = 0, binding = 2) restrict buffer CameraData {
    mat4 toWorld;
    mat4 invProj;
} cam_data;

layout(set = 0, binding = 3) restrict buffer DirectionalLight {
    vec3 dir; float _pad0;
    vec3 col; float _pad1;
    float intensity;
} dir_light;

layout(set = 0, binding = 4) uniform sampler2D depth_sampler;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	vec2 reserved;
} params;

float map(in vec3 pos) {
    return length(pos-sdf_params.translation)-(.25*sdf_params.scaling.x);
}

vec3 calcNormals(in vec3 pos) {
    const float eps = 0.0001;
    const vec2 h = vec2(eps, 0);
    return normalize(vec3(map(pos+h.xyy)-map(pos-h.xyy),
                          map(pos+h.yxy)-map(pos-h.yxy),
                          map(pos+h.yyx)-map(pos-h.yyx)
                         ));
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
    float tmax = 20.0; // far plane clip distance
    vec2 ndc = (vec2(invID) + 0.5) / vec2(size) * 2.0 - 1.0;
    vec4 view_dir = cam_data.invProj * vec4(ndc, 1.0, 1.0);
    vec3 rd_view = normalize(view_dir.xyz/view_dir.w); // view-space ray direction (also used below for depth)
    vec3 rd = normalize((cam_data.toWorld*vec4(rd_view, 0.0)).xyz);
    vec3 ro = cam_data.toWorld[3].xyz;

    // sample depth
    float depth = texelFetch(depth_sampler, invID, 0).r;
    float linear_depth = 0.0; // depth buffer
    float scene_t = 1e9; // ray distance
    if (depth > 0.0) {
        vec4 view_depth = cam_data.invProj*vec4(ndc, depth, 1.0);
        linear_depth = -(view_depth.z/view_depth.w);
        scene_t = linear_depth / max(-rd_view.z, 1e-4);
        tmax = min(tmax, scene_t);
    }
    
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
    if (t<tmax) {
        vec3 pos = ro + rd * t;
        vec3 normal = calcNormals(pos);

        float light_diff = clamp(dot(dir_light.dir, normal), 0.0, 1.0);
        float sky_diff = clamp(0.25 + 0.5 * dot(normal, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);

        col = sdf_params.color;
        col.rgb *= dir_light.col * light_diff;
        col.rgb += vec3(0.0, 0.0, 0.01) * sky_diff;
        col.rgb += .15*sdf_params.color.rgb;
        col.rgb *= dir_light.intensity;
    }

    // color output
    //color = vec4(vec3(linear_depth / 20.0), 1.0); // output depth buffer
    //color = vec4(vec3(scene_t / 20.0), 1.0); // output ray distance
	color = vec4(mix(color.rgb, col.rgb, col.a), 1.0);
    // ---------------------------------

	// Write back to the color buffer
	imageStore(color_image, invID, color);
}