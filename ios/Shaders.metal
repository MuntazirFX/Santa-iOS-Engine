#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// ==== Textured quad pipeline ====
vertex VertexOut vertex_main(const device float *vertexData [[buffer(0)]],
                              uint vid [[vertex_id]]) {
    VertexOut out;
    uint baseIndex = vid * 6;
    out.position = float4(vertexData[baseIndex],
                          vertexData[baseIndex+1],
                          vertexData[baseIndex+2],
                          vertexData[baseIndex+3]);
    out.uv = float2(vertexData[baseIndex+4], vertexData[baseIndex+5]);
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               sampler samp [[sampler(0)]]) {
    return tex.sample(samp, in.uv);
}

// ==== Mesh wireframe pipeline ====
struct MeshVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex MeshVertexOut mesh_vertex(const device float *data [[buffer(0)]],
                                  uint vid [[vertex_id]]) {
    MeshVertexOut out;
    uint base = vid * 7; // 3 position + 4 color (RGBA)
    out.position = float4(data[base], data[base+1], data[base+2], 1.0);
    out.color = float4(data[base+3], data[base+4], data[base+5], data[base+6]);
    return out;
}

fragment float4 mesh_fragment(MeshVertexOut in [[stage_in]]) {
    return in.color;
}
