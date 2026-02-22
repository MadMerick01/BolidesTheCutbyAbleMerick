
// Texture input
Texture2D<float4> source : register(t0);
// Unordered Access View (UAV) input - Read/Write
RWTexture2D<float4> destTex : register(u0);

#include "shaders/common/bng.hlsl"

/*cbuffer SettingsConstantBuffer : register(b0)
{
    int2 textureSize;
};*/

[numthreads(8, 8, 1)]
void main_swizzle(uint3 dispatchThreadID : SV_DispatchThreadID) {

    const uint2 currentPos = uint2(dispatchThreadID.xy);

    destTex[currentPos] = source[currentPos].rgba;
}

