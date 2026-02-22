// Vertex Shader Output -> Pixel Shader Input
struct vertexVS {
    // SV_POSITION id identify pos as screen space
    // position we output from the VS and the SP input
    float4 pos : SV_POSITION;
    //float3 normal : NORMAL;
    float3 posWS : POSITION;
    //float2 texCoord0 : TEXCOORD0;
};

cbuffer bufferdata :register(b0) {
    float4x4 worldToViewToScreen;
}

//Texture2D dynDecal : register(t1);
SamplerState defaultSampler : register(s0);
//Texture2D uiTexture : register(t2);

// Pixel Shader Output
struct PXOutput {
    // this value will be send to the texture 0 in the render target
    float4 out0 : SV_Target0;
};

float3 checkerColor(float2 uv, float3 apos) {
  uv = abs(uv) % 1;
  float checkSize = 10;
  float fmodResult = fmod(floor(checkSize * uv.x) + floor(checkSize * uv.y), 2.0);
  float fin = max(sign(fmodResult), 0.0);
  return float3(fin *clamp(apos.x,0.5,1), fin*clamp(apos.y,0.5,1), fin*clamp(apos.z,0.5,1));
}

PXOutput main(vertexVS inPxl) {
    PXOutput outPxl;

    // Color from the ConstBuffer we set in BeamNGTestTriangle.cpp
    //float3 shapeColor = checkerColor(inPxl.texCoord0, inPxl.posWS);

    //outPxl.out0 = float4(shapeColor, 1);
    //const float4 uiDiffuse = uiTexture.Sample(defaultSampler, inPxl.texCoord0);

    //outPxl.out0 = float4(uiDiffuse.xyz , 1);
    outPxl.out0 = float4(0.0,0.0,0.0,1);

    return outPxl;
}
