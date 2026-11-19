# Distance-adaptive prompter typography: research-backed spec (target: 1.0.3)

Status: spec only, no app code. Written 2026-11-19.
Scope: iPhone (front camera, band under the camera) and Mac (panel under the notch).
Rule of the document: every number is tagged **[source]** (cited), **[derived]** (computed here from cited inputs, reproducible) or **[design]** (our choice, unvalidated, must be tuned on device). Anything not tagged is an assumption and listed in section 11.

Binding product rules from the founder, applied throughout:
1. Mac gets BOTH live face-distance measurement (opt-in, with privacy note) AND manual distance presets.
2. Colour order for read / current / upcoming is decided here from the research (section 8).
3. "Constitution": live video must stay clearly perceivable behind the text, yet wherever text overlays video it must have maximum legibility. So the contrast treatment is local (per-line, luminance-aware plates plus a halo), never a full-band dark overlay (section 8.3).
4. Ships as version 1.0.3.

---

## 0. Summary of the model

Text is sized so the lowercase x-height subtends a fixed visual angle at the eye, then limited by what the screen can show and by how far below the lens the eyes may travel.

```
x-height angle      alpha  = 0.40 deg nominal (clamp 0.25 .. 0.60)
font size (pt)      S      = d_mm * tan(alpha) * ppmm / xr
chars per line      cpl    = 4 * xr * tan(theta_h) / tan(alpha)      (independent of distance)
vertical angle/line        = lh * tan(alpha) / xr  (about 1.0 deg per line at alpha 0.4, lh 1.3)
max lines           N      = floor((tan(theta_v) - g0/d) / per_line + 0.5)
```

d = eye-to-screen distance, ppmm = logical points per physical mm, xr = x-height / font size (about 0.526 for SF Pro), g0 = lens-to-top-of-first-line gap, theta_h / theta_v = allowed horizontal half-sweep / vertical angle below the lens.

Two consequences worth knowing before reading on:
- At legible size each text line costs about 1 degree of downward gaze, whatever the distance. Three lines is the comfortable ceiling, five the hard one (section 3).
- A portrait phone cannot show enough characters per line beyond roughly 1.1 m. Adaptive sizing must stop growing there and tell the user (section 6).

---

## 1. Legibility

### 1.1 What the literature says

| Item | Number | Notes | Source |
|---|---|---|---|
| Critical print size (CPS), normal vision | 0.2 deg x-height (12 arcmin); typical estimates 0.15-0.3 deg (9-18 arcmin) | Smallest size that still gives maximum reading speed; not the smallest readable size | Legge & Bigelow overview, https://pmc.ncbi.nlm.nih.gov/articles/PMC3428264/ |
| Max-speed plateau | about 0.2 to 2 deg x-height (12-120 arcmin) | Speed falls sharply below CPS, slowly above 2 deg | same |
| Acuity reserve | CPS about 2x letter acuity (intact central vision); 3.2x for max speed in low vision rules of thumb | Reserve = print size / acuity limit size | https://pmc.ncbi.nlm.nih.gov/articles/PMC9357187/ , https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6181187/ |
| Vehicle-display glance guidance | 20-30 arcmin character height for high legibility | Character height, not x-height; context only | https://www.nhtsa.gov/sites/nhtsa.gov/files/documents/812360_humanfactorsdesignguidance.pdf |
| Characters per line vs display width | 13 characters per line gives 80% of max reading speed | A minimum, not an optimum | Atilgan, Xiong, Legge 2020, https://legge.psych.umn.edu/sites/legge.psych.umn.edu/files/2020-11/Atilgan%20Xiong%20Leggey%202020%20Reconciling%20print-size%20and%20display-size%20constraints%20on%20reading.pdf.pdf |
| Line length, ordinary screens | about 55 chars rated easiest; 100 chars faster than 25 | Not a prompter optimum; prompters trade speed for eye-contact | https://dl.acm.org/doi/10.1006/ijhc.2001.0458 |
| Letter spacing (Chung 2002) | Speed peaks near standard spacing (centre-to-centre 1.16x width of x); more spacing did not help; 2x spacing cost about 25% speed | Standard spacing is the optimum | https://pmc.ncbi.nlm.nih.gov/articles/PMC2729067/ |
| Crowding (Bouma/Pelli) | Critical spacing about 0.5 x eccentricity | Wider spacing reduces crowding but spreads the word across the visual field | https://www.cns.nyu.edu/~msl/courses/2223/Readings/Pelli-NatNeurosci2008.pdf |
| Word spacing | Removing spaces cut reading rate 54% (sentences) / 44% (passages); keep interword gap at least 3.5x interletter gap | Default SF Pro word space already satisfies this; doubling it helps only low-vision readers | https://eprints.bournemouth.ac.uk/24643/5/TextSpacingRevisited_final.pdf |
| Word + line spacing, central vision loss | double word + double line spacing: +26% speed (high contrast) / +46% (low contrast) | Combined effect, macular patients only; do not generalise | https://pmc.ncbi.nlm.nih.gov/articles/PMC3823704/ |
| Bold vs regular | no speed difference (200 students); stroke width 0.72-1.89x normal: no change in foveal speed; extreme thin/thick about -23% | Semibold/bold are both inside the plateau | https://pmc.ncbi.nlm.nih.gov/articles/PMC7093247/ , https://pmc.ncbi.nlm.nih.gov/articles/PMC3642228/ |
| Eye-voice span (reading aloud) | looks about 2-3 words (0.5-1 s) ahead; 7-8 words possible | Show at least a full upcoming phrase | https://pmc.ncbi.nlm.nih.gov/articles/PMC4585246/ |
| Perceptual span | about 14-15 characters right of fixation | Faint upcoming text disrupts reading | https://pmc.ncbi.nlm.nih.gov/articles/PMC3996545/ , https://pmc.ncbi.nlm.nih.gov/articles/PMC6233613/ |

There is no study of x-height for "glance reading while speaking on camera". The target below is therefore an inference: a comfortable margin above CPS.

### 1.2 Target x-height angle

- Nominal alpha = **0.40 deg** (24 arcmin): 2x CPS, inside the plateau, and inside the vertical gaze budget of section 3. **[design]**
- Floor alpha_min = **0.25 deg** (1.25x CPS). Below it the app shows "too far for this screen" (section 6). **[design]**
- Ceiling alpha_max = **0.60 deg**. Larger text only burns the gaze budget (each line costs more degrees) with no reading gain. **[design]**

### 1.3 Formula: font size in points

```
x_phys_mm   = d_mm * tan(alpha)
S_pt        = x_phys_mm * ppmm / xr
```

