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

// Overexposed, warm instant print: reds bloom, blues sink, olive shadows and cream highlights.
extern "C" float4 instantWarmKernel(coreimage::sample_t s) {
    float3 c = saturate(s.rgb);
    // Soft shoulder that brightens red most, like an overexposed pack.
    c = 1.0 - pow(1.0 - c, float3(1.35, 1.12, 1.0));
    // S-curve so the shadows stay deep under the blown highlights.
    c = mix(c, c * c * (3.0 - 2.0 * c), 0.6);
    float lum = dot(c, float3(0.299, 0.587, 0.114));
    c.r = c.r * 1.06 + 0.02;
    c.b *= 0.84;
    c = mix(float3(lum), c, 1.3);
    float3 cream = float3(1.0, 0.96, 0.86);
    c = mix(c, c * cream, smoothstep(0.55, 1.0, lum));
    float3 olive = float3(0.05, 0.06, 0.02);
    c = olive + c * (1.0 - olive);
    return float4(saturate(c), s.a);
}

// Modern Polaroid colour film: low contrast, deep reds, muted cools,
// lavender shadows and corners, creamy highlights.
extern "C" float4 instantLavenderKernel(coreimage::sampler s, float2 center, float radius, coreimage::destination dest) {
    float2 coord = dest.coord();
    float4 px = s.sample(s.transform(coord));
    float3 c = saturate(px.rgb);
    float lum = dot(c, float3(0.299, 0.587, 0.114));
    // Reds keep their saturation, everything else is dulled.
    float redness = saturate((c.r - max(c.g, c.b)) * 3.0);
    c = mix(float3(lum), c, mix(0.7, 1.1, redness));
    c = mix(float3(0.5), c, 0.93);
    // Keep the deepest darks dense, tint the lower mids lavender.
    float shadowAmount = smoothstep(0.02, 0.3, lum) * (1.0 - smoothstep(0.3, 0.85, lum));
    c = mix(c, c * float3(0.94, 0.86, 1.06) + float3(0.05, 0.03, 0.09), shadowAmount);
    c = mix(c, c * float3(1.0, 0.97, 0.90) + 0.04, smoothstep(0.6, 1.0, lum));
    // Corners fall off to purple-grey rather than black.
    float v = smoothstep(0.5, 1.05, distance(coord, center) / radius);
    c = mix(c, c * float3(0.72, 0.62, 0.86), v * 0.85);
    return float4(saturate(c), px.a);
}

// RGB split with random horizontal tears. Offsets are in pixels.
extern "C" float4 rgbSplitKernel(coreimage::sampler s, float2 offset, float bandHeight, float tearWidth, float seed, coreimage::destination dest) {
    float2 coord = dest.coord();
    float band = floor(coord.y / bandHeight);
    float h = fract(sin(band * 12.9898 + seed) * 43758.5453);
    // Roughly one band in five tears, and torn bands split further apart.
    float tear = step(0.8, h) * (0.4 + 0.6 * (h - 0.8) / 0.2);
    float direction = fract(h * 7.0) > 0.5 ? 1.0 : -1.0;
    float2 base = coord + float2(tear * tearWidth * direction, 0.0);
    float2 split = offset * (1.0 + tear * 2.0);
    float4 g = s.sample(s.transform(base));
    float4 r = s.sample(s.transform(base + split));
    float4 b = s.sample(s.transform(base - split));
    return float4(r.r, g.g, b.b, g.a);
}

// Cheap plastic lens: barrel bulge plus lateral chromatic aberration.
// `radius` is the half-diagonal, so the corners stay pinned and no empty edges appear.
extern "C" float4 vintageLensKernel(coreimage::sampler s, float2 center, float radius, float distortion, float fringe, coreimage::destination dest) {
    float2 d = (dest.coord() - center) / radius;
    float r2 = dot(d, d);
    float2 bulged = d * (1.0 + distortion * r2) / (1.0 + distortion);
    // Fringing grows towards the edges, like a real uncorrected lens.
    float2 red  = bulged * (1.0 + fringe * r2);
    float2 blue = bulged * (1.0 - fringe * r2);
    float4 px  = s.sample(s.transform(center + bulged * radius));
    float4 pxR = s.sample(s.transform(center + red * radius));
    float4 pxB = s.sample(s.transform(center + blue * radius));
    return float4(pxR.r, px.g, pxB.b, px.a);
}
