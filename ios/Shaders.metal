#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float4 position [[position]];
    float4 color;
};

vertex Vertex vertex_main(const device float4 *positions [[buffer(0)]],
                          uint vid [[vertex_id]]) {
    Vertex out;
    out.position = positions[vid];
    out.color = float4(1.0, 0.5, 0.0, 1.0); // Orange color
    return out;
}

fragment float4 fragment_main(Vertex in [[stage_in]]) {
    return in.color;
}
