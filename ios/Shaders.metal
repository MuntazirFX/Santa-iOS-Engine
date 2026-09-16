#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertex_main(const device float *vertexData [[buffer(0)]],
                              uint vid [[vertex_id]]) {
    VertexOut out;
    uint baseIndex = vid * 6;  // 6 floats per vertex (4 position + 2 UV)
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
    float4 color = tex.sample(samp, in.uv);
    return color;
}
