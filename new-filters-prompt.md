# Prompt: New Filter Pack — "WEIRD FILM" Set

## Goal

Add a second set of 5 fun, original film filters to the Pola app.  
Name the pack **"Weird Film"** (displayed in the UI as a section header above the new cells, keeping the existing "Film" filters in their own section).

---

## Existing Architecture (do not change)

- Filters live in `pola/pola/Views/FiltersView.swift`.
- Each filter is a case in `FilmFilterEffect` enum with a `apply(to:) -> UIImage` method that chains CIFilters.
- The `FilmFilter` struct holds `(name, color, imageName, effect)`.
- All filters are listed in the `filmFilters` array and rendered by `FiltersView`.
- `PolaroidEntry.filterName` stores the chosen filter's `name` string.
- The Metal file `pola/pola/Others/PolaroidKernels.metal` exists but is empty — Metal kernels must be added there and wired up via `CIKernel` / `CIColorKernel` / `CIWarpKernel`.

---

## New Filters to Implement

Implement exactly these 5 filters. Each entry includes: the display name (Icelandic-style made-up word), an accent color, the visual concept, and how to build it technically.

---

### 1. LÖMUR — Thermal Camera
**Accent color:** `Color(red: 1.0, green: 0.45, blue: 0.0)` (deep orange)  
**Look:** False-color thermal imaging — hot zones map to white/yellow, cold zones to deep blue/purple.  
**How to build (Metal CIColorKernel):**
```metal
// In PolaroidKernels.metal
// Reads luminance, maps it through a thermal palette:
// dark (0.0–0.3) → blue-purple, mid (0.3–0.6) → green, bright (0.6–0.8) → yellow, peak (0.8–1.0) → white
kernel vec4 thermalKernel(sampler image) {
    vec4 px = sample(image, samplerCoord(image));
    float lum = dot(px.rgb, vec3(0.299, 0.587, 0.114));
    vec3 col;
    if (lum < 0.25)      col = mix(vec3(0.05, 0.0, 0.3),  vec3(0.0, 0.3, 0.9),   lum / 0.25);
    else if (lum < 0.5)  col = mix(vec3(0.0, 0.3, 0.9),   vec3(0.0, 0.85, 0.3),  (lum - 0.25) / 0.25);
    else if (lum < 0.75) col = mix(vec3(0.0, 0.85, 0.3),  vec3(1.0, 0.9, 0.0),   (lum - 0.5) / 0.25);
    else                 col = mix(vec3(1.0, 0.9, 0.0),    vec3(1.0, 1.0, 1.0),   (lum - 0.75) / 0.25);
    return vec4(col, px.a);
}
```
Chain after `CIPhotoEffectMono` for a cleaner luminance base, then apply the kernel, then light vignette (strength 0.8).

---

### 2. DREKI — Infrared Film
**Accent color:** `Color(red: 0.95, green: 0.85, blue: 0.90)` (pink-white)  
**Look:** Wood Woodland IR film — foliage goes bright white/pink, sky turns dark, skin glows.  
**How to build (CIFilters only, no Metal):**
1. `CIColorMatrix`: heavily boost green channel into red (R = 0.1R + 1.2G, G = 0.4G, B = 0.5B + 0.3G) to simulate chlorophyll reflectance.
2. `CIColorControls`: saturation 0.3, contrast 1.15.
3. `CIPhotoEffectFade`: intensity ~0.5 blended back via `CISourceOverCompositing` for a pinkish tinge.
4. `CIVignette`: strength 1.1, radius 2.0.
5. Lift blacks with `CIColorMatrix` bias 0.05 for the characteristic washed look.

---

### 3. SKRÍM — Horror VHS
**Accent color:** `Color(red: 0.15, green: 0.75, blue: 0.35)` (phosphor green)  
**Look:** Degraded VHS tape — strong green/yellow cast, heavy scan-line noise, color bleed.  
**How to build (Metal CIKernel for scan lines + CIFilters for color):**
```metal
// Scan-line + chroma-shift kernel (CIKernel, not CIColorKernel, to access destination coord)
kernel vec4 vhsKernel(sampler image, float time) {
    vec2 coord = destCoord();
    vec2 size  = samplerExtent(image).zw;
    // Horizontal chroma bleed: offset R left, B right by a few pixels
    float bleed = 3.0;
    vec4 px  = sample(image, samplerTransform(image, coord));
    vec4 pxR = sample(image, samplerTransform(image, coord + vec2(-bleed, 0)));
    vec4 pxB = sample(image, samplerTransform(image, coord + vec2( bleed, 0)));
    vec4 mixed = vec4(pxR.r, px.g, pxB.b, px.a);
    // Scan lines: every other row dims by 30%
    float scanline = mod(floor(coord.y), 2.0) < 1.0 ? 0.70 : 1.0;
    return mixed * vec4(vec3(scanline), 1.0);
}
```
Color grading: `CITemperatureAndTint` with a strong green-tint push (`inputTargetNeutral` y ≈ -80), `CIColorControls` saturation 1.3, contrast 0.95, brightness -0.05. Add film grain (grainContrast 1.4). No vignette — instead add a subtle `CIGloom` effect (radius 5, intensity 0.4).

