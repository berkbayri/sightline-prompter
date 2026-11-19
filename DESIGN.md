---
name: Sightline Prompter
description: A teleprompter that follows your voice, word by word. Ink-dark, one reading yellow.
colors:
  ink: "#07080C"
  surface: "#0E1016"
  raised: "#16181F"
  hairline: "rgba(255,255,255,0.08)"
  text: "#F4F4F6"
  text-2: "rgba(244,244,246,0.68)"
  text-3: "rgba(244,244,246,0.42)"
  reading-yellow: "#FFD60A"
  reading-yellow-hover: "#FFE14D"
  current-word-ink: "#FFDB66"
  current-word-plate: "rgba(255,214,10,0.16)"
  icon-gold: "#F5D77A"
  cue-blue: "#7DB8FF"
  rec-red: "#FF3B30"
  glow: "rgba(255,214,10,0.18)"
typography:
  display:
    fontFamily: "Barlow Condensed, BC Narrow, sans-serif"
    fontSize: "clamp(40px, 9vw, 96px)"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "0em"
  reading:
    fontFamily: "-apple-system, SF Text, system-ui, Segoe UI, Roboto, sans-serif"
    fontSize: "min(64px, 100cqw / 20)"
    fontWeight: 600
    lineHeight: 1.35
    letterSpacing: "0em"
  body:
    fontFamily: "-apple-system, SF Text, system-ui, Segoe UI, Roboto, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "-apple-system, SF Text, system-ui, Segoe UI, Roboto, sans-serif"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1
rounded:
  pill: "999px"
  sm: "6px"
  md: "9px"
  lg: "16px"
  hl: "0.22em"
spacing:
  gutter: "max(16px, 4.4vw)"
  section: "clamp(56px, 7vw, 104px)"
  gap: "8px"
  tap: "44px"
components:
  button-primary:
    backgroundColor: "{colors.reading-yellow}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    height: "44px"
    padding: "0 22px"
  button-primary-hover:
    backgroundColor: "{colors.reading-yellow-hover}"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.text}"
    rounded: "{rounded.pill}"
    height: "44px"
  tag:
    textColor: "{colors.text-2}"
    rounded: "{rounded.pill}"
    height: "30px"
    padding: "0 12px"
  tablist:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.pill}"
    padding: "4px"
  consent-bar:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.text}"
    rounded: "{rounded.lg}"
    padding: "18px 20px"
---

# Design System: Sightline Prompter

Recorded from the shipped site (`site/assets/site.css`, built into `docs/`, live at sightlineprompter.app). Product truth lives in PRODUCT.md; this file is visual only.

## Overview

**Creative North Star: "The Page Reads Itself"**

The first screen is a teleprompter, not a hero banner. A script is read word by word on a near-black ground, the current word lit in reading yellow, and the same behaviour is reused wherever the page wants attention. The product is the proof: real simulator and Mac captures, never mockups.

Density is calm and editorial. One idea per section, large condensed uppercase heads, generous vertical rhythm, one soft gold glow per viewport from below. Imagery is real-app UI over photoreal people.

**Key Characteristics:**
- Ink ground, one yellow that means "this is being read" or "do this".
- Condensed 800 display heads (Barlow Condensed) against the system text face used for prompter lines and body.
- Prompter styling is the shared component: the same `--prompter-*` tokens style hero, device panels and the autosize scene.
- Real Apple device frames, real captures, real 9:41 status bar.

Brand source: the app icon (three reading bars, yellow, light grey, dark grey, with the notch) and the App Store screenshot set (heading second line in yellow). The in-page `.mark` repeats the bars at 100% / 80% / 60% width in `{colors.icon-gold}`, `#C9CBD2`, `#4A4D57`.

## Colors

Near-black ink with one warm yellow and one cool blue for cues.

### Primary
- **Reading Yellow** (`{colors.reading-yellow}`): the word currently being read, the primary action button, caret, selection, focus ring. Nothing else.
- **Icon Gold** (`{colors.icon-gold}`): the top bar of the logo mark only. Not a UI accent.

### Secondary
- **Cue Blue** (`{colors.cue-blue}`): `[[cue]]` delivery notes, italic in prompter lines, a 14% blue chip in the hero.

