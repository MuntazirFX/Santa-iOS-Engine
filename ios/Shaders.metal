#include <metal_stdlib>
using namespace metal;

// ============================================================
// Santa Claus in Trouble - Metal Shader
// Current GameEngine vertex layout:
//
// X Y Z R G B
// = 6 floats per vertex
// ============================================================

struct VertexOut
{
    float4 position [[position]];
    float3 color;
};

// ============================================================
// Vertex Shader
// ============================================================

vertex VertexOut mesh_vertex(
    const device float *data [[buffer(0)]],
    constant float &angle [[buffer(1)]],
    uint vertexID [[vertex_id]]
)
{
    VertexOut out;

    uint base = vertexID * 6;

    // Position
    float3 pos = float3(
        data[base + 0],
        data[base + 1],
        data[base + 2]
    );

    // Vertex color
    float3 color = float3(
        data[base + 3],
        data[base + 4],
        data[base + 5]
    );

    // --------------------------------------------------------
    // Rotate around Y
    // --------------------------------------------------------

    float c = cos(angle);
    float s = sin(angle);

    float3 rotated;

    rotated.x = pos.x * c - pos.z * s;
    rotated.y = pos.y;
    rotated.z = pos.x * s + pos.z * c;

    // --------------------------------------------------------
    // Output
    // --------------------------------------------------------

    out.position = float4(
        rotated.x,
        rotated.y,
        rotated.z,
        1.0
    );

    out.color = color;

    return out;
}

// ============================================================
// Fragment Shader
// ============================================================

fragment float4 mesh_fragment(
    VertexOut in [[stage_in]]
)
{
    return float4(
        in.color,
        1.0
    );
}
