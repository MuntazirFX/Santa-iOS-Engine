#include <metal_stdlib>

using namespace metal;

// ============================================================
// 3D Vertex
// ============================================================

struct Vertex3D {
    float3 position;
    float3 color;
    float2 uv;
};

// ============================================================
// Camera / matrices
//
// CPU side should provide matrices using the same convention
// as the renderer.
//
// Metal uses column-vector multiplication here:
//
//     clip = projection * view * model * position
// ============================================================

struct CameraUniforms {
    float4x4 model;
    float4x4 view;
    float4x4 projection;
};

// ============================================================
// Vertex output
// ============================================================

struct VertexOut {
    float4 position [[position]];
    float3 color;
    float2 uv;
};

// ============================================================
// Main 3D vertex shader
// ============================================================

vertex VertexOut
mesh_vertex_3d(
    const device Vertex3D *vertices
        [[buffer(0)]],

    constant CameraUniforms& camera
        [[buffer(1)]],

    uint vertexID
        [[vertex_id]]
) {
    VertexOut out;

    Vertex3D vertex =
        vertices[vertexID];

    float4 localPosition =
        float4(
            vertex.position,
            1.0
        );

    float4 worldPosition =
        camera.model *
        localPosition;

    float4 viewPosition =
        camera.view *
        worldPosition;

    out.position =
        camera.projection *
        viewPosition;

    out.color =
        vertex.color;

    out.uv =
        vertex.uv;

    return out;
}

// ============================================================
// Solid color fragment
// ============================================================

fragment float4
mesh_fragment_3d(
    VertexOut in [[stage_in]]
) {
    return float4(
        in.color,
        1.0
    );
}

// ============================================================
// Compatibility shader
//
// Keeps the old function name available for the current
// renderer. This version still uses the existing float buffer:
//
// position.xyz + color.xyz
// ============================================================

vertex VertexOut
mesh_vertex(
    const device float *data
        [[buffer(0)]],

    constant float &angle
        [[buffer(1)]],

    uint vertexID
        [[vertex_id]]
) {
    VertexOut out;

    uint base =
        vertexID * 6;

    float3 position =
        float3(
            data[base + 0],
            data[base + 1],
            data[base + 2]
        );

    float3 color =
        float3(
            data[base + 3],
            data[base + 4],
            data[base + 5]
        );

    float c =
        cos(angle);

    float s =
        sin(angle);

    float3 rotated;

    rotated.x =
        position.x * c -
        position.z * s;

    rotated.y =
        position.y;

    rotated.z =
        position.x * s +
        position.z * c;

    out.position =
        float4(
            rotated,
            1.0
        );

    out.color =
        color;

    out.uv =
        float2(
            0.0,
            0.0
        );

    return out;
}

// ============================================================
// Compatibility fragment
// ============================================================

fragment float4
mesh_fragment(
    VertexOut in [[stage_in]]
) {
    return float4(
        in.color,
        1.0
    );
}
