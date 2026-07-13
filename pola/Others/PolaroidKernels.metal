#include <CoreImage/CoreImage.h>

using namespace metal;

extern "C" float4 thermalKernel(coreimage::sample_t s) {
    float lum = dot(s.rgb, float3(0.299, 0.587, 0.114));
    float3 col;
    if (lum < 0.25)      col = mix(float3(0.05, 0.0, 0.3),  float3(0.0, 0.3, 0.9),   lum / 0.25);
    else if (lum < 0.5)  col = mix(float3(0.0, 0.3, 0.9),   float3(0.0, 0.85, 0.3),  (lum - 0.25) / 0.25);
    else if (lum < 0.75) col = mix(float3(0.0, 0.85, 0.3),  float3(1.0, 0.9, 0.0),   (lum - 0.5) / 0.25);
    else                 col = mix(float3(1.0, 0.9, 0.0),    float3(1.0, 1.0, 1.0),   (lum - 0.75) / 0.25);
    return float4(col, s.a);
}

extern "C" float4 vhsKernel(coreimage::sampler s, coreimage::destination dest, float time) {
    float2 coord = dest.coord();
    float bleed = 3.0;
    float4 px  = s.sample(s.transform(coord));
    float4 pxR = s.sample(s.transform(coord + float2(-bleed, 0)));
    float4 pxB = s.sample(s.transform(coord + float2( bleed, 0)));
    float4 mixed = float4(pxR.r, px.g, pxB.b, px.a);
    float scanline = fmod(floor(coord.y), 2.0) < 1.0 ? 0.70 : 1.0;
    return mixed * float4(float3(scanline), 1.0);
}

extern "C" float4 cyanotypeKernel(coreimage::sample_t s) {
    float lum = dot(s.rgb, float3(0.299, 0.587, 0.114));
    float t = 1.0 - lum;
    float3 paper = float3(0.94, 0.96, 0.90);
    float3 blue  = float3(0.03, 0.19, 0.42);
    float3 col   = mix(paper, blue, t);
    return float4(col, s.a);
}

extern "C" float4 nightVisionKernel(coreimage::sample_t s) {
    float lum = dot(s.rgb, float3(0.299, 0.587, 0.114));
    float3 phosphor = float3(0.0, lum * 1.15, 0.0);
    float bloom = max(0.0, lum - 0.78) * 3.5;
    phosphor = clamp(phosphor + float3(0.0, bloom, bloom * 0.3), 0.0, 1.0);
    return float4(phosphor, s.a);
}
