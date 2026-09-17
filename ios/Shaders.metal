#include <metal_stdlib>
using namespace metal;

// ============ Solid color pipeline (by vertex color) ============
struct VertexOut {
    float4 position [[position]];
    float3 color;
};

vertex VertexOut mesh_vertex(const device float *data [[buffer(0)]],
                              constant float &angle [[buffer(1)]],
                              uint vid [[vertex_id]]) {
    VertexOut out;
    uint base = vid * 6;  // 3 pos + 3 color
    float3 pos = float3(data[base], data[base+1], data[base+2]);
    
    // Rotate around Y axis
    float c = cos(angle);
    float s = sin(angle);
    float3 r;
    r.x = pos.x * c - pos.z * s;
    r.y = pos.y;
    r.z = pos.x * s + pos.z * c;
    
    out.position = float4(r, 1.0);
    out.color = float3(data[base+3], data[base+4], data[base+5]);
    return out;
}

fragment float4 mesh_fragment(VertexOut in [[stage_in]]) {
    return float4(in.color, 1.0);
}
