// Circle rendering with distance field anti-aliasing
cbuffer CircleUniforms : register(b0, space1) {
    float2 screen_size;      // Screen dimensions for NDC conversion
    float2 circle_center;    // Circle position in screen coordinates
    float circle_radius;     // Circle radius in pixels
    float circle_color_r;    // Color components split to avoid
    float circle_color_g;    // HLSL array packing issues that
    float circle_color_b;    // caused color channel corruption
    float circle_color_a;    // Alpha channel
    float _padding;          // 16-byte alignment padding
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
    
    // Generate quad corner from vertex ID (6 vertices for 2 triangles)
    float2 quad_corner;
    uint tri = input.vertex_id / 3;  // Triangle index (0 or 1)
    uint vert = input.vertex_id % 3; // Vertex in triangle (0, 1, 2)
    
    // First triangle: (0,0), (1,0), (0,1)
    // Second triangle: (0,1), (1,0), (1,1)
    if (tri == 0) {
        if (vert == 0) quad_corner = float2(-1.0, -1.0);      // bottom-left
        else if (vert == 1) quad_corner = float2(1.0, -1.0);  // bottom-right
        else quad_corner = float2(-1.0, 1.0);                 // top-left
    } else {
        if (vert == 0) quad_corner = float2(-1.0, 1.0);       // top-left
        else if (vert == 1) quad_corner = float2(1.0, -1.0);  // bottom-right
        else quad_corner = float2(1.0, 1.0);                  // top-right
    }
    
    // Convert circle position from screen coordinates to NDC with aspect ratio correction
    float aspect_ratio = screen_size.x / screen_size.y;
    
    // Convert circle center from screen coordinates to NDC
    float2 ndc_center = float2(
        (circle_center.x / screen_size.x) * 2.0 - 1.0,  // X: 0->width becomes -1->+1
        -((circle_center.y / screen_size.y) * 2.0 - 1.0) // Y: 0->height becomes +1->-1 (flip Y)
    );
    
    // Convert radius from screen pixels to NDC space with aspect correction
    float ndc_radius = (circle_radius / screen_size.y) * 2.0; // Use Y for consistent scaling
    float2 aspect_correction = float2(1.0 / aspect_ratio, 1.0); // Compress X for circular shape
    
    // Generate final position: center + scaled quad corner
    float2 ndc_pos = ndc_center + quad_corner * ndc_radius * aspect_correction;
    
    output.position = float4(ndc_pos, 0.0, 1.0);
    
    output.local_pos = quad_corner;
    output.color = float4(circle_color_r, circle_color_g, circle_color_b, circle_color_a);
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
    
    return float4(input.color.rgb, alpha * input.color.a);
}