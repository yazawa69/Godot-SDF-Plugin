#[compute]
#version 450

// compute shader tutorial from the godot docs

// Invocations in the (x,y,z) dim
layout(local_size_x = 2, local_size_y = 1, local_size_z = 1) in;

// A binding to the buffer we create in our script
layout(set = 0, binding = 0, std430) restrict buffer MyDataBuffer {
    float data[];
}
my_data_buffer;

// The code we want to execute in each Invocation
void main() {
    my_data_buffer.data[gl_GlobalInvocationID.x] *= 2.0;
}