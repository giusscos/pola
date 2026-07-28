# Pola for Android — Full Development Brief

## What is Pola?

Pola is a Polaroid-style instant camera app. Users take photos or videos, which are saved as "polaroids" — entries with a white frame, caption, back text, location, and an analog film filter applied. Photos go through a "development" animation before becoming viewable.

---

## Tech Stack

| Concern | Library |
|---|---|
| Language | Kotlin |
| UI | Jetpack Compose |
| Architecture | MVVM — ViewModel + StateFlow |
| Database | Room |
| Camera | CameraX |
| Image filters | GPUImage for Android (`jp.co.cyberagent.android:gpuimage:2.1.0`) |
| Location | `FusedLocationProviderClient` (play-services-location) |
| In-app purchases | Google Play Billing Library (`billing-ktx`) |
| Preferences | DataStore (Preferences) |
| Map | Google Maps Compose or OSMdroid |
| Min SDK | API 26 (Android 8.0) |

### Gradle dependencies

```kotlin
// Camera
implementation("androidx.camera:camera-camera2:1.3.x")
implementation("androidx.camera:camera-lifecycle:1.3.x")
implementation("androidx.camera:camera-view:1.3.x")

// Database
implementation("androidx.room:room-runtime:2.6.x")
implementation("androidx.room:room-ktx:2.6.x")
ksp("androidx.room:room-compiler:2.6.x")

// Location
implementation("com.google.android.gms:play-services-location:21.x")

// Filters
implementation("jp.co.cyberagent.android:gpuimage:2.1.0")

// In-app purchases
implementation("com.android.billingclient:billing-ktx:6.x")

// Preferences
implementation("androidx.datastore:datastore-preferences:1.0.x")

// Maps
implementation("com.google.maps.android:maps-compose:4.x")
```

---

## Data Model

```kotlin
@Entity(tableName = "polaroid_entries")
data class PolaroidEntry(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val imageFilename: String,        // JPEG stored as file in app's files dir
    val videoFilename: String? = null,
    val isTimelapse: Boolean = false,
    val caption: String = "",
    val backText: String = "",
    val showMap: Boolean = true,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val developmentProgress: Double = 0.0,  // 0.0–1.0, animates to 1.0 over ~30s
    val timestamp: Long = System.currentTimeMillis(),
    val filterName: String? = null,
    val packName: String? = null,
    val packColorHex: String? = null
)
```

File storage:

- Images: `{filesDir}/{uuid}.jpg`
- Videos: `{filesDir}/{uuid}.mp4`
- Room stores filename references only — no blobs

---

## Filters

There are 10 analog film filters in two groups.

### Film Pack

| ID | Display name | Description |
|---|---|---|
| `chrome` | FLÄRN | Kodachrome pushed contrast |
| `warm` | SOLVA | Warm analog Ektar-like |
| `sepia` | BRÖKK | Heavy sepia fade — old Polaroid SX-70 |
| `cool` | VYLUR | Cross-processed cyan/purple cast |
| `noir` | GRÅLT | Silver-gelatin B&W with heavy grain |

### Weird Film Pack

| ID | Display name | Description |
|---|---|---|
| `lomur` | LÖMUR | False-color thermal imaging |
| `dreki` | DREKI | Infrared film |
| `skrim` | SKRÍM | Horror VHS with scanlines |
| `frosinn` | FROSINN | Cyanotype / blueprint |
| `nott` | NÓTT | Lo-fi night vision green phosphor |

### Filter pipeline

Each filter runs these steps in order:

1. `colorGraded()` — base color grade
2. Shadow lift (if applicable) — lift blacks using color matrix
3. Film grain (if applicable) — noise blended in soft-light mode
4. Vignette (if applicable) — darken edges
5. Gloom (if applicable — only SKRÍM) — bloom on highlights

### Per-filter parameters

