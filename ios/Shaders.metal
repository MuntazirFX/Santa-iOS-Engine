#include <metal_stdlib>
using namespace metal;

// ============ Textured mesh pipeline ============
struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float3 color;
};

vertex VertexOut mesh_vertex(const device float *data [[buffer(0)]],
                              constant float &angle [[buffer(1)]],
                              uint vid [[vertex_id]]) {
    VertexOut out;
    uint base = vid * 8;  // 3 pos + 2 uv + 3 color
    float3 pos = float3(data[base], data[base+1], data[base+2]);
    
    // Rotate around Y axis
    float c = cos(angle);
    float s = sin(angle);
    float3 r;
    r.x = pos.x * c - pos.z * s;
    r.y = pos.y;
    r.z = pos.x * s + pos.z * c;
    
    out.position = float4(r, 1.0);
    out.uv = float2(data[base+3], data[base+4]);
    out.color = float3(data[base+5], data[base+6], data[base+7]);
    return out;
}

fragment float4 mesh_fragment(VertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               sampler samp [[sampler(0)]]) {
    float4 texColor = tex.sample(samp, in.uv);
    return float4(texColor.rgb * in.color, texColor.a);
}
