// Debug circle shader - simplified version to test visibility
// SDL3 GPU API requires vertex shader uniforms at (b[n], space1)
cbuffer CircleUniforms : register(b0, space1) {
    float2 screen_size;      // 8 bytes
    float2 circle_center;    // 8 bytes
    float circle_radius;     // 4 bytes  
    float _padding1;         // 4 bytes (alignment)
    float4 circle_color;     // 16 bytes (RGBA)
};

// Vertex shader input (just vertex ID)
struct VertexInput {
    uint vertex_id : SV_VertexID;
};

// Vertex to pixel shader
struct VertexOutput {
    float4 position : SV_Position;
    float2 local_pos : TEXCOORD0;
    float4 color : COLOR0;
};

// Generate quad vertices procedurally
VertexOutput vs_main(VertexInput input) {
    VertexOutput output;
    
    // Generate a simple full-screen quad to test if anything renders
    float2 quad_corner;
    uint tri = input.vertex_id / 3;  // Triangle index (0 or 1)
    uint vert = input.vertex_id % 3; // Vertex in triangle (0, 1, 2)
    
    // Generate quad covering center of screen
    if (tri == 0) {
        if (vert == 0) quad_corner = float2(-0.5, -0.5);      // bottom-left
        else if (vert == 1) quad_corner = float2(0.5, -0.5);  // bottom-right
        else quad_corner = float2(-0.5, 0.5);                 // top-left
    } else {
        if (vert == 0) quad_corner = float2(-0.5, 0.5);       // top-left
        else if (vert == 1) quad_corner = float2(0.5, -0.5);  // bottom-right
        else quad_corner = float2(0.5, 0.5);                  // top-right
    }
    
    // Use the quad corner directly as NDC coordinates (no transformation)
    output.position = float4(quad_corner, 0.0, 1.0);
    
    // Pass through data for pixel shader
    output.local_pos = quad_corner;
    output.color = float4(1.0, 0.0, 1.0, 1.0); // Bright magenta - should be very visible
    
    return output;
}

float4 ps_main(VertexOutput input) : SV_Target {
    // Just return the color - no distance field for now
    return input.color;
}