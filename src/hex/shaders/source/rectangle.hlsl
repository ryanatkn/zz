// Rectangle rendering with pixel-perfect edges
// Compile with: dxc -T vs_6_0 -E vs_main rectangle.hlsl -Fo rectangle_vs.dxil
// Compile with: dxc -T ps_6_0 -E ps_main rectangle.hlsl -Fo rectangle_ps.dxil

// Per-frame uniforms
cbuffer FrameUniforms : register(b0) {
    float2 screen_size;
    float4 camera_transform; // [offset_x, offset_y, zoom, rotation]
    float time;
    float _padding;
};

// Per-instance vertex data
struct InstanceInput {
    float2 position : POSITION0;
    float2 size : POSITION1;
    float4 color : COLOR0;
};

// Vertex shader input
struct VertexInput {
    float2 position : POSITION;
    uint vertex_id : SV_VertexID;
    uint instance_id : SV_InstanceID;
};

// Vertex to pixel shader
struct VertexOutput {
    float4 position : SV_Position;
    float4 color : COLOR0;
};

// Quad vertices for instancing
static const float2 quad_positions[4] = {
    float2(0.0, 0.0), // Top-left
    float2(1.0, 0.0), // Top-right  
    float2(1.0, 1.0), // Bottom-right
    float2(0.0, 1.0)  // Bottom-left
};

VertexOutput vs_main(VertexInput input, InstanceInput instance) {
    VertexOutput output;
    
    // Get quad corner position (0,0 to 1,1)
    float2 quad_corner = quad_positions[input.vertex_id];
    
    // Scale by instance size and offset by position
    float2 world_pos = instance.position + quad_corner * instance.size;
    
    // Transform through camera
    world_pos = (world_pos - camera_transform.xy) * camera_transform.z;
    world_pos += screen_size * 0.5;
    
    // Convert to NDC
    output.position = float4(
        (world_pos.x / screen_size.x) * 2.0 - 1.0,
        1.0 - (world_pos.y / screen_size.y) * 2.0,
        0.0,
        1.0
    );
    
    output.color = instance.color;
    
    return output;
}

float4 ps_main(VertexOutput input) : SV_Target {
    return input.color;
}