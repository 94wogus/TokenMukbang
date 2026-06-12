# TokenMukbang — Design System ("Liquid Vitals, Instrument-Grade")

> ⚠️ **SUPERSEDED (2026-06-12).** 비주얼 방향이 **김 서림(Steam)**으로 교체됐다 — 정본은
> [`STEAM_DESIGN.md`](STEAM_DESIGN.md), 결정은 [ADR-0016](../adr/0016-steam-visual-direction.md).
> 단, 이 문서의 **하부 메커니즘은 김 서림이 상속**한다: 위험색 앱-측 resolver(`RiskTone`, ADR-0015),
> 6pt `GaugeBar`, scrim·우측 값 컬럼, `DSSegmented`, tabular 숫자. 아래는 그 상속분 레퍼런스로
> 유효하되 **팔레트·시그니처·z-stack은 STEAM_DESIGN이 우선**한다.

> **TL;DR:** The implementation-facing rules distilled from `DESIGN_RESEARCH.md`. One
> threshold drives every surface; depth = material + tint (no shadows / hard borders);
> numbers are right-aligned `.monospacedDigit`; gauge + number always travel together;
> the reset countdown is always visible; 먹방 personality lives only at the edges.
> Risk color is resolved app-side and **scheme-branched** (light ≠ dark). Deployment
> target macOS 14; Tahoe niceties are `#available` progressive enhancement.

## 1. Color tokens

Resolved in the **app layer** by a `RiskTone` resolver that reads `@Environment(\.colorScheme)`.
`TokenMukbangKit` stays UI-free and only emits the `RiskLevel` enum (calm/watch/warning/critical)
+ an `isOver` flag — it never owns a `Color`.

**Risk scale** — risk color rides **gauge fill / ring / endpoint dot ONLY**, never a small numeral.

| level | light | dark |
|-------|-------|------|
| safe (calm) | `#1E7B34` | `#30D158` |
| watch | `#946800` | `#D9B225` |
| warn (warning) | `#A8521A` | `#FF9F0A` |
| danger (critical) | `#C0271E` | `#FF453A` |
| over (≥100%) | `#A21B3A` | `#FF375F` + **non-color cue** (bar breaks past tick + ✕ glyph) |

**Surfaces** (semantic so vibrancy/Increase-Contrast/Reduce-Transparency work for free):
- `surface.base` = `.regularMaterial` (popover body — never stack a second Material).
- `surface.card` = white 6% (light) / 5% (dark) — used sparingly, not as the primary seam.
- `surface.hover` = white 10% / 8%. `surface.selected` = `controlAccent` 14%.
- `gauge.track` = white 0.12 (light) / 0.14 (dark).
- `border.hairline` = `Color(.separatorColor)`, drawn `.overlay(alignment:.bottom){ Color(.separatorColor).frame(height: 1/displayScale) }`.

**Foreground:** `fg.primary` = `Color(.labelColor)`, `fg.secondary` = `.secondaryLabelColor`,
`fg.tertiary` = `.tertiaryLabelColor`.

**Accent:** `controlAccentColor` for **non-risk affordances only** — fenced OUT of the meaning
channel (it is user-settable and may equal warn/danger).

**Context-fill** (sessions) uses the **same** `RiskTone` resolver — no second risk palette.