### Neutral
- **Ink** (`{colors.ink}`): page ground. **Surface** (`{colors.surface}`): tablist track. **Raised** (`{colors.raised}`): menus, consent bar, language bar.
- **Text tiers**: `{colors.text}` primary, `{colors.text-2}` body copy and nav, `{colors.text-3}` ruler ticks and quietest labels. Hairline `{colors.hairline}` for section rules.
- **Rec Red** (`{colors.rec-red}`): recording indicator inside app captures only.

### Named Rules
**The Yellow Rule.** Yellow marks the word being read and the one primary action. A secondary link is white and underlined so yellow stays with the reading word. In headings the second line is yellow (`em`), echoing the App Store set.
**The One Glow Rule.** One radial gold glow (`{colors.glow}`) per viewport, behind the device, from below. No other glows or gradients.

## Typography

**Display Font:** Barlow Condensed 800, latin and latin-ext woff2 subsets, with a metric-matched Arial Narrow fallback (`BC Fallback`, size-adjust 86%).
**Body Font:** system stack (`-apple-system, SF Text, system-ui, Segoe UI, Roboto`), the same face the app prompter uses.

**Character:** a poster-condensed voice for short heads, the OS reading face for everything that is read.

### Hierarchy
- **Display** (800, `clamp(40px, 9vw, 96px)`, line-height 1, uppercase, tracking 0): section heads (h2). Heads stay short.
- **Reading line** (600, `min(64px, 100cqw/20)`, 1.35): hero prompter lines. Previous line `.72em` at `{colors.text-3}`-ish dim, upcoming white, read words `rgba(255,255,255,0.78)`.
- **Body** (400, 17px, 1.55): `.sub` and section copy at `clamp(16px, 1.3vw, 19px)`, max 34-40em, `text-wrap: pretty`, colour `{colors.text-2}`.
- **Label** (500, 13px): tags. Buttons 600 / 15px.

### Prompter tokens (shared with the app)
`--prompter-weight` 600, `--prompter-tracking` 0em, `--prompter-word` 0.04em, `--prompter-leading` 1.3, upcoming `#fff`, read `rgba(255,255,255,0.78)`, dim `rgba(244,244,246,0.5)`, current word ink `{colors.current-word-ink}` on plate `{colors.current-word-plate}` with radius `0.22em` and pad `0.1em`, cue weight 500 italic, over-video halo (`--prompter-halo`) and local plate `rgba(0,0,0,0.5)` per line, never a full band. Source of values: `docs/prompter-typography.md` sections 1.5, 1.6, 7, 8. In the app: semibold 600 constant weight (weight never adaptive, it reflows), letter spacing 0, word spacing +0.04em halo compensation, leading 1.30, size from x-height angle 0.40 deg (S = d * tan(alpha) * ppmm / 0.526), default 3 visible lines, colour order read / current / upcoming.

### Locale rules
- **Latin diacritics:** `--lh` 1.06 for fr, es, it, pt; 1.12 for tr and de.
- **CJK (ja, ko, zh):** no uppercase, tracking 0, display scale `.74`, weight 900, line-height 1.22 on heads and 1.75 to 1.8 on body, FAQ summaries 1.5. System stacks per language: Hiragino ProN / Yu (ja), Apple SD KR (ko), PingFang SC/TC with Microsoft YaHei/JhengHei and Noto fallbacks (zh).
- **Line breaking:** ja and zh `line-break: strict; word-break: auto-phrase; overflow-wrap: anywhere`; ko `word-break: keep-all; overflow-wrap: break-word`. Cues are upright (not italic) in ko and zh.
- Word highlighting segments with `Intl.Segmenter` per `lang`, so CJK words highlight as phrases.

### Named Rules
**The Short Head Rule.** Display type is for a few words. Long or CJK heads drop the scale, never the legibility.
**The Same Face Rule.** Whatever is read (prompter lines, body) is the system face; the condensed face only labels sections.

## Layout

