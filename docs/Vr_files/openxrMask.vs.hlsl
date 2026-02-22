struct vertexIA {

    float3 pos : POSITION;
    //float2 texCoord0 : TEXCOORD0;
};

cbuffer bufferdata :register(b0) {
    float4x4 worldToViewToScreen;
}

//StructuredBuffer<float4x4> instances : register(t0); // store local to world

// Vertex Shader Output -> Pixel Shader Input
struct vertexVS {
    // SV_POSITION id identify pos as screen space
    // position we output from the VS and the SP input
    float4 posClipSpace : SV_POSITION; // SV_POSITION ALWAYS need to be in clip space
    //float3 normal : NORMAL;
    float3 posWS : POSITION;
    //float2 texCoord0 : TEXCOORD0;
};

vertexVS main(vertexIA inVtx, uint svInstanceID : SV_InstanceID) {
    vertexVS outVtx;

    // Convert our vertex to screen space.
    outVtx.posWS = inVtx.pos.xyz; //  to world << vtx local space
    float4 posClipSpace = mul(worldToViewToScreen, float4(outVtx.posWS, 1)); // screen << world
    posClipSpace.z = posClipSpace.w - 1E-6; // Force to near plane (z = w)
    outVtx.posClipSpace = posClipSpace;
    //outVtx.normal = inVtx.normal;
    //outVtx.texCoord0 = inVtx.texCoord0;

    // NDC X[-1..+1] Y[-1..+1] Z:depth[0..+1]
    // perpective division
    //float3 posNDC = (outVtx.posClipSpace / outVtx.posClipSpace.w).xyz;

    // [0..1] [0..1]
    //float2 posScreenUV = posNDC.xy * 0.5 + 0.5;

    // [0..width] [0..height] ... this space always have an offset of 0.5 << super important
    //float2 posScreenSpace = posScreenUV.xy * float2(width, height);

    return outVtx;
}
