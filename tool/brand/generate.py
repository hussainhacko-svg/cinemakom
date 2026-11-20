#!/usr/bin/env python3
"""Generates every Cinemakom logo asset from one master drawing.

    python3 tool/brand/generate.py

Needs fontTools, rsvg-convert and ImageMagick (`magick`). The mark is a ticket
stub with ك knocked out (docs/DESIGN.md §7), drawn in a 100×100 design space.
ك is traced from Reem Kufi Bold, so no output depends on the font being
installed. Three levels of detail keep it clean at every size:

  full  — perforation + ك    (≥ 48 px)
  small — ك only, larger      (24–47 px)
  tiny  — silhouette          (< 24 px)

Outputs (all regenerated, never edit them by hand):
  branding/*.svg                         masters (with and without the tile)
  lib/app/brand/brand_paths.g.dart       paths for the in-app CinemakomMark
  android/app/src/main/res/...           adaptive, monochrome, legacy, splash
  ios/Runner/Assets.xcassets/...         AppIcon set, LaunchImage
  windows/runner/resources/app_icon.ico  16–256 px
  linux/packaging/icons/...              hicolor PNGs + scalable SVG
  assets/brand/app_icon_256.png          Linux window icon (bundled)
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from fontTools.pens.basePen import BasePen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parents[2]
NIGHT = '#15100C'
BULB = '#F4B740'

# ---- geometry (100×100 design space) ----------------------------------------

def ticket(x0, y0, x1, y1, r, notch):
    """Rounded rectangle with a semicircular notch in the middle of each side."""
    cy = (y0 + y1) / 2
    return (f'M{x0 + r} {y0} H{x1 - r} A{r} {r} 0 0 1 {x1} {y0 + r} '
            f'V{cy - notch} A{notch} {notch} 0 0 0 {x1} {cy + notch} '
            f'V{y1 - r} A{r} {r} 0 0 1 {x1 - r} {y1} H{x0 + r} '
            f'A{r} {r} 0 0 1 {x0} {y1 - r} V{cy + notch} '
            f'A{notch} {notch} 0 0 0 {x0} {cy - notch} V{y0 + r} '
            f'A{r} {r} 0 0 1 {x0 + r} {y0} Z')

def circle(cx, cy, r):
    return f'M{cx - r} {cy} A{r} {r} 0 1 0 {cx + r} {cy} A{r} {r} 0 1 0 {cx - r} {cy} Z'

TICKET = ticket(12, 24, 88, 76, 6, 7)
TICKET_TINY = ticket(8, 20, 92, 80, 6, 9)  # bolder silhouette for 16 px
PERFORATION = ' '.join(circle(68, 31 + i * 6.5, 1.6) for i in range(7))


def kaf_path(center_x, center_y, height):
    """ك from Reem Kufi Bold, scaled to `height` and centred, as SVG path data."""
    font = TTFont(ROOT / 'assets/fonts/ReemKufi-Variable.ttf')
    font = instancer.instantiateVariableFont(font, {'wght': 700})
    glyphs = font.getGlyphSet()
    name = font.getBestCmap()[0x0643]
    from fontTools.pens.boundsPen import BoundsPen
    bounds = BoundsPen(glyphs)
    glyphs[name].draw(bounds)
    xmin, ymin, xmax, ymax = bounds.bounds
    scale = height / (ymax - ymin)
    # Font units are y-up; flip and centre the bounding box on (center_x, center_y).
    dx = center_x - (xmin + xmax) / 2 * scale
    dy = center_y + (ymin + ymax) / 2 * scale
    pen = _SegmentPen(glyphs)
    glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, dx, dy)))
    return _to_svg(_union(pen.contours)), (xmax - xmin) * scale


# ---- outline union -------------------------------------------------------------
# The font draws ك as overlapping contours (fine under the font's non-zero fill).
# The mark knocks ك out with an even-odd fill, where an overlap would flip back to
# solid, so the contours are merged into one outline first.

class _SegmentPen(BasePen):
    """Collects each contour as segments: ('L', p0, p1) or ('Q', p0, c, p1)."""

    def __init__(self, glyphs):
        super().__init__(glyphs)
        self.contours = []

    def _moveTo(self, p):
        self.contours.append([])
        self._start = self._cur = p

    def _lineTo(self, p):
        if p != self._cur:
            self.contours[-1].append(('L', self._cur, p))
        self._cur = p

    def _qCurveToOne(self, c, p):
        self.contours[-1].append(('Q', self._cur, c, p))
        self._cur = p

    def _curveToOne(self, c1, c2, p):
        raise ValueError('cubic outlines are not supported')

    def _closePath(self):
        self._lineTo(self._start)

    _endPath = _closePath


def _flatten(seg, n=16):
    if seg[0] == 'L':
        (x0, y0), (x1, y1) = seg[1], seg[2]
        return [(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n) for i in range(n + 1)]
    _, p0, c, p1 = seg
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1])
            for t in (i / n for i in range(n + 1))]


def _cross(a0, a1, b0, b1):
    """Parameters (t, u) where segment a0–a1 meets b0–b1, or None."""
    rx, ry = a1[0] - a0[0], a1[1] - a0[1]
    sx, sy = b1[0] - b0[0], b1[1] - b0[1]
    den = rx * sy - ry * sx
    if abs(den) < 1e-12:
        return None
    qx, qy = b0[0] - a0[0], b0[1] - a0[1]
    t, u = (qx * sy - qy * sx) / den, (qx * ry - qy * rx) / den
    return (t, u) if 1e-9 < t < 1 - 1e-9 and 1e-9 < u < 1 - 1e-9 else None


def _inside(p, contour):
    poly = [q for seg in contour for q in _flatten(seg, 1 if seg[0] == 'L' else 16)[:-1]]
    hit = False
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if (y0 > p[1]) != (y1 > p[1]) and p[0] < x0 + (p[1] - y0) * (x1 - x0) / (y1 - y0):
            hit = not hit
    return hit


def _union(contours):
    """Merges outer contours (no holes) whose crossings are all on straight edges."""
    cuts = [[[] for _ in c] for c in contours]  # (t, point) splits per segment
    for i, ci in enumerate(contours):
        for j in range(i + 1, len(contours)):
            for a, sa in enumerate(ci):
                for b, sb in enumerate(contours[j]):
                    pa, pb = _flatten(sa, 1 if sa[0] == 'L' else 16), _flatten(sb, 1 if sb[0] == 'L' else 16)
                    for k in range(len(pa) - 1):
                        for m in range(len(pb) - 1):
                            hit = _cross(pa[k], pa[k + 1], pb[m], pb[m + 1])
                            if not hit:
                                continue
                            if sa[0] != 'L' or sb[0] != 'L':
                                raise ValueError('ك contours cross on a curve; '
                                                 'extend _union to split curves')
                            t, u = hit
                            p = (sa[1][0] + t * (sa[2][0] - sa[1][0]),
                                 sa[1][1] + t * (sa[2][1] - sa[1][1]))
                            cuts[i][a].append((t, p))
                            cuts[j][b].append((u, p))
    # Split at the crossings, keep the pieces outside every other contour.
    kept = []
    for i, contour in enumerate(contours):
        for seg, seg_cuts in zip(contour, cuts[i]):
            if seg[0] == 'Q':
                pieces = [seg]
            else:
                pts = [seg[1], *(p for _, p in sorted(seg_cuts)), seg[2]]
                pieces = [('L', a, b) for a, b in zip(pts, pts[1:])]
            for piece in pieces:
                mid = _flatten(piece, 2)[1]
                if not any(_inside(mid, other)
                           for j, other in enumerate(contours) if j != i):
                    kept.append(piece)
    # Chain the pieces back into closed loops.
    key = lambda p: (round(p[0], 6), round(p[1], 6))
    starts = {key(seg[1]): seg for seg in kept}
    loops = []
    while starts:
        first = next(iter(starts))
        loop, at = [], first
        while True:
            seg = starts.pop(at)
            loop.append(seg)
            at = key(seg[-1])
            if at == first:
                break
        loops.append(loop)
    return loops


def _to_svg(contours):
    n = lambda v: f'{v:.2f}'.rstrip('0').rstrip('.')
    pt = lambda p: f'{n(p[0])} {n(p[1])}'
    out = []
    for contour in contours:
        out.append(f'M{pt(contour[0][1])}')
        for seg in contour[:-1] if contour[-1][0] == 'L' else contour:
            out.append(f'L{pt(seg[2])}' if seg[0] == 'L' else f'Q{pt(seg[2])} {pt(seg[3])}')
        out.append('Z')
    return ''.join(out)


KAF_FULL, KAF_FULL_W = kaf_path(39.5, 50, 28)
KAF_SMALL, KAF_SMALL_W = kaf_path(49, 50, 34)

# Each detail level is one even-odd path: the ticket with holes cut out.
DETAIL = {
    'full': f'{TICKET} {PERFORATION} {KAF_FULL}',
    'small': f'{TICKET} {KAF_SMALL}',
    'tiny': TICKET_TINY,
}


def svg(detail, *, tile=False, scale=1.0, fill=BULB, tile_radius=0):
    """A 100×100 SVG of the mark. `scale` shrinks it around the centre."""
    t = f' transform="translate(50 50) scale({scale}) translate(-50 -50)"' if scale != 1 else ''
    bg = (f'<rect width="100" height="100" rx="{tile_radius}" fill="{NIGHT}"/>' if tile else '')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">{bg}'
            f'<path{t} fill="{fill}" fill-rule="evenodd" d="{DETAIL[detail]}"/></svg>\n')


def detail_for(px):
    return 'full' if px >= 48 else 'small' if px >= 24 else 'tiny'


def png(svg_text, px, dest, *, opaque=False):
    """Renders `svg_text` to a px×px PNG at `dest`."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', suffix='.svg', delete=False) as f:
        f.write(svg_text)
    try:
        subprocess.run(['rsvg-convert', '-w', str(px), '-h', str(px), f.name, '-o', str(dest)], check=True)
        if opaque:  # iOS rejects icons with an alpha channel.
            subprocess.run(['magick', str(dest), '-background', NIGHT, '-alpha', 'remove', '-alpha', 'off', str(dest)], check=True)
    finally:
        os.unlink(f.name)


