// Visual effects with animated distance fields and additive blending
// Compile with: dxc -T vs_6_0 -E vs_main effect.hlsl -Fo effect_vs.dxil  
// Compile with: dxc -T ps_6_0 -E ps_main effect.hlsl -Fo effect_ps.dxil

// Effect uniforms - simplified to match other shaders
cbuffer EffectUniforms : register(b0, space1) {
    float2 screen_size;
    float2 center;
    float radius;
    float color_r;
    float color_g;
    float color_b;
    float color_a;
    float intensity;
    float time;
    float3 _padding;
};

// Vertex shader input
struct VertexInput {
    uint vertex_id : SV_VertexID;
};

// Vertex to pixel shader
struct VertexOutput {
    float4 position : SV_Position;
    float2 local_pos : TEXCOORD0;
    float4 color : COLOR0;
    float radius : TEXCOORD1;
    float intensity : TEXCOORD2;
    float2 world_center : TEXCOORD3;
};

// Quad vertices generated procedurally (no static array needed)

VertexOutput vs_main(VertexInput input) {
    VertexOutput output;
    
    // Generate quad corner from vertex ID (same as simple_circle shader)
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
    
    // Convert effect position from screen coordinates to NDC (same as simple_circle)
    float aspect_ratio = screen_size.x / screen_size.y;
    
    // Convert center from screen coordinates to NDC
    float2 ndc_center = float2(
        (center.x / screen_size.x) * 2.0 - 1.0,  // X: 0->width becomes -1->+1
        -((center.y / screen_size.y) * 2.0 - 1.0) // Y: 0->height becomes +1->-1 (flip Y)
    );
    
    // Convert radius from screen pixels to NDC space with precise aspect correction
    float ndc_radius = (radius / screen_size.y) * 2.0; // Use Y for consistent scaling
    float2 aspect_correction = float2(1.0 / aspect_ratio, 1.0); // Precise aspect ratio correction
    
    // Generate final position: center + scaled quad corner
    float2 ndc_pos = ndc_center + quad_corner * ndc_radius * aspect_correction;
    
    output.position = float4(ndc_pos, 0.0, 1.0);
    output.local_pos = quad_corner; // Keep original local pos for distance field
    output.color = float4(color_r, color_g, color_b, color_a);
    output.radius = radius;
    output.intensity = intensity;
    output.world_center = center;
    
    return output;
}

float4 ps_main(VertexOutput input) : SV_Target {
    // High-precision distance from center in local space
    float2 precise_pos = input.local_pos;
    float dist = length(precise_pos);
    
    // Screen-space derivative-based anti-aliasing for stable effect edges
    float delta = length(fwidth(precise_pos));
    float edge_softness = delta * 0.8; // Slightly softer for effects
    
    // Expand effect slightly beyond mathematical boundary for smoother edges
    float circle_radius = 0.97; // Even softer expansion for effects
    float alpha = 1.0 - smoothstep(circle_radius - edge_softness, circle_radius + edge_softness, dist);
    
    // Conservative discard threshold
    if (alpha < 0.01) discard;
    
    // Apply effect intensity and shader boosts with proper alpha clamping
    float final_intensity = input.intensity * 2.0; // 2x intensity boost
    float3 bright_color = input.color.rgb * 2.0; // 2x color boost
    float final_alpha = min(1.0, alpha * input.color.a * final_intensity); // Clamp alpha to 1.0
    
    return float4(bright_color, final_alpha);
}