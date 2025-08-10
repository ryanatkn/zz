// Circle rendering with distance field anti-aliasing
// Compile with: dxc -T vs_6_0 -E vs_main circle.hlsl -Fo circle_vs.dxil
// Compile with: dxc -T ps_6_0 -E ps_main circle.hlsl -Fo circle_ps.dxil

// Per-frame uniforms
cbuffer FrameUniforms : register(b0) {
    float2 screen_size;
    float4 camera_transform; // [offset_x, offset_y, zoom, rotation]
    float time;
    float _padding;
};

// Per-instance vertex data
struct InstanceInput {
    float2 center : POSITION0;
    float radius : POSITION1;
    float4 color : COLOR0;
};

// Vertex shader input (quad corners)
struct VertexInput {
    float2 position : POSITION;
    uint vertex_id : SV_VertexID;
    uint instance_id : SV_InstanceID;
};

// Vertex to pixel shader
struct VertexOutput {
    float4 position : SV_Position;
    float2 local_pos : TEXCOORD0;
    float4 color : COLOR0;
    float radius : TEXCOORD1;
};

// Quad vertices for instancing (corners of unit square)
static const float2 quad_positions[4] = {
    float2(-1.0, -1.0),
    float2( 1.0, -1.0),
    float2( 1.0,  1.0),
    float2(-1.0,  1.0)
};

VertexOutput vs_main(VertexInput input, InstanceInput instance) {
    VertexOutput output;
    
    // Get quad corner position
    float2 quad_corner = quad_positions[input.vertex_id];
    
    // Transform instance center through camera
    float2 screen_center = instance.center;
    screen_center = (screen_center - camera_transform.xy) * camera_transform.z;
    screen_center += screen_size * 0.5;
    
    // Scale quad by radius and convert to NDC
    float2 world_pos = screen_center + quad_corner * instance.radius;
    output.position = float4(
        (world_pos.x / screen_size.x) * 2.0 - 1.0,
        1.0 - (world_pos.y / screen_size.y) * 2.0,
        0.0,
        1.0
    );
    
    // Pass through data for pixel shader
    output.local_pos = quad_corner;
    output.color = instance.color;
    output.radius = instance.radius; // Pass actual radius for proper AA calculation
    
    return output;
}

float4 ps_main(VertexOutput input) : SV_Target {
    // High-precision distance from center of quad in local space
    float2 precise_pos = input.local_pos;
    float dist = length(precise_pos);
    
    // Screen-space derivative-based anti-aliasing for stable edges
    float delta = length(fwidth(precise_pos));
    float edge_softness = delta * 0.7; // Smooth transition based on screen pixel size
    
    // Expand circle slightly beyond mathematical boundary for smoother edges
    float circle_radius = 0.98; // Slightly smaller than 1.0 to allow AA expansion
    float alpha = 1.0 - smoothstep(circle_radius - edge_softness, circle_radius + edge_softness, dist);
    
    // Conservative discard threshold
    if (alpha < 0.01) discard;
    
    // Apply instance color with calculated alpha
    return float4(input.color.rgb, input.color.a * alpha);
}