---

### 4. FROSINN — Cyanotype / Blueprint
**Accent color:** `Color(red: 0.1, green: 0.35, blue: 0.75)` (blueprint blue)  
**Look:** 19th-century cyanotype print — monochrome deep Prussian blue on off-white, zero grain.  
**How to build (Metal CIColorKernel):**
```metal
kernel vec4 cyanotypeKernel(sampler image) {
    vec4 px  = sample(image, samplerCoord(image));
    float lum = dot(px.rgb, vec3(0.299, 0.587, 0.114));
    // Invert and remap into Prussian blue ↔ off-white
    float t = 1.0 - lum;
    // paper white  = (0.94, 0.96, 0.90), prussian blue = (0.03, 0.19, 0.42)
    vec3 paper = vec3(0.94, 0.96, 0.90);
    vec3 blue  = vec3(0.03, 0.19, 0.42);
    vec3 col   = mix(paper, blue, t);
    return vec4(col, px.a);
}
```
Apply to the luminance of `CIPhotoEffectMono` output. Then `CIColorControls` contrast 1.05, no grain, no vignette (cyanotypes have uniform exposure).

---

### 5. NÓTT — Lo-Fi Night Vision
**Accent color:** `Color(red: 0.18, green: 0.88, blue: 0.42)` (night-vision green)  
**Look:** Generation-1 night-vision goggles — monochrome bright green phosphor, heavy noise, blooming on highlights.  
**How to build (Metal CIKernel + CIFilters):**
```metal
// Phosphor bloom + noise kernel
kernel vec4 nightVisionKernel(sampler image) {
    vec4 px  = sample(image, samplerCoord(image));
    float lum = dot(px.rgb, vec3(0.299, 0.587, 0.114));
    // Remap to bright green phosphor
    vec3 phosphor = vec3(0.0, lum * 1.15, 0.0);
    // Clip and bloom highlights above 0.8
    float bloom = max(0.0, lum - 0.78) * 3.5;
    phosphor = clamp(phosphor + vec3(0.0, bloom, bloom * 0.3), 0.0, 1.0);
    return vec4(phosphor, px.a);
}
```
After the kernel: heavy grain (grainContrast 1.6, use `CISoftLightBlendMode`), `CIVignette` strength 2.0 radius 1.5, no shadow lift (phosphor tubes have deep blacks).

---

## Wiring the Metal Kernels

For each Metal-based effect, compile the kernel at filter init time and cache it:

```swift
// Example pattern for a CIColorKernel
private static let thermalKernel: CIColorKernel? = {
    // The kernel function name must match exactly what's in PolaroidKernels.metal
    CIColorKernel(functionName: "thermalKernel",
                  fromMetalLibraryData: PolaroidKernels.data)
}()
```

Add a `PolaroidKernels` helper (a new Swift file or an extension in FiltersView.swift) that loads the compiled `.metallib` from the main bundle:

```swift
enum PolaroidKernels {
    static let data: Data = {
        let url = Bundle.main.url(forResource: "default", withExtension: "metallib")!
        return try! Data(contentsOf: url)
    }()
}
```

To apply a `CIColorKernel`:
```swift
kernel.apply(extent: input.extent,
             roiCallback: { _, rect in rect },
             arguments: [input])
```

For a `CIKernel` (with `destCoord()`), use:
```swift
kernel.apply(extent: input.extent,
             roiCallback: { _, rect in rect },
             arguments: [input as Any, 0.0 as Any])  // pass time=0 for static
```

---

## FiltersView Changes

1. Add a new array `let weirdFilters: [FilmFilter] = [...]` next to `filmFilters`.
2. In `FiltersView.body`, add a second `LazyVGrid` section with a "Weird Film" header above it, matching the style of the existing grid.
3. In `generatePreviews()`, loop over `weirdFilters` as well.
4. All new filters are premium-gated the same way as the existing ones.

---

## Naming Convention

Keep the Icelandic-ish made-up word naming style. Do not use real Icelandic words — just evocative consonant clusters with accented characters to fit the existing FLÄRN / SOLVA / BRÖKK aesthetic.

---

## iOS 18 Compatibility

- `CIColorKernel(functionName:fromMetalLibraryData:)` is available on iOS 15+. ✅  
- `CIKernel(functionName:fromMetalLibraryData:)` is available on iOS 12+. ✅  
- All CIFilters used (`CIColorMatrix`, `CITemperatureAndTint`, `CIColorControls`, `CIVignette`, `CIGloom`, `CISoftLightBlendMode`, `CIPhotoEffectMono`) are available on iOS 18.0. ✅  
- Do **not** use any API requiring iOS 26.

---

## What NOT to do

- Do not modify `PolaroidEntry` or `PhotoStore` — `filterName` already stores filter names as strings.
- Do not change the existing `filmFilters` array or any existing `FilmFilterEffect` cases.
- Do not add a new Swift package dependency — use only `CoreImage`, `MetalKit`, and built-in CIFilters.
- Do not add comments explaining *what* the code does — only add one if the *why* is non-obvious.