Single column of full-bleed sections inside `.wrap` (max 1312px, side gutter `max(16px, 4.4vw)`), separated by 1px hairlines. Section padding `clamp(56px, 7vw, 104px)`. Two-column splits from 900px (7/5 hero, 5/6 and 5/7 device grids), stacked below. Mobile nav wraps; the links row scrolls horizontally behind a hairline. Hero left is a container-query-sized reading block so the lines fit without wrapping on desktop; under 640px lines wrap with `text-wrap: balance` and a 27px floor (23px ja). All tap targets min 44px. Breakpoints: 420, 600, 640, 700, 760, 899/900.

## Elevation & Depth

Flat and tonal. Depth comes from ink / surface / raised steps, 1px strokes (white 0.14 to 0.28) and the one gold glow. The only real shadow is the language menu (`0 24px ... rgba(0,0,0,.6)`). The reading lines over video use a text halo, not a box shadow.

### Named Rules
**The Flat-By-Default Rule.** Surfaces carry no shadow; only floating menus do.

## Shapes

Pills for anything interactive or labelled (buttons, tags, tablist, video control: 999px). Containers 16px (consent bar), menu 14px, items 8px, App Store badge 9px, focus ring radius 6px. Current-word highlight radius `0.22em`. Device screens use bezel-matched radii (17.2%/7.9%). Strokes are 1px; focus is a 2px yellow outline, offset 3px.

## Components

### Buttons
Primary: yellow pill on ink text, 44px, 600/15px; hover `#FFE14D` + 1px lift; active scale .97. `.light` (text-colour fill) and `.ghost` (transparent, white .28 stroke) variants exist for non-primary use. Secondary text link is white, underlined at 50% (`.link`). The App Store badge (official black, unmodified, `.store`) is the page's one primary action next to the yellow button.

### Reading-line hero
Three lines: previous (dim, .72em), current (word highlight advances on a 420ms timer), next (white), plus one cue chip in blue. Entrance rises 14px with 80ms stagger. The right side is the per-locale simulator recording in an iPhone 17 Pro bezel.

### Tags vs segmented tabs
Tags are non-interactive pills, 30px, 1px yellow-outlined (rgba .42), grey text. Tabs (`.tablist`) are a segmented control on `{colors.surface}` with 1px white .16 stroke, scroll-snapped on narrow screens; selected state is the only tab that fills. Do not style tags to look clickable.

### Device frames
Black Apple Product Bezels, unmodified, per Apple marketing guidelines (iPhone 2760x1350 aspect, `.dev` / `.dev.l`). Screen is inset exactly (5.333% / 2.5%) with the bezel PNG above. No CSS-drawn notch or fake device chrome.

### Consent bar
Fixed bottom-left, max 560px, `{colors.raised}`, 16px radius, 1px white .14 stroke, 18/20 padding, 16px viewport margin; actions are buttons, text in body tier.

### FAQ
`details/summary` list with hairline dividers, answers max 34em, line-height 1.8 for CJK, summary 1.5.

### Language menu and bar
Raised panel with 44px rows; `aria-current` is weight 600. The first-visit redirect runs from `/` only, once, and bots and saved choices stay put.

### Distance scene (autosize)
Sticky pinned scene: scroll progress maps 35 cm, 100 cm, 45 cm; text size comes from the app formula; the iPhone mock uses the real prompter tokens with a masked fade, a ruler (44px) with range input for keyboard use.

## Do's and Don'ts

### Do:
- **Do** use real captures: simulator or Mac recordings per locale, with a real 9:41 status bar.
- **Do** label AI-generated people as illustrative in alt text.
- **Do** keep Apple Product Bezels unmodified and the App Store badge official.
- **Do** let the app and site share `--prompter-*` values; change them in `docs/prompter-typography.md` first.
- **Do** rest on a static highlighted word under `prefers-reduced-motion` and offer a pause control for loops.

### Don't:
- **Don't** use yellow for anything but the reading word and the primary action (and heading second lines).
- **Don't** make weight, tracking or word size change on the highlighted word (reflow loses the line).
- **Don't** draw a CSS notch or bezel next to real Apple bezels.
- **Don't** invent testimonials, ratings, prices or press.
- **Don't** use a full-width dark band over video text; use the per-line plate and halo.

## Not canonized (defects/drift)
- Tags use a yellow outline (rgba .42), which strains the Yellow Rule; recorded as built, not extended to new components.
