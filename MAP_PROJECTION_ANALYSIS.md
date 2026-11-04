# Map Projection Analysis — A/B Protocol Test

**Date:** 2026-11-03
**Status:** Proven. Supersedes the earlier `MAP_OVERLAP_ANALYSIS.md` plan. No code was edited during this investigation.

## TL;DR / Conclusion

> **The server's `isometric=true` output (B) is the one that matches D2R's automap projection.**
> The `rotate=true` parameter (A) is **ignored by the server** — A is just an unrotated top-down render.
> To get a D2R-style map, the client must request `isometric=true`, and it must then **stop applying its own legacy +45°/y-squash transform** (`findNewPos`) to the player position, because the image arrives already pre-rotated.

---

## 1. A/B Test Setup

Single decisive test against the local `d2-mapserver` (port 3002), identical seed/difficulty/level:

| | **A** | **B** |
|---|---|---|
| URL suffix | `...&edge=true&rotate=true` | `...&edge=true&isometric=true` |
| Full URL | `http://localhost:3002/v1/map/4213276686/0/1/image?edge=true&rotate=true` | `http://localhost:3002/v1/map/4213276686/0/1/image?edge=true&isometric=true` |
| Seed / difficulty / level | 4213276686 / 0 / 1 | 4213276686 / 0 / 1 |

