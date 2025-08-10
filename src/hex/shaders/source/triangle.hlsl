// Minimal triangle test shader - procedural triangle generation
// This is based on SDL3's BasicTriangle example but simplified further

// Vertex shader input (just vertex ID)
struct VertexInput {
    uint vertex_id : SV_VertexID;
};

// Vertex to pixel shader
struct VertexOutput {
    float4 position : SV_Position;
    float4 color : COLOR0;
};

// Generate triangle vertices procedurally
VertexOutput vs_main(VertexInput input) {
    VertexOutput output;
    
    // Hardcoded triangle positions in NDC space
    float2 positions[3] = {
        float2(0.0, 0.5),   // top
        float2(-0.5, -0.5), // bottom-left
        float2(0.5, -0.5)   // bottom-right
    };
    
    // Simple colors for each vertex
    float4 colors[3] = {
        float4(1.0, 0.0, 0.0, 1.0), // red
        float4(0.0, 1.0, 0.0, 1.0), // green
        float4(0.0, 0.0, 1.0, 1.0)  // blue
    };
    
    uint vertex_index = input.vertex_id % 3;
    
    output.position = float4(positions[vertex_index], 0.0, 1.0);
    output.color = colors[vertex_index];
    
    return output;
}

float4 ps_main(VertexOutput input) : SV_Target {
    return input.color;
}