# ---- Android ------------------------------------------------------------------

def vector_drawable(detail, size_dp, scale, color='#FF' + BULB[1:]):
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/brand/generate.py. Do not edit. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="{size_dp}dp" android:height="{size_dp}dp"
    android:viewportWidth="100" android:viewportHeight="100">
    <group android:pivotX="50" android:pivotY="50" android:scaleX="{scale}" android:scaleY="{scale}">
        <path android:fillType="evenOdd" android:fillColor="{color}"
            android:pathData="{DETAIL[detail]}"/>
    </group>
</vector>
"""


def android():
    res = ROOT / 'android/app/src/main/res'
    (res / 'drawable').mkdir(parents=True, exist_ok=True)
    # Adaptive icon: only the central 66/108 dp is safe, so the ticket is 0.62.
    (res / 'drawable/ic_launcher_foreground.xml').write_text(vector_drawable('full', 108, 0.62))
    (res / 'drawable/ic_launcher_monochrome.xml').write_text(vector_drawable('full', 108, 0.62, '#FFFFFFFF'))
    # Splash (Android 12+): the icon shows inside a 160 dp circle of 240 dp.
    (res / 'drawable/splash_icon.xml').write_text(vector_drawable('full', 240, 0.68))
    # Splash before Android 12: the mark centred on Night.
    (res / 'drawable/splash_mark.xml').write_text(vector_drawable('full', 120, 1.0))
    launch = """<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/brand/generate.py. Do not edit. -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/night" />
    <item android:drawable="@drawable/splash_mark" android:gravity="center"
        android:width="120dp" android:height="120dp" />