**Menu-bar tint** (`RiskTone.menuBarColor`): the bar is translucent over a wallpaper and the system
only auto-contrasts *template* glyphs, not custom RGB. Rather than an outline halo (a video-game OSD
trope), the menu-bar palette is **muted + luminance-pinned**: saturation capped (instrument-grade),
luminance branched by the **menu bar's own** light/dark — deeper on a light bar, lighter on a dark bar
— so it reads on nearly any wallpaper. That light/dark is the *menu bar's* effective appearance (which
tracks the wallpaper), read from the status-item button's `effectiveAppearance` via `MenuBarAppearance`,
**not** `NSApp.effectiveAppearance` (which is only the app's mode). Unit label (`5h`/`7d`) is **bold but
transparent** (opacity ~0.45): recedes by alpha, not weight. Percent is 2-digit zero-padded (`05%`) so
width never jitters. (Technique research 2026-06-11: bjango, Apple HIG, exelban/Stats #2178.)

## 2. Type scale (6 rungs, 3 weights). SF Rounded is fenced to exactly the hero % + kaomoji chip.

| role | spec |
|------|------|
| Display (hero %) | 28pt semibold **SF Rounded** `.monospacedDigit` — the single warmth on the data plane |
| Title (section header) | 15pt semibold SF Pro |
| Eyebrow | 10pt medium **UPPERCASE**, tracking ~0.6, `.tertiary` SF Pro — used **once**, at the major seam |
| Body / label | 13pt regular SF Pro, `.secondary` (labels separate from values on BOTH opacity + weight) |
| Value | 13pt **medium** `.monospacedDigit` SF Pro, **right-aligned** |
| Reset countdown | 13pt regular `.monospacedDigit` `.secondary`, **persistent** (absolute time on hover) |
| Caption | 10pt regular `.tertiary` (timestamps only) |
| Menu bar | unit label 12pt **bold @ 45% opacity** (context, recedes by alpha) + value 13pt **bold** `.monospacedDigit` **muted risk-tint** (signal). No glyph/halo — adaptive muted color is the cue |

## 3. Layout moves

1. **Header = two rows, not a 3-way tug-of-war.** Top strip: kaomoji **chip (20px)** + Title on a
   shared `firstTextBaseline`. Hero 28pt % right-aligned, vertically centered to the whole header.
   The kaomoji is **off** the hero row (one rounded object on the data plane at a time).
2. **One right-edge alignment spine at 16pt inset.** Hero %, every row Value, used/limit, reset
   countdown, sparkline endpoint dot all share one invisible right gutter. Whitespace = vertical
   rhythm (8pt grid: 16 outer / 12 section / 8 row); the gutter = horizontal alignment.
3. **Z-flow with a demoted bar.** hero % (right) → thin **6pt** full-width linear bar (a quiet echo
   of the same number, never competes) → **persistent reset countdown** beneath, numerals on the
   right gutter. Over-state: bar visibly breaks past a 100% tick + ✕ glyph.
4. **Menu bar — typography + adaptive muted color carry the information.** Unit label (`5h`/`7d`)
   **bold @ 45% opacity** (context); **value+% bold, muted-risk-tinted** by state, the color
   **luminance-pinned to the menu bar's own light/dark** so it reads on any wallpaper (no outline).
   `.monospacedDigit` + 2-digit zero-pad → no width jitter. **NB:** a SwiftUI `Text` in `MenuBarExtra`
   is flattened by the status item (per-run weight/size/color stripped, rendered as a monochrome
   template), so the label is rendered to a **non-template color `NSImage`** (`ImageRenderer` +
   `isTemplate = false` + `.renderingMode(.original)`) — the colored-icon trick. The menu bar's
   effective appearance comes from the status-item button's `effectiveAppearance` (`MenuBarAppearance`),
   not `NSApp`'s, so the colors track the wallpaper the way template glyphs do.
5. **Multi-gauge / Compact hierarchy.** No single hero → sort rows by risk descending (worst top),
   bump the top row's % one rung (15pt semibold), reserve a min-width gauge column so a long label
   can't starve the bar.
6. **Region separation hardened against vibrancy.** The major seam (usage ↔ Agent-Watchers) gets the
   one hairline + the single neutral eyebrow; card radii 12 / inner pill 8 / chip 9999 as the macOS-14
   baseline, `.containerConcentric`/Tahoe radii are `#available` enhancements.

## 4. Spacing & radii
- 8pt grid: **16** outer padding, **12** between sections, **8** between rows, **6** intra-row.
- Radii: card **12**, inner pill **8**, chip **9999**, gauge bar height **6**.

## 5. Personality rule (ADR-0009 holds, accuracy > cuteness)
- Mascot: **popover header chip + widget + empty states + event toasts** only. Never on the data
  plane competing with the hero, never in the menu bar.
- Gauges/numbers stay expressionless and precise. Copy carries the 먹방 voice (완식 / 소화 중 / 관전).
