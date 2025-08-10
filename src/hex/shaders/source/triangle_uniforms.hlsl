// Triangle shader with uniform buffer support
// SDL3 GPU API requires vertex shader uniforms at (b[n], space1)
cbuffer FrameUniforms : register(b0, space1) {
    float2 screen_size;
    float time;
    float _padding;
};

// Vertex shader input (just vertex ID)
struct VertexInput {
    uint vertex_id : SV_VertexID;
};

// Vertex to pixel shader
struct VertexOutput {
    float4 position : SV_Position;
    float4 color : COLOR0;
};

// Generate triangle vertices procedurally with time-based animation
VertexOutput vs_main(VertexInput input) {
    VertexOutput output;
    
    // Base triangle positions in NDC space
    float2 positions[3] = {
        float2(0.0, 0.5),   // top
        float2(-0.5, -0.5), // bottom-left
        float2(0.5, -0.5)   // bottom-right
    };
    
    // Calculate color intensity based on screen aspect ratio and time
    float screen_ratio = screen_size.x / screen_size.y; 
    float base_intensity = screen_ratio / 2.0; 
    
    // Time-based pulsing animation
    float time_pulse = sin(time * 2.0) * 0.3 + 0.7; 
    float final_intensity = base_intensity * time_pulse;
    
    float4 colors[3] = {
        float4(final_intensity, 0.0, 0.0, 1.0),     // Red
        float4(0.0, final_intensity, 0.0, 1.0),     // Green  
        float4(0.0, 0.0, final_intensity, 1.0)      // Blue
    };
    
    uint vertex_index = input.vertex_id % 3;
    
    // Use base triangle positions
    float2 pos = positions[vertex_index];
    
    output.position = float4(pos, 0.0, 1.0);
    output.color = colors[vertex_index];
    
    return output;
}

float4 ps_main(VertexOutput input) : SV_Target {
    return input.color;
}