| Filter | Shadow lift | Grain contrast | Vignette strength | Vignette radius | Gloom |
|---|---|---|---|---|---|
| FLÄRN | 0.04 | 0.75 | 1.2 | 1.75 | — |
| SOLVA | 0.04 | 0.65 | 0.9 | 1.75 | — |
| BRÖKK | 0.07 | 0.80 | 1.4 | 1.75 | — |
| VYLUR | 0.03 | 0.72 | 1.2 | 1.75 | — |
| GRÅLT | 0.0 | 1.10 | 1.8 | 1.75 | — |
| LÖMUR | — | — | 0.8 | 1.75 | — |
| DREKI | — | — | — | — | — |
| SKRÍM | — | 1.40 | — | — | radius 5.0, intensity 0.4 |
| FROSINN | — | — | — | — | — |
| NÓTT | — | 1.60 | 2.0 | 1.5 | — |

### Color grade math

**FLÄRN (chrome)**
```
1. Apply Chrome photo effect (boost contrast, slight desaturation)
2. Contrast ×1.08, Saturation ×1.06
```

**SOLVA (warm)**
```
1. Temperature shift: neutral 6500K → target 5000K, tint +20
2. Saturation ×0.92, Brightness +0.03
```

**BRÖKK (sepia)**
```
1. Sepia tone at intensity 0.88
2. Contrast ×0.90
```

**VYLUR (cool / cross-process)**
```
1. Color matrix: R×0.82, G×0.94, B×1.28
2. Saturation ×1.12
```

**GRÅLT (noir)**
```
1. Desaturate to B&W
2. Contrast ×1.18
```

**DREKI (infrared)**
```
1. Color matrix remap:
   inputR = [0.1, 1.2, 0.3]
   inputG = [0,   0.4, 0  ]
   inputB = [0,   0,   0.5]
2. Saturation ×0.3, Contrast ×1.15
3. Blend 50% with a faded version (dissolve)
4. Vignette: strength 1.1, radius 2.0
5. Lift blacks by 0.05
```

**SKRÍM (VHS)**
```
1. Temperature: neutral 6500K → target 6500K, tint -80 (purple cast)
2. Saturation ×1.3, Contrast ×0.95, Brightness -0.05
3. Apply VHS scanline GLSL kernel (see below)
```

**FROSINN (cyanotype)**
```
1. Convert to grayscale
2. Apply cyanotype GLSL kernel (see below)
3. Contrast ×1.05
```

**NÓTT (night vision)**
```
1. Apply night vision GLSL kernel (see below)
```

**LÖMUR (thermal)**
```
1. Convert to grayscale
2. Apply thermal GLSL kernel (see below)
```

### Custom GLSL kernels

```glsl
// Thermal — LÖMUR
vec4 thermalKernel(vec4 s) {
    float lum = dot(s.rgb, vec3(0.299, 0.587, 0.114));
    vec3 col;
    if (lum < 0.25)      col = mix(vec3(0.05,0.0,0.3),  vec3(0.0,0.3,0.9),  lum/0.25);
    else if (lum < 0.5)  col = mix(vec3(0.0,0.3,0.9),   vec3(0.0,0.85,0.3), (lum-0.25)/0.25);
    else if (lum < 0.75) col = mix(vec3(0.0,0.85,0.3),  vec3(1.0,0.9,0.0),  (lum-0.5)/0.25);
    else                 col = mix(vec3(1.0,0.9,0.0),    vec3(1.0,1.0,1.0),  (lum-0.75)/0.25);
    return vec4(col, s.a);
}

// Cyanotype — FROSINN
vec4 cyanotypeKernel(vec4 s) {
    float lum = dot(s.rgb, vec3(0.299, 0.587, 0.114));
    float t = 1.0 - lum;
    vec3 paper = vec3(0.94, 0.96, 0.90);
    vec3 blue  = vec3(0.03, 0.19, 0.42);
    vec3 col   = mix(paper, blue, t);
    return vec4(col, s.a);
}

// Night vision — NÓTT
vec4 nightVisionKernel(vec4 s) {
    float lum = dot(s.rgb, vec3(0.299, 0.587, 0.114));
    float bloom = max(0.0, lum - 0.78) * 3.5;
    vec3 phosphor = vec3(0.0, lum * 1.15, 0.0);
    phosphor = clamp(phosphor + vec3(0.0, bloom, bloom * 0.3), 0.0, 1.0);
    return vec4(phosphor, s.a);
}

// VHS scanline — SKRÍM (needs sampler with coordinate access)
vec4 vhsKernel(sampler2D tex, vec2 coord, vec2 texSize) {
    float bleed = 3.0;
    vec4 px  = texture(tex, coord);
    vec4 pxR = texture(tex, coord + vec2(-bleed / texSize.x, 0.0));
    vec4 pxB = texture(tex, coord + vec2( bleed / texSize.x, 0.0));
    vec4 mixed = vec4(pxR.r, px.g, pxB.b, px.a);
    float scanline = mod(floor(coord.y * texSize.y), 2.0) < 1.0 ? 0.70 : 1.0;
    return mixed * vec4(vec3(scanline), 1.0);
}
```