Artifacts saved under `C:\Users\zhang\AppData\Local\Temp\opencode\abtest\`:
`A_rotate.png`, `B_isometric.png`, plus full header dumps (`*.headers.txt`) and `pixel_analysis.ps1`.

### Results

| Metric | **A** (`rotate=true`) | **B** (`isometric=true`) |
|---|---|---|
| PNG dimensions | 750 × 724 px | 374 × 190 px |
| File size | 4,002 B | 11,105 B |
| Opaque pixels | 7,372 | 6,165 |
| Content bounding box | (292,322)–(599,553) | (0,0)–(373,189) |
| Content size | **308 × 232** (top-down rectangle) | **374 × 190** (fills canvas = trimmed iso diamond) |
| Aspect ratio of content | 1.33 : 1 | **≈ 1.97 : 1 ≈ 2:1** |

### Response headers (identical set for A and B)

```
leftTrimmed=0   topTrimmed=0
offsetx=5680    offsety=4320
mapwidth=280    mapheight=200
waypoint=119,94 serverScale=2
```

**Notably absent from this build:** `prerotated`, `version`, `originalwidth`, `originalheight`. (See §5 — this matters for the client.)

---

## 2. Numerical Confirmation That B = isometric(A)

`pixel_analysis.ps1` measured the opaque content bounding boxes and computed what A's top-down rectangle would become under the server's isometric transform:

- **A** content = a top-down rectangle of **308 × 232**.
- Predicted iso output for that rectangle (rotate45° + squash y×0.5): **W ≈ 381.8, H ≈ 190.9**.
- **B** actual content = **374 × 190**.

The height matches within ~1 px; the width is ~2 % smaller only because the real map's corners are irregular (not a perfect rectangle). This confirms **B is exactly A's map content run through `makeIsometric`**, not a different level or stitched result.

### Why B must be 2:1 regardless of input

The transform in `D:\d2-mapserver\src\map\makeIsometric.ts` (lines 16–20) is applied in this order to the canvas context:

```ts
ctx2.translate(hypot / 2, hypot / 2);
ctx2.scale(1, 0.5);                 // squash vertically by half
ctx2.rotate((45 * Math.PI) / 180);  // rotate 45°
ctx2.translate(-(mapWidth / 2), -(mapHeight / 2));
```

Because the context matrix is `translate · scale(1,0.5) · rotate45`, a point is effectively **rotated 45° first, then squashed vertically by ½**. For *any* input rectangle this yields a diamond whose bounding box has an aspect ratio of exactly **2:1** — which is precisely D2R's automap projection (a 2:1 dimetric/isometric look). B = 374/190 ≈ 1.97 confirms it.

---

## 3. Server Pipeline Trace (why A is top-down, why B is iso)

Traced end-to-end in `D:\d2-mapserver`:

- **`src/server/routes.ts`** — reads only `verbose`, `trim`, `isometric`, `edge`, `wallthickness`, `serverScale` from the query string. It does **not** read `rotate`, `noStitch`, or client-sent `padding`; padding is hardcoded to `150` (line 32). Image cache is keyed by a flag-encoded filename under `./cache/image_*.json`.
- **`src/map/generateMapImage.ts`** — outdoor-stitch branch first (`getOutdoorConnectedMapIds`). For `mapid=1` there is no case in that function → **no stitching**, single level. Then:
  - line 24–26: `if (reqConfig.isometric) levelImage = await makeIsometric(levelImage)` — runs **after** `generatePNG`, **before** the final trim.
  - line 28–34: optional right/bottom trim, recording `leftTrimmed`/`topTrimmed`.
- **`src/map/generatePNG.ts`** — canvas sized as `size*scale + 2*padding`; right/bottom-only trim (line 49); calls `drawWatermark` (line 52).
- **`src/map/drawing/drawWatermark.ts`** — line 16 unconditionally creates a canvas **+20 px taller** even when the watermark is disabled. This accounts for A's extra bottom strip.
- **`src/types/RequestConfig.ts`** — lines 54–56 clamp `serverScale` to **[2, 10]** (so "request scale 1" as a fix is not possible).

**Consequence:** A's "rotate" was never applied server-side; A is simply the unrotated top-down render. The only difference between A and B is the `makeIsometric` step plus trim — **not** stitching or level selection (both are single-level mapid=1).

> Minor observation: A's 724 px height slightly exceeds a naive theoretical max (~700 canvas + 20 watermark = 720). Pixel analysis resolved this as non-material: A's real opaque content is only the small centered 308×232 block; the rest of the large canvas is empty padding plus the watermark strip. The few extra pixels do not affect any conclusion (possible stale cache/process, but irrelevant here).

---

## 4. Which Output Matches D2R?

**B (`isometric=true`).** It is a 2:1 isometric diamond — the same walls and the same yellow waypoint/exit marker as A, just projected into D2R's automap orientation. A (top-down square) does not match.

---

## 5. Minimum Client Implications

The client today assumes it receives a **top-down** image and applies its own projection to place the player dot. Switching to `isometric=true` breaks that assumption unless these are addressed.

### 5.1 The legacy transform that must be skipped for pre-rotated images

`D:\d2r-mapview\src\ui\helper.ahk`, `findNewPos` (lines 13–19):

```ahk
findNewPos(xPosDot, yPosDot, centerX, centerY, RWidth, RHeight, scale) {
    newAngle := findAngle(xPosDot, yPosDot, centerX, centerY) + 45   ; legacy +45° rotation
    distance := getDistanceFromCoords(xPosDot, yPosDot, centerX, centerY) * scale
    newPos := getPosFromAngle((RWidth/2),(RHeight/2),distance,newAngle)
    newPos["y"] := (RHeight/2) + ((RHeight/2) - newPos["y"]) / 2     ; legacy y-squash ×½
    return newPos
}
```

This is the client-side re-implementation of exactly the rotate45°+squash(0.5) that `makeIsometric` already performs server-side. It is called **unconditionally** at:

- `D:\d2r-mapview\src\ui\map\MapGUIs.ahk` line 131
- `D:\d2r-mapview\src\ui\map\MapGUIs.ahk` line 224

(the `transformPosition(...)` alternatives at lines 130 and 225 are commented out.)

**If the image is already isometric, running `findNewPos` again double-transforms the player position → the dot lands in the wrong place.** So for pre-rotated images this legacy +45°/squash must be skipped and replaced with a direct linear mapping of game coords → iso-image pixels.

### 5.2 The `prerotated` / `serverisv10` branches — they exist but are dead

In `D:\d2r-mapview\src\types\MapImage.ahk`:

- line 22: `prerotated := ""` (default)
- line 139: `case "prerotated": prerotated := convertToBool(field[2])` — parsed from the response header
- lines 152–158: sticky logic — if `prerotated` was ever true, set local `serverisv10 := true`; and if `serverisv10`, force `prerotated := true` for all subsequent requests
- line 182: `this.prerotated := prerotated` (stored on the object)

**But a full-repo grep shows `prerotated` appears *only* in `MapImage.ahk`. It is never read by any rendering/placement code.** There is no branch anywhere that says "if pre-rotated, skip `findNewPos`." So:

1. The gating branch **does not exist yet** and must be added (e.g., in `MapGUIs.ahk`, choose between the legacy `findNewPos` path and a direct-mapping path based on whether the image is pre-rotated).
2. This server build emits **no `prerotated` header**, so the sticky logic at lines 152–158 never triggers — the client currently has no way to learn from headers alone that an image arrived pre-rotated.

**Minimum fix options (pick one):**
- **(a)** Have the server emit a `prerotated: true` header on isometric responses, so the existing parse/sticky logic in `MapImage.ahk` starts working — then add the missing draw-path branch that consumes it.
- **(b)** Since we control the client and always request `isometric=true`, branch on our own request flag (a local "we asked for iso" boolean) instead of relying on the header, and skip `findNewPos` accordingly.

### 5.3 The URL change itself

`D:\d2r-mapview\src\types\MapImage.ahk` line 38 currently hardcodes:

```ahk
imageUrl := imageUrl . "&rotate=true&showTextLabels=false"
```

The server ignores `rotate`. To get the D2R projection this must become `isometric=true`:

```ahk
imageUrl := imageUrl . "&isometric=true&showTextLabels=false"
```

(Other params on lines 39–41 — `padding=0`, `noStitch=true` — are also ignored by this server build; padding is hardcoded to 150. They are harmless but have no effect.)

### 5.4 Missing size headers affect the center math

`originalWidth`/`originalHeight` (`MapImage.ahk` lines 23–24, parsed at 140–141) default to `""`. This build emits **no** `originalwidth`/`originalheight`, so they stay empty and `(originalWidth/2)` evaluates to `0` in AHK — meaning `findNewPos`'s center is `(0,0)` rather than the true map center. If any center-based placement math is retained after the change, these headers (or an equivalent source of the original top-down size) must be supplied; otherwise use the known `mapwidth`/`mapheight` + `offsetx`/`offsety` already present in every response.

---

## 6. Summary of Required Client Changes (minimum set)

1. **Request iso, not rotate** — `MapImage.ahk:38`: `rotate=true` → `isometric=true`.
2. **Stop double-transforming** — for pre-rotated images, skip the legacy +45°/y-squash in `findNewPos` (`helper.ahk:13–19`, called at `MapGUIs.ahk:131` and `:224`) and use a direct linear game-coord → iso-pixel mapping instead.
3. **Add the missing gate** — there is currently no draw-path branch on `prerotated`; add one (and either make the server emit the `prerotated` header, or branch on the client's own "requested iso" flag).
4. **Fix the center source** — `originalWidth/Height` are empty from this build; supply them or derive the center from `mapwidth/mapheight` + `offsetx/offsety`.

No changes to map generation or memory-reading code are required for the projection itself.

---

## 7. Carry-over (separate task, not done here)

After this analysis: remove the transition diagnostic logging added during the visibility fix from
`D:\d2r-mapview\src\memory\readUI.ahk` and `D:\d2r-mapview\src\mapFunctions.ahk`.