</layer-list>
"""
    for folder in ('drawable', 'drawable-v21'):
        (res / folder).mkdir(exist_ok=True)
        (res / folder / 'launch_background.xml').write_text(launch)
    (res / 'mipmap-anydpi-v26').mkdir(exist_ok=True)
    (res / 'mipmap-anydpi-v26/ic_launcher.xml').write_text("""<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/brand/generate.py. Do not edit. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/night" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
""")
    (res / 'values/colors.xml').write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/brand/generate.py. Do not edit. -->
<resources>
    <color name="night">#FF{NIGHT[1:]}</color>
</resources>
""")
    # One theme: the launch window and the window behind Flutter are Night.
    styles = """<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/brand/generate.py. Do not edit. -->
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:statusBarColor">@color/night</item>
        <item name="android:navigationBarColor">@color/night</item>%s
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@color/night</item>
    </style>
</resources>
"""
    (res / 'values/styles.xml').write_text(styles % '')
    (res / 'values-v31').mkdir(exist_ok=True)
    (res / 'values-v31/styles.xml').write_text(styles % """
        <item name="android:windowSplashScreenBackground">@color/night</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_icon</item>""")
    night = res / 'values-night'
    if night.exists():  # Night mode would override the v31 splash; one theme anyway.
        for f in night.iterdir():
            f.unlink()
        night.rmdir()
    # Legacy launchers (before Android 8) use these PNGs.
    for folder, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        png(svg(detail_for(px), tile=True, scale=0.8, tile_radius=20), px, res / f'mipmap-{folder}/ic_launcher.png')
    # Play Store listing icon (Google applies its own mask).
    png(svg('full', tile=True, scale=0.72), 512, ROOT / 'branding/store/play-store-512.png', opaque=True)
    # Android TV home-screen banner (320×180 dp → 640×360 px at xhdpi).
    tv_svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 180">'
        f'<rect width="320" height="180" fill="{NIGHT}"/>'
        f'<g transform="translate(95 25) scale(1.3)">'
        f'<path fill="{BULB}" fill-rule="evenodd" d="{DETAIL["full"]}"/>'
        f'</g></svg>\n'
    )
    tv_dest = res / 'drawable-xhdpi/tv_banner.png'
    tv_dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', suffix='.svg', delete=False) as f:
        f.write(tv_svg)
    try:
        subprocess.run(['rsvg-convert', '-w', '640', '-h', '360', f.name, '-o', str(tv_dest)], check=True)
        subprocess.run(['magick', str(tv_dest), '-background', NIGHT, '-alpha', 'remove', '-alpha', 'off', str(tv_dest)], check=True)
    finally:
        os.unlink(f.name)