### Film grain implementation

```
1. Generate a random noise Bitmap the same size as the image
2. Desaturate it to grayscale
3. Adjust contrast by the grainContrast value for the active filter
4. Blend it over the image using Soft Light blend mode
```

### Shadow lift / fade film

```
Applies a linear lift to all channels:
  newColor = oldColor * (1.0 - lift) + lift
This raises blacks to a dark gray, simulating faded analog film.
```

> Run all filter operations on `Dispatchers.Default`, never on the main thread.

---

## Screens & Features

### 1. Camera Screen (main screen)

- Full-screen CameraX preview at 4:3 aspect ratio
- Three modes switchable via a tab selector: **PHOTO**, **VIDEO**, **TIME LAPSE**
- **Top bar:** Settings gear | Flashlight toggle | Timer selector (0 / 3 / 5 / 10 s) | Mic toggle (video) or Timelapse settings (timelapse) | Flip camera
- **Bottom bar:** Library thumbnail (last photo taken) | Shutter button | Film filter button
- **Filter strip:** horizontal scroll of filter name badges, selectable
- **Pack/frame color strip:** horizontal scroll of colored circle badges
- **Zoom controls:** shown when device has multiple focal lengths (0.5x, 1x, 2x, 3x)
- After capturing a photo: show the Polaroid print animation, then the caption input card
- Front camera mirroring support (toggleable in Settings)

### 2. Polaroid Print Animation

- Full-screen overlay shown immediately after capture
- White Polaroid frame slides up from the bottom of the screen
- Photo "develops" — starts blurred and dark, clears over ~8 seconds as `developmentProgress` approaches 1.0
- Caption appears below the image inside the frame
- Tap to dismiss early

### 3. Library Screen

- Grid of Polaroid thumbnails (2 or 3 columns via `LazyVerticalGrid`)
- Each cell: photo inside a white Polaroid frame with caption beneath
- Entries still developing show a blurred overlay proportional to `developmentProgress`
- Tap → Polaroid detail view (zoom/shared-element transition)
- Long press → select mode (multi-select for delete and share)
- Search bar at the top — searches `caption` and `backText` fields

### 4. Polaroid Detail View

- Full-size Polaroid showing the photo and caption on the front
- Tap/swipe → flip animation reveals the back side: `backText` + a map pin at the saved coordinate (if available)
- Edit button → opens an edit sheet for caption and back text
- Share and delete actions in the toolbar
- Swipe left/right to navigate between entries

### 5. Filters Sheet (bottom sheet)

- Two sections: **Film** and **Weird Film**
- 3-column grid of filter preview thumbnails
- Non-premium users see a padlock overlay on all filters
- "Original" option always shown first in the Film section
- Tapping a locked filter dismisses the sheet and opens the Paywall

### 6. Settings Screen

- Premium status indicator and upgrade button
- Language override: English, German, Spanish, French, Italian
- Toggle: Print animation enabled
- Toggle: Caption prompt after each shot
- Toggle: Front camera mirroring
- Toggle: Watermark on exported photos
- Toggle: Audio recording on videos
- Timelapse: interval (seconds), duration (seconds), save-as-video toggle
- Restore purchases button

