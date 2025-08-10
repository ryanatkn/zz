// Rectangle rendering for terrain and obstacles
cbuffer RectUniforms : register(b0, space1) {
    float2 screen_size;      // Screen dimensions for NDC conversion
    float2 rect_position;    // Rectangle position in screen coordinates
    float2 rect_size;        // Rectangle size in pixels
    float rect_color_r;      // Color components split to avoid
    float rect_color_g;      // HLSL array packing issues that
    float rect_color_b;      // caused color channel corruption
    float rect_color_a;      // Alpha channel
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
        if (vert == 0) quad_corner = float2(0.0, 0.0);      // top-left
        else if (vert == 1) quad_corner = float2(1.0, 0.0); // top-right
        else quad_corner = float2(0.0, 1.0);                // bottom-left
    } else {
        if (vert == 0) quad_corner = float2(0.0, 1.0);      // bottom-left
        else if (vert == 1) quad_corner = float2(1.0, 0.0); // top-right
        else quad_corner = float2(1.0, 1.0);                // bottom-right
    }
    
    // Calculate screen position: position + corner * size
    float2 screen_pos = rect_position + quad_corner * rect_size;
    
    // Convert to NDC coordinates
    float2 ndc_pos = float2(
        (screen_pos.x / screen_size.x) * 2.0 - 1.0,  // X: 0->width becomes -1->+1
        -((screen_pos.y / screen_size.y) * 2.0 - 1.0) // Y: 0->height becomes +1->-1 (flip Y)
    );
    
    output.position = float4(ndc_pos, 0.0, 1.0);
    output.color = float4(rect_color_r, rect_color_g, rect_color_b, rect_color_a);
    
    return output;
}

float4 ps_main(VertexOutput input) : SV_Target {
    return input.color;
}