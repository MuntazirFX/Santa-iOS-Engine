#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vertex_main(const device float *vertexData [[buffer(0)]],
                              uint vid [[vertex_id]]) {
    VertexOut out;
    // Har vertex 8 floats ka hai: 4 position + 4 color
    uint baseIndex = vid * 8;
    out.position = float4(vertexData[baseIndex], vertexData[baseIndex+1], vertexData[baseIndex+2], vertexData[baseIndex+3]);
    out.color = float4(vertexData[baseIndex+4], vertexData[baseIndex+5], vertexData[baseIndex+6], vertexData[baseIndex+7]);
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