# ---- iOS ----------------------------------------------------------------------

def ios():
    icons = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for image in json.loads((icons / 'Contents.json').read_text())['images']:
        px = round(float(image['size'].split('x')[0]) * int(image['scale'][0]))
        png(svg(detail_for(px), tile=True, scale=0.86), px, icons / image['filename'], opaque=True)
    launch = ROOT / 'ios/Runner/Assets.xcassets/LaunchImage.imageset'
    for name, px in [('LaunchImage.png', 120), ('LaunchImage@2x.png', 240), ('LaunchImage@3x.png', 360)]:
        png(svg('full'), px, launch / name)
    board = ROOT / 'ios/Runner/Base.lproj/LaunchScreen.storyboard'
    r, g, b = (int(NIGHT[i:i + 2], 16) / 255 for i in (1, 3, 5))
    text = re.sub(r'<color key="backgroundColor"[^>]*/>',
                  f'<color key="backgroundColor" red="{r:.4f}" green="{g:.4f}" blue="{b:.4f}" alpha="1" '
                  'colorSpace="custom" customColorSpace="sRGB"/>', board.read_text())
    board.write_text(text)


def macos():
    icons = ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    if not icons.exists():
        return
    for px in (16, 32, 64, 128, 256, 512, 1024):
        png(svg(detail_for(px), tile=True, scale=0.8, tile_radius=22), px, icons / f'app_icon_{px}.png')


# ---- Windows and Linux --------------------------------------------------------

def windows():
    with tempfile.TemporaryDirectory() as tmp:
        files = []
        for px in (16, 24, 32, 48, 64, 128, 256):
            dest = Path(tmp) / f'{px}.png'
            png(svg(detail_for(px)), px, dest)  # Windows icons have no tile.
            files.append(str(dest))
        subprocess.run(['magick', *files, str(ROOT / 'windows/runner/resources/app_icon.ico')], check=True)


