# Cinemakom Design: "Marquee"

**The idea:** the neighbourhood picture palace after dark. The interface is deep cocoa and warm bulb light, so the **posters are the only real colour on screen**. It nods to the old cinema halls of Al-Rasheed Street without turning into a costume.

**One theme.** There is no light mode, dark mode or theme setting. Every colour, size and radius comes from the tokens below (`lib/app/theme/`). Never hardcode a colour or font in a widget.

Visual reference: the "A · Marquee" boards on the [design canvas](https://claude.ai/artifact/XEb3j3VhiknZVEpX4FuLnU).

---

## 1. Colour (`MarqueeColors`)

| Token | Hex | Use |
|---|---|---|
| `night` | `#15100C` | App background |
| `booth` | `#221A14` | Surfaces: panels, sheets, cards, search field |
| `boothRaised` | `#2C221A` | Selected or hovered rows, pressed surfaces |
| `navBar` | `#1B1510` | Bottom bar and rail |
| `velvet` | `#3A2C21` | Dividers, outlines, progress tracks |
| `velvetStrong` | `#5A4634` | Outlined-button borders, inactive indicators |
| `cream` | `#F4EAD7` | Primary text and icons |
| `creamSoft` | `#CDBEA5` | Long text (synopsis) |
| `dust` | `#B9A88E` | Captions, metadata, inactive nav |
| `dustDim` | `#6E5C47` | Decorative only: unwatched episode numerals, disabled |
| `bulb` | `#F4B740` | **The one accent**: primary actions, active nav, progress, focus, 4K badge |
| `bulbBright` | `#FFD27A` | Pressed or hovered accent |
| `onBulb` | `#1A1208` | Text and icons on `bulb` |
| `ember` | `#E8735A` | Errors only |

Rules:
- **Bulb is scarce.** Use it on at most one primary action per screen, plus indicators (active tab, progress, focus). It is never a background for large areas.
- **No gradients, shadows or blur.** Surfaces are separated by tone (`night` → `booth` → `boothRaised`). The one exception is a `night` scrim under text that sits on artwork.
- **Contrast** (checked by `test/theme/contrast_test.dart`): `cream`, `creamSoft`, `dust` and `bulb` are all ≥ 4.5:1 on `night`, `booth` and `boothRaised`, and `onBulb` is ≥ 4.5:1 on `bulb`. `dustDim` is decorative only.

## 2. Type (`MarqueeText`)

| Role | Latin | Arabic |
|---|---|---|
| **Display** (hero titles, section headers, numerals, logo) | Big Shoulders Display 800–900 | Reem Kufi 700 |
| **UI** (everything else) | IBM Plex Sans 400/500/600 | IBM Plex Sans Arabic 400/500/600 |

Each role is one family plus a fallback (`fontFamilyFallback`), so mixed-script titles (very common in the API) render with the right glyphs without any locale switch.

| Style | Size / line height | Weight | Notes |
|---|---|---|---|
| `heroTitle` | 58 / 0.9 | Display 900 | Latin titles uppercased |
| `displayLarge` | 40 / 1.0 | Display 800 | Details title |
| `sectionTitle` | 22 / 1.1 | Display 800 | Latin: uppercase, tracking 0.04 em |
| `numeral` | 34 / 1.0 | Display 900 | Episode numbers ("04") |
| `title` | 16 / 1.3 | UI 600 | Card and row titles |
| `body` | 15 / 1.5 | UI 400 | Synopsis (`creamSoft`) |
| `label` | 14 / 1.2 | UI 600 | Buttons |
| `caption` | 12 / 1.35 | UI 400 | Metadata (`dust`) |
| `eyebrow` | 12 / 1.2 | UI 600 | "NOW SHOWING": tracking 0.16 em, `bulb` |
| `navLabel` | 11 / 1.2 | UI 500, 600 when active | |

**Media titles are script-aware.** A title can be Arabic even in the English UI (the API often puts Arabic in `en_title`). Style titles with `heroTitleFor(title)` / `displayLargeFor(title)`: Arabic display glyphs (dots, tall ascenders) need a line height of about 1.3 where Latin capitals use 0.9. The fonts are bundled in `assets/fonts/`. The variable fonts get their weight through `withWeight()`, which also sets the `wght` variation.

**Arabic rules.** Arabic is cursive, so **never apply letter-spacing or uppercase to Arabic**. Tracked styles (`sectionTitle`, `eyebrow`) drop their tracking in the Arabic locale, and media titles carry no tracking at all, because they can be in either script. Arabic line height is at least 1.5 for body text.

**Metadata format:** `year · genre · length` (e.g. `2023 · Drama · 3h`). There are no ratings anywhere (AGENTS.md). Numbers and durations are formatted with `intl` for the active locale.

## 3. Space, shape, motion

- **Spacing:** multiples of 4 (`4 8 12 16 20 24 32 40`). Screen gutter: 20 on phones, 32 at 600 dp and up, 48 at 1200 dp and up.
- **Radii:** 6 thumbnails · 10 posters · 12 rows and cards · 16 panels and hero · pill for buttons (height / 2).
- **Touch targets:** at least 44 × 44. The primary button is 48 tall.
- **Motion:** 150 ms ease-out for state changes and 250 ms for page transitions. Nothing loops except the loading indicator. Respect `MediaQuery.disableAnimations`.

## 4. The motif: marquee bulbs

A row of small `bulb` dots (4–6 px, gap 5–7 px, with an occasional dimmed dot) has three uses:
- **The loading indicator:** dots light in sequence. It replaces spinners and shimmer.
- **The hero frame:** dot rows above the banner.
- **Brand marks:** the logo, the splash screen and the header.

Use it sparingly. It is never a divider between every section.

## 5. Components

- **Poster card:** 2:3 image, radius 10, `title` below (1 line, ellipsis), then a `caption` with year · genre. The only badge is **4K** (`bulb` background, `onBulb` text, radius 4, at the top start corner). The placeholder is a plain `booth` block (no shimmer).
- **Hero (Home):** a `booth` panel (radius 16, padding 10). It holds a bulb-dot row, then the **wide banner cover at its real 2.7:1 ratio** (radius 8), then page bars (active is a wide `bulb` bar, the others short `velvetStrong` bars). Below the panel: `eyebrow` "NOW SHOWING", `heroTitle`, `caption` meta, then **Play** (primary) and a Favorite icon button.
- **Continue card:** `booth` row (radius 12, padding 8) with a 56 × 84 poster, title, "Season 2 · Episode 5", a 3 px progress bar (`velvet` track, `bulb` fill) and "14 min left".
- **Episode row:** `numeral` (bulb when in progress, `cream` when watched, `dustDim` when unwatched), then "Episode N" (the API has no episode titles), length, and progress when started. The current episode sits on `boothRaised`.
- **Buttons:** primary = `bulb` pill, `onBulb` label with an icon. Secondary = outlined pill (`velvetStrong` border, `cream` label). Icon button = 44 px circle, `booth` fill, `velvet` border.
- **Section header:** `sectionTitle` at the start edge, a "See all" link (`bulb`, `label`) at the end edge.
- **Navigation:** bottom bar (`navBar`, height 72, top border `boothRaised`) below 600 dp, `NavigationRail` from 600 dp. Active item = `bulb` icon and label, inactive = `dust`. Five destinations: Home, Continue, Favorites, Downloads, Settings.
- **Icons:** outlined, 1.8 px stroke, 22 px in navigation and 18 px in buttons.

## 6. Performance rules
- **Image sizes:**
  - **Lists** use `imgMediumThumbObjUrl` (293 × 439, ~40 KB).
  - **Details** use `imgObjUrl` (2000 × 3000, ~1.5 MB) **only** with `memCacheWidth` = displayed width × device pixel ratio.
  - **The hero** uses the banner cover, decoded at screen width × device pixel ratio.
- **No** `BackdropFilter`, shadows, `Opacity` animations over images, or `saveLayer` effects. Round images with `ClipRRect` only where needed, and everything else with `BoxDecoration.borderRadius`.
- **Lists:** horizontal rows use `ListView.builder` with a fixed `itemExtent` where possible. Use `const` widgets wherever possible.
- **Fonts:** bundled in the app (no runtime downloads). Variable fonts where available; for IBM Plex Sans Arabic, only Regular, Medium and SemiBold.

## 7. Logo (sketch: to be finalised)
The wordmark is **CINEMAKOM** (Big Shoulders Display 900, tracked +0.04 em) with **سينماكم** (Reem Kufi 700, `bulb`). The mark is a **ticket stub** (notched sides, a perforation, three bulb dots) carrying **ك**, the "your" in سينماكم: *your* ticket, *your* cinema.
