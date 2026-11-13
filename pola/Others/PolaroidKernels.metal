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

// MARK: - Film drop 3 (1.0.9)
// Every size is passed in pixels, computed from the image's short side, and all noise is hashed
// from the pixel position, so a 120 px preview, the print and a re-export look the same.

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Smooth value noise in 0...1 with features `cell` pixels across.
static float valueNoise(float2 coord, float cell) {
    float2 p = coord / cell;
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// GLÖD base grade: tungsten-balanced film shot at night. Cool, dense blacks, mids pushed
// slightly teal, highlights left warm so the halation reads against them.
extern "C" float4 tungstenNightKernel(coreimage::sample_t s) {
    float3 c = saturate(s.rgb);
    float lum = dot(c, float3(0.299, 0.587, 0.114));
    c *= float3(0.86, 0.97, 1.14);
    c = mix(c, c * c * (3.0 - 2.0 * c), 0.45);
    float mids = smoothstep(0.1, 0.45, lum) * (1.0 - smoothstep(0.45, 0.85, lum));
    c += mids * float3(-0.03, 0.015, 0.025);
    c = mix(c, c * float3(1.08, 1.0, 0.9), smoothstep(0.7, 1.0, lum));
    c = float3(0.015, 0.02, 0.035) + c * 0.97;
    return float4(saturate(c), s.a);
}

// GLÖD halation source: only the brightest highlights, already tinted red-orange.
extern "C" float4 halationSourceKernel(coreimage::sample_t s, float threshold) {
    float lum = dot(saturate(s.rgb), float3(0.299, 0.587, 0.114));
    float glow = smoothstep(threshold, 1.0, lum);
    return float4(glow * float3(1.0, 0.30, 0.10) * 1.25, 1.0);
}

// FÖRN: expired colour film. Magenta highlights and green shadows, milky lifted blacks,
// lower saturation, coarse clumpy grain and a fade that creeps in from one edge.
extern "C" float4 expiredFilmKernel(coreimage::sample_t s, float4 extent, float grainCell, coreimage::destination dest) {
    float2 coord = dest.coord();
    float3 c = saturate(s.rgb);
    float lum = dot(c, float3(0.299, 0.587, 0.114));
    c = mix(float3(lum), c, 0.78);
    float shadow = 1.0 - smoothstep(0.0, 0.45, lum);
    float high = smoothstep(0.55, 1.0, lum);
    c += shadow * float3(-0.02, 0.045, -0.005) + high * float3(0.055, -0.03, 0.035);
    c = mix(float3(0.5), c, 0.92);
    float3 milk = float3(0.12, 0.10, 0.115);
    c = milk + c * (1.0 - milk);
    // Fade from the right edge as displayed, wavering so it isn't a clean gradient.
    float2 uv = (coord - extent.xy) / extent.zw;
    float waver = valueNoise(coord, grainCell * 90.0) - 0.5;
    float fade = smoothstep(0.7, 1.25, uv.x + uv.y * 0.2 + waver * 0.2);
    c = mix(c, float3(0.93, 0.84, 0.80), fade * 0.3);
    // Two octaves of grain: clumps plus fine speckle.
    float grain = (valueNoise(coord, grainCell) - 0.5) * 0.8 + (hash21(floor(coord / max(grainCell * 0.4, 1.0))) - 0.5) * 0.4;
    c += grain * 0.11;
    return float4(saturate(c), s.a);
}

// TINN: wet-plate tintype. The plate only sees blue, so skies blow out and reds go dark;
// the edges swirl and soften like a Petzval lens; the plate has streaks and dark edges.
extern "C" float4 wetPlateKernel(coreimage::sampler s, float2 center, float radius, float swirl, float streakWidth, coreimage::destination dest) {
    float2 coord = dest.coord();
    float2 d = coord - center;
    float r = length(d) / radius;
    // Average taps along an arc around the centre: sharp middle, swirling soft edges.
    float spread = swirl * smoothstep(0.35, 1.0, r);
    float2 tangent = r > 0.0001 ? float2(-d.y, d.x) / length(d) : float2(0.0);
    float2 radial = r > 0.0001 ? d / length(d) : float2(0.0);
    float3 acc = float3(0.0);
    for (int i = 0; i < 8; i++) {
        float t = (float(i) / 7.0 - 0.5);
        float2 offset = tangent * t * spread + radial * t * spread * 0.25;
        acc += s.sample(s.transform(coord + offset)).rgb;
    }
    float3 c = saturate(acc / 8.0);
    float lum = dot(c, float3(0.10, 0.30, 0.60)) * 1.35;
    lum = smoothstep(0.02, 0.9, lum);
    lum = pow(lum, 0.8);
    // Plate streaks: a few faint bands where the collodion flowed, fading along their length.
    float band = valueNoise(float2(coord.x, 0.0), streakWidth);
    float flow = valueNoise(float2(coord.x * 0.5, coord.y), streakWidth * 8.0);
    float streak = smoothstep(0.72, 0.95, band) * flow;
    lum += (streak - 0.15) * 0.06;
    // Uneven, darker plate edges.
    float edge = smoothstep(0.62, 1.0, r + (valueNoise(coord, streakWidth * 6.0) - 0.5) * 0.25);
    lum *= 1.0 - edge * 0.65;
    float3 shadowTone = float3(0.09, 0.075, 0.06);
    float3 silver = float3(0.84, 0.82, 0.76);
    float3 col = mix(shadowTone, silver, saturate(lum));
    return float4(col, 1.0);
}

// PRIKK: newsprint CMYK halftone. Each ink is a dot screen at its own angle; dot area follows
// the ink amount sampled at the dot's centre. `cell` is the screen pitch in pixels.
static float halftoneInk(coreimage::sampler s, float2 coord, float cell, float angle, int channel) {
    float cs = cos(angle), sn = sin(angle);
    float2x2 rot = float2x2(float2(cs, -sn), float2(sn, cs));
    float2x2 inv = float2x2(float2(cs, sn), float2(-sn, cs));
    float2 rotated = rot * coord;
    float2 cellCenter = (floor(rotated / cell) + 0.5) * cell;
    float3 rgb = saturate(s.sample(s.transform(inv * cellCenter)).rgb);
    float k = 1.0 - max(max(rgb.r, rgb.g), rgb.b);
    float3 cmy = k < 0.999 ? (1.0 - rgb - k) / (1.0 - k) : float3(0.0);
    float ink = channel == 0 ? cmy.x : channel == 1 ? cmy.y : channel == 2 ? cmy.z : k;
    float dotRadius = sqrt(saturate(ink)) * cell * 0.62;
    float dist = length(rotated - cellCenter);
    return 1.0 - smoothstep(dotRadius - 0.75, dotRadius + 0.75, dist);
}

extern "C" float4 halftoneKernel(coreimage::sampler s, float cell, coreimage::destination dest) {
    float2 coord = dest.coord();
    float c = halftoneInk(s, coord, cell, 0.2618, 0);
    float m = halftoneInk(s, coord, cell, 1.3090, 1);
    float y = halftoneInk(s, coord, cell, 0.0, 2);
    float k = halftoneInk(s, coord, cell, 0.7854, 3);
    float3 paper = float3(0.95, 0.93, 0.86);
    // Process inks are not pure; multiply them onto the paper like overprinting.
    float3 col = paper;
    col *= mix(float3(1.0), float3(0.0, 0.62, 0.86), c);
    col *= mix(float3(1.0), float3(0.90, 0.10, 0.52), m);
    col *= mix(float3(1.0), float3(1.0, 0.92, 0.05), y);
    col *= mix(float3(1.0), float3(0.12, 0.12, 0.13), k);
    return float4(col, 1.0);
}