### 7. Paywall / Premium Screen

- Three products displayed with price from Play Store:
  - `com.pola.premium.monthly`
  - `com.pola.premium.yearly`
  - `com.pola.premium.lifetime`
- Restore purchases button
- List of premium benefits: all 10 filters, all pack colors, watermark removal

### 8. Onboarding Screen

- Shown on first launch only
- Explains the app concept with illustrations
- Requests camera and location permissions
- "Get Started" button writes a flag to DataStore so it never shows again

---

## Camera Modes

### Photo mode

```
Tap shutter → capture image via CameraX → apply selected filter → 
save JPEG to disk → insert PolaroidEntry into Room → show print animation
```

### Video mode

```
Tap shutter → start recording → tap again to stop → 
extract thumbnail frame → apply filter to thumbnail → 
save video file to disk → save PolaroidEntry → show print animation
```

Mic toggle in the toolbar enables/disables audio track.

### Timelapse mode

```
Tap shutter → capture one photo every N seconds for M total seconds
→ each frame saved individually as a PolaroidEntry, OR
   all frames compiled into an MP4 (user preference)
→ progress ring animates around shutter button between shots
```

Timelapse settings: interval (seconds between shots), duration (total seconds), save-as-video flag.

---

## Development Progress

New entries start with `developmentProgress = 0.0`.

- Launch a coroutine on insert that updates the value from 0.0 → 1.0 over 30 seconds, writing each step back to Room.
- While developing, show a dark/blurred overlay in the library and detail view that fades out as `developmentProgress` increases.
- If the app is killed and relaunched, read the current `developmentProgress` from Room and resume the animation from where it left off.

---

## Pola Pack Colors (frame tinting)

When a pack color is selected, tint the white Polaroid border with that color.

| Name | Hex |
|---|---|
| FLÄRN | `#F2C71F` |
| SOLVA | `#F5B88A` |
| BRÖKK | `#C76E38` |
| VYLUR | `#AE45D1` |
| GRÅLT | `#474747` |

---

## Premium Gating

| Feature | Free | Premium |
|---|---|---|
| All 10 filters | Locked | Unlocked |
| Pack frame colors | Locked | Unlocked |
| Watermark on exports | Always shown | Removable |
| Photo / video capture | Unlimited | Unlimited |

**PremiumManager** is a singleton ViewModel backed by Google Play Billing:

- On launch: query `queryPurchasesAsync` to restore entitlement state
- After purchase: verify and persist to DataStore
- Products: `monthly` subscription, `yearly` subscription, `lifetime` one-time purchase
- Cache `isPremium: Boolean` in DataStore so the value survives restarts without a network call

---

## Localization

Support five locales: **en**, **de**, **es**, **fr**, **it**.

All user-visible strings go in `res/values[-locale]/strings.xml`. Never hardcode strings in Compose code.

---

## Architecture Notes

- Use Kotlin `Flow` and coroutines throughout — no RxJava.
- Use safe calls (`?.`) and the Elvis operator (`?:`) — no `!!` force-unwrap.
- Repository layer sits between ViewModels and Room DAOs.
- One ViewModel per screen; share state via the Repository, not between ViewModels directly.
- Filter application always runs on `Dispatchers.Default`.

---

## Recommended Implementation Order

| Step | What to build |
|---|---|
| 1 | Room DB: `PolaroidEntry` entity, DAO, Repository |
| 2 | Library screen: `LazyVerticalGrid` showing saved entries |
| 3 | CameraX: preview + photo capture in Photo mode |
| 4 | Filter pipeline: implement all 10 filters, test each independently |
| 5 | Print animation screen |
| 6 | Polaroid detail view + flip animation |
| 7 | Video recording mode |
| 8 | Timelapse mode |
| 9 | Settings screen + DataStore preferences |
| 10 | Onboarding screen + permission flow |
| 11 | Search in library |
| 12 | Google Play Billing + PremiumManager + Paywall screen |
| 13 | Localization (all 5 locales) |