APP_ID = 'io.github.sharon_xa.cinemakom'


def linux():
    base = ROOT / 'linux/packaging/icons/hicolor'
    for px in (16, 24, 32, 48, 64, 128, 256, 512):
        png(svg(detail_for(px), tile=True, scale=0.8, tile_radius=22), px, base / f'{px}x{px}/apps/{APP_ID}.png')
    (base / 'scalable/apps').mkdir(parents=True, exist_ok=True)
    (base / f'scalable/apps/{APP_ID}.svg').write_text(svg('full', tile=True, scale=0.8, tile_radius=22))
    # Window icon for development runs (loaded by linux/runner/my_application.cc).
    png(svg('full', tile=True, scale=0.8, tile_radius=22), 256, ROOT / 'assets/brand/app_icon_256.png')


# ---- Dart ---------------------------------------------------------------------

_TOKEN = re.compile(r'[MLHVQCAZ]|-?\d*\.?\d+(?:e-?\d+)?')


def path_ops(d):
    """SVG path data (absolute M L H V Q C A Z) → flat op list for Dart."""
    tokens = _TOKEN.findall(d)
    ops, i, cmd, cur, start = [], 0, None, (0.0, 0.0), (0.0, 0.0)

    def num():
        nonlocal i
        i += 1
        return float(tokens[i - 1])

    while i < len(tokens):
        if tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
        if cmd == 'M':
            cur = start = (num(), num()); ops += [0, *cur]; cmd = 'L'
        elif cmd == 'L':
            cur = (num(), num()); ops += [1, *cur]
        elif cmd == 'H':
            cur = (num(), cur[1]); ops += [1, *cur]
        elif cmd == 'V':
            cur = (cur[0], num()); ops += [1, *cur]
        elif cmd == 'Q':
            c = (num(), num()); cur = (num(), num()); ops += [2, *c, *cur]
        elif cmd == 'C':
            c1 = (num(), num()); c2 = (num(), num()); cur = (num(), num()); ops += [3, *c1, *c2, *cur]
        elif cmd == 'A':
            r = num(); num(); num(); large = num(); sweep = num(); cur = (num(), num())
            ops += [4, *cur, r, large, sweep]
        elif cmd == 'Z':
            ops += [5]; cur = start; cmd = None
        else:
            raise ValueError(f'unsupported path command {cmd!r}')
    return ops


def dart():
    def fmt(ops):
        nums = ', '.join(f'{v:g}' for v in ops)
        return '\n'.join('    ' + line for line in _wrap(nums))
    body = '\n\n'.join(f"""/// The "{name}" mark in a 100×100 box.
const {name}MarkOps = <double>[
{fmt(path_ops(d))}
];""" for name, d in DETAIL.items())
    out = ROOT / 'lib/app/brand/brand_paths.g.dart'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(f"""// Generated by tool/brand/generate.py. Do not edit.
//
// Ops: 0 moveTo(x, y) · 1 lineTo(x, y) · 2 quadTo(cx, cy, x, y)
//      3 cubicTo(c1x, c1y, c2x, c2y, x, y) · 4 arcTo(x, y, r, large, clockwise)
//      5 close. Fill with PathFillType.evenOdd.
// ignore_for_file: lines_longer_than_80_chars

{body}
""")


def _wrap(text, width=74):
    line = ''
    for part in text.split(', '):
        if len(line) + len(part) + 2 > width:
            yield line + ','
            line = part
        else:
            line = f'{line}, {part}' if line else part
    if line:
        yield line + ','


def main():
    out = ROOT / 'branding'
    out.mkdir(exist_ok=True)
    for detail in DETAIL:
        (out / f'mark-{detail}.svg').write_text(svg(detail))
    (out / 'app-icon.svg').write_text(svg('full', tile=True, scale=0.86))
    for step in (android, ios, macos, windows, linux, dart):
        step()
        print('✓', step.__name__)
    print(f'kaf width: full {KAF_FULL_W:.1f}, small {KAF_SMALL_W:.1f} (main field is 56 wide)')


if __name__ == '__main__':
    main()