- ppmm: logical points per physical millimetre (section 2). Reading the physical size from the device rather than assuming 163 ppi is what makes this correct on a mini and a Pro Max alike.
- xr: x-height / pointSize of the exact font instance used. SF Pro Text: 1078/2048 = **0.5264** [source: W3C CSS list archive, https://lists.w3.org/Archives/Public/public-css-archive/2022Sep/0987.html ; the 1086/2048 = 0.530 figure in circulation is within 1%]. SF Pro is variable-optical-size, so at runtime compute `xr = font.xHeight / font.pointSize` for the semibold instance and use 0.526 only as fallback. https://developer.apple.com/documentation/appkit/nsfont/xheight

Inverse (what the user effectively gets for a fixed size): `alpha = atan(S * xr / ppmm / d)`.

Sanity checks with current defaults [derived]:
- iPhone default 34 pt gives alpha 0.40 deg at **42 cm**: the default is already tuned for a handheld selfie arm.
- Mac default 26 pt gives alpha 0.26 deg at 60 cm (close to CPS) and 0.40 deg only at 39 cm. At a normal desk distance the Mac default is too small. This is the largest practical win of adaptive sizing.

### 1.4 Characters per line (distance-independent)

Horizontal half-sweep of the eyes across a line of c characters (average advance about 0.5 em including spaces **[design assumption]**):

```
sweep_half = atan( (c * 0.5 * S / ppmm / 2) / d )
cpl        = 4 * xr * tan(theta_h) / tan(alpha)      (substituting S from 1.3; d cancels)
```

| theta_h (half-sweep) | cpl at alpha 0.30 | 0.40 | 0.55 |
|---|---|---|---|
| 3 deg | 21 | 16 | 12 |
| 4 deg | 28 | 21 | 15 |
| 5 deg | 35 | 26 | 19 |

[derived]. Recommendation: **target 22 characters, min 13, max 30** (about 4 words; sweep about +/-4.2 deg at alpha 0.4). 22 sits above the 13-character 80%-speed floor and keeps the sweep near the 4.1-4.7 deg half-width of the direct-gaze cone for a virtual head (Gamer & Hecht 2007, https://experimental.psychologie.uni-mainz.de/files/2024/06/2007gamer-hecht-gaze.pdf). Honest caveat: no study measures how much horizontal sweep while reading is tolerated; the cone is used as a heuristic. Column is centred under the lens.

### 1.5 Line height

Distance-independent angular cost per line [derived]: `deg_per_line = atan(lh * tan(alpha) / xr)`:

| lh | alpha 0.30 | 0.40 | 0.55 |
|---|---|---|---|
| 1.25 | 0.71 | 0.95 | 1.31 |
| 1.30 | 0.74 | 0.99 | 1.36 |
| 1.35 | 0.77 | 1.03 | 1.41 |

Recommendation: **lh = 1.30** (range 1.25-1.40), a small cut from today's 1.35 to save gaze budget. The only experimental support for bigger spacing is low-vision (section 1.1), so we do not buy gaze degrees for it. **[design]**

### 1.6 Weight, tracking, word spacing

- Weight: keep **semibold (600)**, constant. Reading speed is flat across 0.72-1.89x stroke width; semibold over video also holds up better against a halo. Do NOT make weight adaptive: weight changes alter glyph advances and reflow the paragraph, which makes the user lose the line. **[source + design]**
- Letter spacing: **0 em** (system tracking). Chung 2002 shows standard spacing is optimal and widening does not help. Allowed range 0 to +0.02 em, exposed only as the existing user setting. **[source]**
- Word spacing: default **+0.04 em** because the halo (section 8.3) visually shrinks the gap; the Slattery ratio (gap at least 3.5x interletter gap) is already met by the font default, so this is a halo compensation only. Range 0 to 0.08 em. **[design, unvalidated; A/B on device]**

---

## 2. Device geometry

Physical ppi from Apple tech specs; points from Apple/iOS Resolution tables. `ppmm = ppi / (scale * 25.4)`, with the mini exception below. Sources: https://www.ios-resolution.com/ , https://useyourloaf.com/blog/iphone-17-screen-sizes , https://support.apple.com/en-us/125092 , https://support.apple.com/en-us/126470 , https://iosref.com/res

### 2.1 iPhone

| Family | ppi | Logical size (pt, portrait) | Scale | **ppmm** |
|---|---:|---|---|---:|
| 12 mini, 13 mini | 476 | 375 x 812 | @3x, panel downsampled (about 2.88 px/pt) | **6.507** |
| 12, 12 Pro, 13, 13 Pro, 14, 16e, 17e* | 460 | 390 x 844 | @3x | 6.037 |
| 12 Pro Max, 13 Pro Max, 14 Plus | 458 | 428 x 926 | @3x | 6.010 |
| 14 Pro, 15, 15 Pro, 16 | 460 | 393 x 852 | @3x | 6.037 |
| 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus | 460 | 430 x 932 | @3x | 6.037 |
| 16 Pro, 17, 17 Pro | 460 | 402 x 874 | @3x | 6.037 |
| 16 Pro Max, 17 Pro Max | 460 | 440 x 956 | @3x | 6.037 |
| iPhone Air (named "iPhone Air", not "17 Air") | 460 | 420 x 912 | @3x | 6.037 |
| SE 2, SE 3 | 326 | 375 x 667 | @2x | **6.417** |

*17e listed per the research source; verify against the final Apple spec page. The mini exception: `476 / (2.88 * 25.4) = 6.507`, not `476 / (3 * 25.4)` [derived; https://useyourloaf.com/blog/iphone-13-screen-sizes/].

iOS exposes no physical size API, so ship a model-identifier table with default **6.037** for unknown (future) models. Only four values matter: 6.037 (default), 6.010, 6.507, 6.417. Spread across the range is +/-7%, i.e. below the size-change threshold, so a wrong lookup is cosmetically minor.

### 2.2 MacBook (notch models)

| Model | Native px | ppi | Default looks-like (pt) | **ppmm** | Notch (pt, estimate) |
|---|---|---:|---|---:|---|
| Air 13.6 (M2/M3/M4) | 2560 x 1664 | 224 | 1470 x 956 | **5.064** | about 179 x 32 (AppKit reading on M4 Air) |
| Air 15.3 | 2880 x 1864 | 224 | 1710 x 1107 (one source: 1112) | **5.236** | about 32 high |
| Pro 14.2 | 3024 x 1964 | 254 | 1512 x 982 | **5.000** | about 185 x 32 |
| Pro 16.2 | 3456 x 2234 | 254 | 1728 x 1117 | **5.000** | about 185 x 32 |

Sources: https://www.apple.com/macbook-air/specs/ , https://www.apple.com/macbook-pro/specs/ , https://gauravsharma.com/hardware/apple/mac-screens/ , https://crestnotch.app/macbook-notch-dimensions . Notch sizes are layout estimates, not Apple-published physical values. `ppmm = looks-like width pt / (native px / ppi * 25.4)` [derived].

On macOS do NOT use a table: `ppmm = NSScreen.frame.width / CGDisplayScreenSize(displayID).width` (mm). This follows the user's chosen "scaled" resolution automatically, which a table cannot. Fall back to 5.064 if the reported size is 0 or implausible (<200 mm wide).

### 2.3 Where the lens is relative to the band (g0)

Needed in section 3. Estimates, not measured **[assumption: measure on the physical devices]**:
- iPhone Dynamic Island models: lens centre about 4.8 mm below the top edge (island 37 pt high starting about 11 pt down); first text line top at the island bottom plus a gutter, so **g0 about 4 mm** to the top of the first line.
- Mac notch: lens about 3 mm below the screen top edge; panel content starts at notch bottom (about 32 pt = 6.3 mm) plus the existing 8 pt gutter, so **g0 about 4 mm**. (The code already uses `safeAreaInsets.top + 8`.)

For iPhone models without a Dynamic Island (SE, mini, 12/13/14) the lens sits in the top bezel or notch; g0 is larger (bezel/notch edge to first line), so use **6 mm** for them. **[assumption]**

---

## 3. Eye-line and gaze budget

### 3.1 Evidence

All angles are deviation of the speaker's gaze from the lens, as judged by a viewer.

| Study | Horizontal | Below | Above | Note |
|---|---|---|---|---|
| Chen 2002, "Leveraging eye contact in videoconferencing" | about 1 deg each side | knee near 10 deg; **recommends < 5 deg** | about 1 deg | Strong asymmetry, 16 observers. https://doi.org/10.1145/503376.503386 , https://graphics.stanford.edu/papers/eye_contact/paper.pdf |
| Bell Labs 1969 (via Chen) | 4.5 deg | 5.5 deg | 5.5 deg | Loss-of-contact thresholds, symmetric vertical |
| Gamer & Hecht 2007 | virtual head 4.1-4.7 deg per side; real person 2.0-4.1 per side (8.12 deg full width at 1 m, 3.90 at 5 m) | not measured | not measured | Cone is wider when closer. https://doi.org/10.1037/0096-1523.33.3.705 |
| Horstmann & Linke 2022 | 2.6-3.0 deg per side (Gaussian width) | 3.9-4.3 deg (50% threshold) | 5.1-5.9 deg | Did NOT replicate Chen's below-advantage. https://doi.org/10.1186/s41235-022-00418-1 |
| Gao et al. 2025 | n/a | best-rated gaze at **1.76 deg below**; contact reported at 0-3 deg below | n/a | An optimum, not a cutoff; stills at about 50-60 cm. https://doi.org/10.1167/jov.25.11.8 |
| Bohannon et al. 2013 review | reviews the above | ~10 deg knee / ~5 deg recommendation | ~1 deg | Methods differ across studies. https://doi.org/10.1016/j.displa.2012.10.009 |

Studies disagree (Chen's below-tolerance of about 10 deg versus Horstmann's about 4 deg). So we use two budgets, chosen conservatively:
- **theta_v comfort = 3 deg** (inside Horstmann's 50% line and near Gao's optimum). **[design]**
- **theta_v hard max = 5 deg** (Chen's recommendation). **[source]**
- Horizontal: see 1.4 (heuristic, about +/-4 deg).

### 3.2 Geometry

Angle from the lens to the centre of line k (k = 1 is nearest the lens), line pitch `L = lh * S / ppmm` (mm):

```
y_k       = g0 + (k - 0.5) * L          // mm below lens
theta_k   = atan( y_k / d )
N_max(theta) = floor( (tan(theta) - g0/d) / (lh*tan(alpha)/xr) + 0.5 + 0.05 )
band height  = g0_pad + N * lh * S   (points)
```

[derived; the 0.05 absorbs rounding]. Lines used vs distance, alpha 0.40, lh 1.30, g0 4 mm:

| d (m) | g0 angle | N at 3 deg | N at 4 deg | N at 5 deg |
|---:|---:|---:|---:|---:|
| 0.30 | 0.76 deg | 2 | 3 | 4 |
| 0.40 | 0.57 deg | 3 | 4 | 5 |
| 0.50 | 0.46 deg | 3 | 4 | 5 |
| 0.60 | 0.38 deg | 3 | 4 | 5 |
| 1.00 | 0.23 deg | 3 | 4 | 5 |
| 1.50 | 0.15 deg | 3 | 4 | 5 |

At alpha 0.30 the counts rise to about 4 (3 deg) and 6 (5 deg) [derived].

Decisions:
- **Visible lines N = 3 default, 2 allowed at d < 0.35 m, never more than 5.** The prompt scrolls; N is how many are on screen at once.
- **Reading line = line 1 or 2 of the band** (closest to the lens), upcoming lines below it. Eyes then sit mostly at 0.5-2 deg below the lens, at or inside Gao's optimum, with line 3 as peripheral look-ahead (eye-voice span 2-3 words). **[design]**
- Band height is not a free parameter: derive it from N and S so that the lowest line centre stays under theta_v. The band under the lens must therefore **shrink in height as text grows**; do not let a user-set large band push lines beyond the budget.
- When the user's manual band is taller than the budget, extra lines are still allowed, but fade (opacity ramp to 0.35 over the last line beyond the 5 deg limit) so the eye is not invited there.

---

## 4. Distance estimation on iPhone

### 4.1 Options

| | (a) TrueDepth depth output | (b) Vision + pinhole (recommended) | (c) ARKit face tracking |
|---|---|---|---|
| Concurrent with `AVCaptureMovieFileOutput` | Possible in one session with `.builtInTrueDepthCamera`, depth output and movie output; must test the exact graph. https://developer.apple.com/videos/play/wwdc2022/110429/ | Yes: add an `AVCaptureVideoDataOutput` to the existing session. Per WWDC22 session 110429, video and audio data outputs may deliver alongside movie recording for apps linked on iOS 16+ (verify on the target OS). The app already does this for audio (`audioOutput.setSampleBufferDelegate`) | Not with `AVCaptureMovieFileOutput`. ARKit owns its capture session; a second session can steal the camera. Recording must go through `AVAssetWriter` on `ARFrame.capturedImage`. https://developer.apple.com/videos/play/tech-talks/601/ |
| Format constraints | Depth only on formats where `supportedDepthDataFormats` is non-empty; there is no device-independent table for 4K60/HDR/ProRes plus depth; depth can arrive at a lower rate than video (`activeDepthDataMinFrameDuration`). https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/supporteddepthdataformats | None: runs on whichever format the user chose (CameraEngine already picks `activeFormat` per mode, including 4K and HDR HLG) | ARKit `supportedVideoFormats` only; the user's recording presets would be lost |
| Device coverage | All TrueDepth iPhones; **not iPhone SE** | All iPhones | TrueDepth iPhones |
| Accuracy | Metric, but only if the delivered map is `absolute` accuracy; Apple's depth-photo docs describe TrueDepth as providing depth in metres, the WWDC22 overview describes the default disparity as relative; calibrate on device | About 6-8% 1-sigma uncalibrated (4.2) | Good (anchor transform), but anchor origin is behind the face, not at the eyes |
| Cost to adopt | Changes the capture device type (`.builtInWideAngleCamera` to `.builtInTrueDepthCamera` could narrow the format list) and risks regressions in the recording path that already ships | One output, one Vision request, no change to recording | A rewrite of recording |

**Recommendation: (b) Vision landmarks + pinhole model, with the camera's own intrinsics, no change to the recording path. Fallback chain: (b) with intrinsics, then (b) with `videoFieldOfView`, then the user's stored reading distance / manual preset.** (a) is an optional later calibration aid only; (c) is rejected because it would force the recording rewrite and lose format choices. This is the smallest change that fully works.

### 4.2 Method (b) in detail

1. Add one `AVCaptureVideoDataOutput` to the existing session; set `videoSettings` to a small width (about 640 px) so it does not deliver 4K buffers while recording; `alwaysDiscardsLateVideoFrames = true`; own serial queue. Enable `isCameraIntrinsicMatrixDeliveryEnabled` on its connection before `startRunning` and read `kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix` per frame. https://developer.apple.com/documentation/avfoundation/avcaptureconnection/iscameraintrinsicmatrixdeliveryenabled
2. Run `VNDetectFaceLandmarksRequest` (uses its own detection) at **5 Hz** (every 6th frame at 30 fps); take the largest face. Pupils: `landmarks.leftPupil` / `rightPupil` (optional, normalised inside the face box, so convert to pixels). If pupils are missing use eye-region centroids. https://developer.apple.com/documentation/vision/vnfacelandmarks2d
3. `ipd_px = |pupil_L - pupil_R|`, corrected for head yaw: `ipd_px / cos(yaw)` with yaw from `VNFaceObservation.yaw`; reject frames with |yaw| > 30 deg. IPD is rotation-invariant for roll, so no roll correction.
4. `f_px`: from the intrinsic matrix scaled to the buffer width. Fallback `f_px = W / (2 * tan(hFOV/2))` with `AVCaptureDevice.Format.videoFieldOfView` (horizontal FOV, degrees). https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/videofieldofview
5. `Z = f_px * IPD_mm / ipd_px` with `IPD_mm = 63`. Optical-axis depth, which is also the eye-to-screen distance because the screen is coplanar with the lens (the difference to the true eye-to-line distance, about 4-60 mm sideways, is below 1% beyond 0.4 m).
6. Digital zoom, video stabilisation crops and cinematic modes change the effective field of view; the app must pass the intrinsics of the frame, not of the format. **Verify on device with a tape measure at 0.4 / 0.6 / 1.0 m for each stabilisation mode the app offers.**

### 4.3 Error budget [derived]

IPD prior: 62.1 +/- 3.7 mm across adults (https://applications.emro.who.int/imemrf/J_Ophthalmic_Vision_Res/J_Ophthalmic_Vision_Res_2012_7_3_231_234.pdf), so 1-sigma = **6.0%**, which maps 1:1 onto distance and onto font size (size is proportional to d). Pixel noise for 640 px buffers, hFOV assumed 70 deg (read the real value at runtime):

| d | ipd_px | 1 px error | yaw 10 deg | combined 1-sigma (with IPD 6%) |
|---:|---:|---:|---:|---:|
| 0.4 m | 72 | 1.4% | 1.5% | about 6.3% |
| 0.6 m | 48 | 2.1% | 1.5% | about 6.5% |
| 1.0 m | 29 | 3.5% | 1.5% | about 7.2% |
| 1.5 m | 19 | 5.2% | 1.5% | about 8.1% |
| 2.0 m | 14 | 6.9% | 1.5% | about 9.5% |

Published comparison: a 26-person webcam study with sex-specific mean IPD and a calibrated polynomial reported 3.9-7.3% mean relative error over 20-240 cm (https://www.mdpi.com/2673-9909/5/3/118); a facial-feature method on frontal phone photos reported 26% MAPE (https://link.springer.com/article/10.1007/s00414-023-03078-y). There is no Apple-published accuracy for Vision-based distance. So the estimate is good enough for sizing text (JND-scale errors) and not good enough to display as a number to the user.

Reduce the dominant error (IPD prior) with a personal gain `k` (section 4.5): when the user nudges the size manually while auto is on, store `k = S_user / S_model` (clamped 0.8-1.25) and apply it to all later estimates. That removes the fixed anatomical bias for that person.

### 4.4 Update rate, smoothing, snapping

- Measurement: 5 Hz (200 ms). Distance moves slowly while reading; faster adds battery and thermal cost on top of 4K recording without benefit. **[design]**
- Pre-filter: median of last 5 valid samples (rejects blink and landmark outliers); skip frames where confidence is low, face is smaller than 24 px IPD, or |yaw| > 30 deg.
- Smooth `ln(Z)` (log domain, so a 10% move is the same step at 0.4 m as at 2 m) with a **1 Euro filter** (Casiez, Roussel, Vogel, CHI 2012: https://gery.casiez.net/1euro/ , https://gery.casiez.net/publications/CHI2012-casiez.pdf). Authors' defaults are mincutoff 1 Hz, beta 0, dcutoff 1 Hz. Starting values for this signal: **mincutoff 0.4 Hz, beta 5, dcutoff 1 Hz** (so a deliberate lean-in of about 50%/s opens the cutoff to about 3 Hz while a still reader sits at 0.4 Hz). **[design; tune on device with recorded traces]**
- **Size snapping.** Never apply the continuous value. Work on a geometric grid with ratio **1.10** (about 10% steps; the size change a reader notices without being startled; no cited JND, so tune). A new target is committed only if both hold: `|ln(S_target / S_current)| >= ln(1.10)` continuously for **>= 1.5 s**, and at least **3 s** since the last change. Hysteresis: the commit threshold for a change back is 1.15 (the opposite direction must overshoot more).
- **When to apply.** Prefer the next speech pause of >= 250 ms or the next paragraph break; apply anyway after **4 s** of waiting. Animate 300 ms ease-in-out. Always re-anchor on the **current word** (keep it at the same screen position) so the reader never loses place. The existing `ScriptTokenizer` word indices do not change with size, so only layout is recomputed.
- Never change size while the user is dragging/scrubbing, and never during the first 2 s after a manual size change (the user is in control).

### 4.5 Modes

- **Auto** (default on for new users in 1.0.3 only after the first successful face detection; off if camera permission is denied or no face is seen for 5 s).
- **Fixed** (today's behaviour, fontSize setting).
- Manual change while in Auto = learns `k` (4.3), shows a toast "Auto size adjusted to you", and a long-press resets `k = 1`.
- Dev/Debug builds: auto size is available and shows an optional debug overlay (distance, alpha, S, N). Never gated (global rule).

---

## 5. Mac: distance and camera sharing

### 5.1 Can the prompter use the camera while a call app does?

Yes in general. On macOS, several apps can receive frames from the built-in camera at the same time; Apple's AVCaptureDevice docs discuss other apps sharing the device, and `isInUseByAnotherApplication` only reports that another app is using it, not that capture will fail. https://developer.apple.com/documentation/avfoundation/avcapturedevice and https://developer.apple.com/documentation/avfoundation/avcapturedevice/isinusebyanotherapplication . Cautions, all to be verified by running Zoom/Meet/FaceTime/Teams in both start orders:
- Hold `lockForConfiguration()` only while changing settings; an unnecessary lock can degrade capture in other sharing apps. https://developer.apple.com/documentation/avfoundation/avcapturedevice
- Continuity Camera can make a call app switch to an iPhone; pick the built-in camera in the prompter explicitly and show which camera is used.
- Center Stage reframes the image on supported cameras (12 MP Center Stage on Air M4 and Pro M4): it changes the effective field of view, so absolute distance would be wrong. https://support.apple.com/guide/mac-help/use-the-camera-mchlp2980/mac
- The macOS app currently has no camera code (no `AVCapture` in `macOS/`), so this adds: `NSCameraUsageDescription` and the `com.apple.security.device.camera` entitlement if sandboxed, a new permission prompt, and a review note. https://developer.apple.com/documentation/bundleresources/information-property-list/nscamerausagedescription

### 5.2 Privacy indicator

The built-in camera LED and the green menu-bar dot light whenever any app captures; Apple engineers the LED not to activate without the camera running. https://support.apple.com/en-us/102177 . A prompter-only camera session will therefore also light the indicator, even when the user only sees the prompter. Hence **opt-in only** (default OFF), with this text on the toggle: "Uses the camera briefly and only on this Mac to measure how far you sit, so the text stays readable. No video is saved or sent." Processing in memory, no frame ever stored; show the active-camera name and a one-tap off in the panel.

### 5.3 Field of view on Mac

`AVCaptureDevice.Format.videoFieldOfView` is documented for iOS, iPadOS, Mac Catalyst and tvOS, not native macOS; Apple publishes no horizontal FOV for MacBook cameras (the 122 deg figure belongs to Studio Display). https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/videofieldofview . The format description extension `kCMFormatDescriptionExtension_HorizontalFieldOfView` may be present on some cameras (value in thousandths of a degree). https://developer.apple.com/documentation/coremedia/kcmformatdescriptionextension_horizontalfieldofview . Do not assume it.

### 5.4 Recommendation: relative live mode plus presets

Because FOV is unknown, the Mac live mode is **relative**, which needs no FOV, no IPD prior and no metric distance:

```
S = S_ref * (ipd_ref_px / ipd_px)        // distance is proportional to 1/ipd_px
```

Calibration moment ("Set my distance" button, or implicit: the user adjusts size while Auto is on): store `ipd_ref_px` and the font size the user considers comfortable right then. The first run uses the preset below so there is always a sensible start.

Manual presets (also the fallback whenever live measurement is off, denied, Center Stage is active, or no face for 5 s). Distances are assumptions to be logged anonymously and tuned, see 11:

| Preset | Eye-to-screen | Typical use |
|---|---:|---|
| Close | 45 cm | laptop on a lap/tight desk |
| Desk | 60 cm | default |
| Back | 80 cm | leaning back, external keyboard |
| Standing | 120 cm | standing desk, presenting |

Font size for a preset is the section 1.3 formula with the screen's `ppmm` (section 2.2) and the panel width cap (section 6). A slider in cm (30-150) is the "advanced" version of the same control.

---

## 6. Typical distances and resulting sizes

Use cases (distances are **assumptions**, to be validated with the app's own analytics): handheld selfie 0.35-0.45 m; phone on a desk stand or tripod 0.5-0.7 m; Mac at a desk 0.55-0.75 m; ring light / tripod at 1-2 m.

Model [derived]: alpha 0.40 deg, xr 0.526, lh 1.30, g0 4 mm, target 22 chars max, cap S so that at least 13 characters fit, S_min 20 pt. "S ideal" ignores the width cap, "S used" applies it.

### iPhone 16 Pro, portrait (ppmm 6.037, 402 pt wide, usable 370 pt)

| d (m) | S ideal (pt) | S used (pt) | alpha used (deg) | chars/line | sweep (+/- deg) | lines (3 deg / 5 deg) | Use case |
|---:|---:|---:|---:|---:|---:|---|---|
| 0.30 | 24 | 24 | 0.40 | 22 | 4.2 | 2 / 4 | close selfie |
| 0.40 | 32 | 32 | 0.40 | 22 | 4.2 | 3 / 5 | handheld arm |
| 0.50 | 40 | 40 | 0.40 | 18 | 3.5 | 3 / 5 | desk stand |
| 0.60 | 48 | 48 | 0.40 | 15 | 2.9 | 3 / 5 | desk stand |
| 0.80 | 64 | 57 | 0.36 | 13 | 2.2 | 3 / 5 | tripod |
| 1.00 | 80 | 57 | 0.28 | 13 | 1.8 | 3 / 5 | tripod, limit |
| 1.50 | 120 | 57 | 0.19 | 13 | 1.2 | too far | below CPS, hint |
| 2.00 | 160 | 57 | 0.14 | 13 | 0.9 | too far | below CPS, hint |

Reading: the phone in portrait is a valid prompter out to about 1.1 m (alpha stays above the 0.25 deg floor). Beyond that show "Move closer or use landscape", because at 1.5 m a 13-character column is only readable if alpha stays at 0.19 deg, below critical print size. In landscape the usable width roughly doubles (874 pt), which moves the limit to about 2.4 m [derived].

### MacBook Air 13.6, panel 520 pt (default; usable 488 pt; ppmm 5.064)

| d (m) | S ideal (pt) | S used (pt) | alpha used (deg) | chars/line | sweep (+/- deg) | lines (3 deg / 5 deg) | Use case |
|---:|---:|---:|---:|---:|---:|---|---|
| 0.40 | 27 | 27 | 0.40 | 22 | 4.2 | 3 / 5 | Close |
| 0.50 | 34 | 34 | 0.40 | 22 | 4.2 | 3 / 5 | |
| 0.60 | 40 | 40 | 0.40 | 22 | 4.2 | 3 / 5 | Desk (default) |
| 0.70 | 47 | 47 | 0.40 | 21 | 3.9 | 3 / 5 | |
| 0.80 | 54 | 54 | 0.40 | 18 | 3.4 | 3 / 5 | Back |
| 1.00 | 67 | 67 | 0.40 | 15 | 2.8 | 3 / 5 | |
| 1.50 | 101 | 75 | 0.30 | 13 | 1.8 | 4 / 7 | Standing (120 cm: about 90 pt, panel must be widened) |

At the 60 cm desk preset the 520 pt x 220 pt default panel yields S = 40 pt, about 24 characters and 3.5 lines inside the 180 pt left under the notch, so the default panel already matches the model. Today's 26 pt default is 35% too small for that distance.

---

## 7. Defaults when not adaptive (fallback)

Used when Auto is off, permission is denied, or no face is found. Derived with the same model at the typical distance for each platform.

| Parameter | iPhone | Mac | Basis |
|---|---|---|---|
| Distance assumed | 0.45 m | 0.60 m | typical, see section 6 |
| Weight | semibold (600) | semibold (600) | 1.6 |
| Font size | **36 pt** (alpha 0.40 deg at 45 cm; iPhone 16 Pro) | **40 pt** (alpha 0.40 deg at 60 cm) | 1.3; today 34 / 26 |
| Line height multiple | 1.30 | 1.30 | 1.5 (today 1.35) |
| Letter spacing | 0 em | 0 em | 1.6 |
| Word spacing | +0.04 em | +0.04 em | 1.6, design |
| Paragraph spacing | 0.8 em (unchanged) | 0.8 em | existing |
| Column width / side margins | 22 chars centred, min margin 16 pt; at 36 pt that is about 400 pt wide, so full width minus margins on a 402 pt phone | 22 chars, centred under the notch, min margin 16 pt | 1.4 |
| Visible lines | 3 | 3 | 3.2 |
| Reading line | line 1-2 of band | line 1-2 | 3.2 |

Cue text (`[[...]]` blocks, shown not read, not counted as words) keeps its ratio 0.62 and italic medium; its colour stays distinct (blue) so it is never mistaken for script. Word indices are untouched (`ScriptTokenizer` is shared and must not change).

---

## 8. Colour, highlight and contrast over video

### 8.1 Colour order: read / current / upcoming

Evidence and inference:
- Readers look 2-3 words ahead and use a preview out to about 14-15 characters; faint upcoming text slows reading, especially for older readers (https://pmc.ncbi.nlm.nih.gov/articles/PMC4585246/ , https://pmc.ncbi.nlm.nih.gov/articles/PMC3996545/ , https://pmc.ncbi.nlm.nih.gov/articles/PMC6233613/). So the text the eyes must process next must have full contrast.
- A highly salient cue on the spoken word can drag the eye back toward it (highlighting study, https://hal.science/hal-01575227/document); the research gives no proven optimal brightness ordering, so this is a design decision.

Decision:

| State | Treatment |
|---|---|
| **Upcoming** | **brightest body text: pure white (alpha 1.0)** (today 0.95); this is where the eyes work |
| **Current word** | warm yellow (1.0, 0.86, 0.40) as today, plus a soft fill plate at 16% (as today); restrained: colour and fill, no size or weight change (no reflow) |
| **Read** | white at **0.55** alpha (today 0.60 on iPhone, **0.35 on Mac**: too low). Still readable (needed for rereading a slip) but clearly "done" |

The reader does not get "dimmer ahead"; the only thing brighter than upcoming text is hue, not luminance. Yellow luminance (0.73) is below white (1.0) on purpose.

### 8.2 Contrast targets

WCAG 2: AA 4.5:1 and AAA 7:1 for normal text, 3:1 / 4.5:1 for large text (https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum , https://www.w3.org/WAI/WCAG22/Understanding/contrast-enhanced). APCA: |Lc| 75 minimum, 90 preferred for body (https://github.com/Myndex/SAPC-APCA/blob/master/documentation/APCA_in_a_Nutshell.md). Targets:
- Upcoming text: **>= 7:1** (text is large, so 4.5:1 is the AA-large-AAA bar and 7:1 is our target) over the brightest realistic frame.
- Current word: >= 4.5:1.
- Read text: >= 3:1.

### 8.3 Local, adaptive treatment (satisfies the "video stays visible, text maximally legible" rule)

Contrast arithmetic [derived, sRGB gamma compositing as in Core Graphics]. Required black backing opacity `a` for white text (alpha 1) behind which the video has relative luminance Lbg:

| Background luminance | a for 4.5:1 | a for 7:1 |
|---:|---:|---:|
| 0.90 (white sky, bright wall) | 0.51 | 0.63 |
| 0.70 | 0.46 | 0.59 |
| 0.50 | 0.37 | 0.53 |
| 0.30 | 0.20 | 0.40 |
| 0.20 or darker | about 0 | about 0.15 |

The 0.90 row matches the independent figures 51.3% / 63.4% in https://dev.to/sgbp/your-contrast-checker-probably-lies-about-rgba-text-5h3i . Under linear-light compositing the numbers would be 80% / 89%, so test the actual renderer. Formula:

```
Lt_eff   = (1.0 + 0.05) / R - 0.05                 // max allowed background luminance, R = 4.5 or 7
a_scrim  = clamp(1 - enc(Lt_eff) / enc(L_bg), 0, 0.65)   // enc = sRGB OETF
```

Resulting full-text contrast with the recommended colours and scrim 0.65 over L_bg 0.9 [derived]: upcoming 7.4:1, current word 5.5:1, read@0.5 3.2:1. Without any scrim the same white text over a white sky is 1.1:1, which is why a halo alone is not enough.

Why local, not a band: today the iPhone path draws a full-width feathered veil of alpha 0.30 over the whole text band plus a two-layer halo (blur 10 pt at 0.7, and offset 1 pt / blur 2.5 pt at 0.95). 0.30 is below the 0.51 needed for 4.5:1 on a white background, and it darkens the whole band even where the video is already dark. The new rules:

1. **Per-line plate**, not per-band: for each visible line take its glyph rect, inflate by 0.6 em horizontally and 0.22 em vertically, rounded radius 0.5 em, fill black, then Gaussian-feather with sigma 0.3 em. Lines are only 0.3 em apart, so plates merge into one soft shape that follows the ragged right edge of the text; the video stays visible above, below and beside the text. **[design]**
2. **Alpha per line from the video behind it**: sample luma of the camera preview under each line on a coarse grid (for example 16 x 4 cells), take the 90th percentile as L_bg, compute `a_scrim` with R = 7, clamp to **0.12 minimum** (halo-only floor on dark scenes) and **0.65 maximum**; smooth over time with an EMA, tau 0.5 s, so it does not flicker on cuts or auto-exposure. On a dark scene the scrim vanishes and the picture is untouched. The scrim never needs more than 0.65, so the picture always remains visible through it (about 35% of the pixel value shows through).
3. **Halo on every glyph** (supplement, never a substitute): tight shadow, offset 0, y +0.03 em, radius 0.07 em, black 0.9; wide shadow, radius 0.28 em, black 0.55. Today's values are about 0.07 em and 0.29 em at 34 pt, so the geometry carries over, expressed in em so it scales with auto size. W3C accepts a contrasting halo or at least 1 px outline (https://www.w3.org/WAI/WCAG21/Techniques/general/G18); a study found shadows beat the outlines it tested on static images, which does not carry to live video, hence the plate. https://www.bendsawyer.com/wp-content/uploads/2025/05/Sawyer-et-al_2020_Glanceable-legible-typography-over-complex-backgrounds.pdf
4. Reference practice: BBC subtitles specify solid black behind text (https://www.bbc.co.uk/accessibility/forproducts/guides/subtitles/); Material recommends local gradients, 40-60% black as a starting point (https://m1.material.io/style/imagery.html). Ours is the adaptive version of the same idea.
5. **Mac**: the panel window is clear and non-opaque (`NotchPanel`: `isOpaque = false`, `backgroundColor = .clear`), so text sits on whatever is under it, typically a call window, and sampling it would need Screen Recording permission, which we will not request. Use a fixed per-line plate at **0.60** plus the same halo, or an opaque near-black panel that merges with the notch. Either gives >= 7:1 on any background (white behind 0.60 black is 6.2:1 for white text; 0.65 gives 7.4:1, so use **0.65 fixed** on Mac). Confirm in the code what the view draws behind the text before changing anything.

Compatibility: reading-line rule (1 px, white 0.18) and the current-word fill stay; the cue-block backgrounds stay.

---

## 9. Competitor check (what exists, what could not be found)

Method: App Store pages, release notes, vendor help pages, Reddit, patents, research. "Not found" means no documentation of camera-measured face distance driving script size; it does not prove absence.

| Product | What it does | Distance-adaptive size |
|---|---|---|
| Teleprompter Pro (formerly Premium), Teleprompter Premium (separate app), Teleprompter.com | font size slider, voice scroll (VoiceGlide) | not found |
| BIGVU | voice scroll, AI eye-contact correction, face/body tracking via Pivo pod (keeps you in frame) | not found |
| PromptSmart / PromptSmart+ | VoiceTrack speech following; optional face detection for focus/framing | not found |
| Elgato Prompter / Camera Hub (now Studio 2.0) | face tracking for framing, AR eye-contact correction, Voice Sync | not found |
| Moody (incl. Mac notch version) | voice-activated scroll, user-selected size | not found |
| CapCut teleprompter | font, speed, position; separate AI Eye Contact | not found |
| Parrot, CuePrompter, Promptr by MRVL, EyePrompt, Teleprompter for Video, OwlPrompter | manual size, voice/smart scroll; OwlPrompter pauses scroll when you look away (camera used for scroll, not size); EyePrompt scores eye contact after the take | not found |
| **CueBuddy (formerly SpeakFlow), App Store** | the listing says "optimized reading presets for different shooting distances" (verified on the page 2026-11-19). It does not state the distances, does not mention measuring distance, and I could not verify claims of 0.5/1/2 m or of face tracking on that page | **manual presets only**, closest to our Mac preset feature |
| Teleprompter Chrome extension | computes font size from a distance the user types in | manual |
| Apple Screen Time "Screen Distance" | TrueDepth warns when the device is closer than 12 in for a while (iOS 17+) | warning only, no resizing. https://support.apple.com/en-us/105007 |

Prior art (not products):
- **CN114554031A** (Unisound, published 2022-05-27): a prompting method that gets the speaker's position (including from a camera, claim 5), determines distance to the prompt screen and a display mode including font and font size (claims 2, 7), with a motorised screen turning toward the speaker. Verified: Google shows "Pending" but the legal events list a post-publication rejection (RJ01) dated 2025-08-26, never granted. https://patents.google.com/patent/CN114554031A/en
- **US 9,183,806 B2** (Verizon, filed 2011-06-23, granted 2015-11-10, shown Active with adjusted expiry 2032-01-25): sensor-measured user-to-device distance, a baseline distance, target value for an output, changed at a user-specified speed (claim 1), font size in claims 2 and 11; the description mentions distance to the user's eyes. https://patents.google.com/patent/US9183806B2/en . It is generic, not teleprompter-specific, but it describes the same family of idea. **Needs legal review before the 1.0.3 marketing push** (claim wording involves a baseline distance and a user-selected change speed; our smoothing/snapping design is different, but that is a question for counsel, not for this document).
- Research: LIME (face-to-screen distance from front camera, font size on SMS demo, https://arxiv.org/html/1612.04131); reading-while-walking font adaptation from viewing distance (CHI 2025, https://dl.acm.org/doi/10.1145/3706598.3713367); calibrated front-camera text size (2024, https://www.worldscientific.com/doi/10.1142/S1793351X2445003X).
- Name collision, FYI: a third-party GitHub project named "sightline-prompter" (JoJo-1965) has a head guide that measures apparent face size. It is a different owner from this repository (`berkbayri`). Not distance-adaptive text either.

Bottom line: no teleprompter app that I could document does camera-measured, live, automatic script resizing. That is a finding about public documentation on one date, not proof that none exists, and "idea novelty" is not claimable (patents and papers above).

---

## 10. Parameter table (constants for code)

| Constant | Value | Notes |
|---|---:|---|
| `xHeightRatioFallback` | 0.526 | use `font.xHeight/pointSize` at runtime |
| `alphaNominalDeg` | 0.40 | x-height visual angle |
| `alphaMinDeg` / `alphaMaxDeg` | 0.25 / 0.60 | clamp |
| `cplTarget` / `cplMin` / `cplMax` | 22 / 13 / 30 | characters per line |
| `avgCharAdvanceEm` | 0.50 | incl. spaces |
| `lineHeightMultiple` | 1.30 | range 1.25-1.40 |
| `visibleLinesDefault` / `Min` / `Max` | 3 / 2 / 5 | band shows N lines |
| `thetaVComfortDeg` / `thetaVMaxDeg` | 3.0 / 5.0 | gaze below lens |
| `thetaHHalfDeg` | 4.2 | heuristic half-sweep |
| `g0Mm` | 4 (Dynamic Island, Mac notch), 6 (other iPhones) | measure on device |
| `fontWeight` | semibold | constant |
| `letterSpacingEm` | 0 | user range 0..0.02 |
| `wordSpacingEm` | 0.04 | range 0..0.08 |
| `ppmmIPhone` | 6.037 default; 6.010, 6.507, 6.417 | table by model id |
| `ppmmMac` | `frame.width / CGDisplayScreenSize.width`, fallback 5.064 | live |
| `fontSizeMinIPhone` / `Mac` | 20 / 16 pt | |
| `fontSizeCapRule` | `S <= W_usable / (0.5 * cplMin)` | width cap |
| `ipdMm` | 63 | prior, 6% sigma |
| `faceMeasureHz` | 5 | |
| `yawRejectDeg` | 30 | |
| `minIPDpx` | 24 | below: invalid |
| `medianWindow` | 5 samples | |
| `oneEuro.minCutoffHz` / `beta` / `dCutoffHz` | 0.4 / 5 / 1.0 | on ln(Z); tune on device |
| `sizeStepRatio` | 1.10 | geometric grid |
| `commitThresholdUp` / `Down` | 1.10 / 1.15 | hysteresis |
| `commitDwellSec` / `minGapSec` / `maxWaitSec` | 1.5 / 3.0 / 4.0 | |
| `pauseApplySec` | 0.25 | speech pause to apply |
| `resizeAnimSec` | 0.30 | anchor on current word |
| `noFaceTimeoutSec` | 5 | fall back to preset / stored distance |
| `personalGainRange` | 0.8 .. 1.25 | `k` |
| `colorUpcoming` / `Current` / `Read` | white 1.0 / (1, 0.86, 0.40) / white 0.55 | |
| `currentFillAlpha` | 0.16 | existing |
| `scrimAlphaMin` / `Max` | 0.12 / 0.65 | per line |
| `scrimTargetRatio` | 7.0 | AAA, upcoming text |
| `scrimPadEm` (h / v) | 0.6 / 0.22 | |
| `scrimRadiusEm` / `FeatherSigmaEm` | 0.5 / 0.3 | |
| `scrimSmoothTauSec` | 0.5 | |
| `lumaGrid` | 16 x 4 per line, 90th percentile | |
| `haloTight` | y 0.03 em, radius 0.07 em, black 0.9 | |
| `haloWide` | radius 0.28 em, black 0.55 | |
| `macScrimAlphaFixed` | 0.65 | clear panel, no sampling |
| `macPresetsCm` | 45 / 60 / 80 / 120 | Close / Desk / Back / Standing |
| `lineFadeBeyondBudget` | opacity ramp to 0.35 | beyond theta_v max |

---

## 11. Algorithm (pseudocode)

```text
// ---- once per script open / device change
ppmm   = platformPPMM()                         // 2.1 / 2.2
xr     = font(semibold).xHeight / pointSize     // fallback 0.526
W      = usableWidthPt()                        // minus margins
gain k = stored personalGain (default 1)

// ---- continuous, 5 Hz, only when Auto ON and permission granted
on videoFrame(buffer, intrinsics):
    if frameIndex % 6 != 0: return
    face = Vision.landmarks(buffer).largestFace
    if face == nil or conf low:  noFaceTimer += dt; if noFaceTimer > 5: useFallbackDistance(); return
    ipdPx = distance(pupilL, pupilR) / cos(yaw)
    if |yaw| > 30deg or ipdPx < 24: return
    noFaceTimer = 0
    if iOS:  Z = fPx * 63mm / ipdPx                    // fPx from intrinsics, else videoFieldOfView
    if Mac:  zRel = ipdRefPx / ipdPx                   // relative mode, no metric distance
    push(median5, ln(Z or zRel)); lnZ = oneEuro(median5.value, dt)

// ---- size controller (runs every 200 ms)
function targetSize():
    if iOS/Mac-metric:   d = exp(lnZ);  S0 = d * tan(alphaNom) * ppmm / xr
    if Mac-relative:     S0 = S_ref * exp(lnZ - lnZref)           // = S_ref * ipdRef/ipdPx
    if Mac-preset/none:  S0 = presetDistance * tan(alphaNom) * ppmm / xr
    S  = S0 * k
    S  = min(S, W / (0.5 * cplMin))                 // width cap
    S  = max(S, sMin)
    alpha = atan(S * xr / ppmm / d)
    if alpha < alphaMin and distance known:  showHint("too far for this screen"); S = cap
    return S

S_t = targetSize()
if |ln(S_t / S_cur)| >= ln(stepRatio) (1.10 up / 1.15 reversing):
    dwell += dt
else: dwell = 0
if dwell >= 1.5s and now - lastChange >= 3s and !userInteracting:
    if speechPause >= 0.25s or atParagraphBreak or waited >= 4s:
        S_cur = snapToGrid(S_t, ratio 1.10)
        relayout(S_cur, anchor: currentWord, anim: 0.30s)
        lastChange = now

// ---- layout derived from S_cur
cpl      = clamp(W / (0.5*S_cur), cplMin, cplTarget(22))
colWidth = cpl * 0.5 * S_cur
perLine  = lh * tan(alpha) / xr
N        = clamp(floor((tan(3deg) - g0/d)/perLine + 0.55), 2, 3)   // comfort; up to 5 only if user widens band
bandH    = gutter + N * lh * S_cur
reading line = line 1..2

// ---- contrast, per visible line, every frame (cheap) or at 15 Hz
for line in visibleLines:
    Lbg = percentile90(luma(previewRegion(line.rect)))            // iOS
    a   = clamp(1 - enc(((1.05)/7.0 - 0.05)) / enc(Lbg), 0.12, 0.65)   // Mac: fixed 0.65
    a   = ema(a, tau 0.5s)
    draw plate(line.rect inflated (0.6em, 0.22em), radius 0.5em, black, a, feather sigma 0.3em)
    draw glyphs with tight + wide halo (em based)
```

Manual override: any user size change while Auto is ON sets `k = clamp(S_user / S_model, 0.8, 1.25)`; the size controller then applies it without a toast storm (one toast per session).

---

## 12. Open items to verify on device before shipping (not assumptions to hide)

1. Lens position (g0) on iPhone 16 Pro, one non-island iPhone, MacBook Air 13.6: measure with calipers.
2. Distance accuracy at 0.4 / 0.6 / 1.0 m per stabilisation mode and per recording mode (4K60, HDR HLG); confirm the intrinsics already include crop/stabilisation.
3. Thermal and battery cost of one 640 px video data output plus 5 Hz Vision landmarks during 4K60 HDR recording.
4. Mac: concurrent capture with Zoom, Meet, FaceTime and Teams in both start orders; Center Stage on/off; Continuity Camera selected.
5. 1 Euro, step ratio 1.10, dwell and word-spacing values: tune with recorded traces; none is a cited number.
6. Per-line scrim alpha in the actual renderer (gamma vs linear compositing) against a white wall, a window and a mid-grey wall.
7. Typical distances per use case (section 6) from opt-in anonymous measurements.
8. Legal review of US 9,183,806 B2 (active to about 2032) before announcing the feature (section 9).

---

## 13. Claims we can make (and cannot)

Can say, after the verification in section 12 passes:
- "Text size follows how far you sit, so it stays readable without leaning toward the screen." (feature description)
- "Sized from the viewing angle of the letters (research-based reading size), not a fixed point size."
- "Keeps the text close to the lens so your eyes stay near the camera." (line count and band height are limited to a few degrees below the lens, section 3)
- "Works with 4K and HDR recording: the camera feed for distance runs alongside recording, nothing is saved." (only once item 3 is verified)
- "Everything is measured on your device; no video or face data leaves it." (true for the design above; keep it true)
- "Local contrast: a soft backing only behind the lines of text, so your picture stays visible." (describes the design)
- Mac: "Optional: measures your distance from the built-in camera (off by default), or choose Close / Desk / Back / Standing."

Cannot say:
- "First", "only", "world's first", "no other teleprompter does this": only "we found no teleprompter app that documents this" is supportable, and prior art exists in patents and papers (section 9). If a "first" claim is ever wanted, it needs a fresh dated search of the App Store and a lawyer.
- Any metric accuracy ("measures distance to the centimetre"): the estimate is about 6-9% 1-sigma uncalibrated.
- "Perfect eye contact" or "viewers cannot tell you are reading": the research gives tolerance angles, not guarantees, and studies disagree (section 3.1).
- "Scientifically proven" for the specific defaults (0.40 deg, 22 characters, 3 lines, +0.04 em word spacing): they are research-informed design choices.
- Medical or accessibility claims.
- That it works on iPhone SE specially: it does (no TrueDepth needed), but SE accuracy is untested.
