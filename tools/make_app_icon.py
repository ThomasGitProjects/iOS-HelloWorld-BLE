"""Render the app icon (1024x1024 PNGs) into the AppIcon asset catalog.

Pure standard library: shapes are signed distance fields, anti-aliased per pixel and written with zlib.
Run from the repository root:  python tools/make_app_icon.py
Outputs the default, dark and tinted variants referenced by AppIcon.appiconset/Contents.json.
"""

import math
import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024
OUT_DIR = Path(__file__).resolve().parent.parent / "HelloWorldBLEScanner" / "Assets.xcassets" / "AppIcon.appiconset"

# Bluetooth rune, centered, in normalized coordinates ([-1, 1], y pointing down).
H, W = 0.40, 0.21
RUNE = [(-W, -H / 2), (W, H / 2), (0.0, H), (0.0, -H), (W, -H / 2), (-W, H / 2)]
RUNE_HALF_WIDTH = 0.052

# Radio waves left and right of the rune: (radius, alpha).
RINGS = [(0.54, 1.0), (0.68, 0.72), (0.82, 0.45)]
RING_HALF_WIDTH = 0.030
RING_APERTURE = math.radians(34)

CYAN = (0.25, 0.88, 1.0)
WHITE = (1.0, 1.0, 1.0)
BG_STOPS = [(0.0, (0.02, 0.03, 0.09)), (0.55, (0.07, 0.12, 0.45)), (1.0, (0.36, 0.13, 0.71))]

PIXEL = 2.0 / SIZE


def seg_dist(px, py, ax, ay, bx, by):
    pax, pay, bax, bay = px - ax, py - ay, bx - ax, by - ay
    h = max(0.0, min(1.0, (pax * bax + pay * bay) / (bax * bax + bay * bay)))
    dx, dy = pax - bax * h, pay - bay * h
    return math.sqrt(dx * dx + dy * dy)


RUNE_SEGMENTS = list(zip(RUNE, RUNE[1:]))


def rune_dist(px, py):
    return min(seg_dist(px, py, a[0], a[1], b[0], b[1]) for a, b in RUNE_SEGMENTS) - RUNE_HALF_WIDTH


def arc_dist(px, py, radius):
    # Arcs mirrored around both axes, centered on the horizontal axis, with rounded caps.
    x, y = abs(px), abs(py)
    if math.atan2(y, x) < RING_APERTURE:
        d = abs(math.hypot(x, y) - radius)
    else:
        d = math.hypot(x - radius * math.cos(RING_APERTURE), y - radius * math.sin(RING_APERTURE))
    return d - RING_HALF_WIDTH


def coverage(d):
    return max(0.0, min(1.0, 0.5 - d / PIXEL))


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def background(u, v):
    t = max(0.0, min(1.0, (u + v) / 4 + 0.5))
    for (t0, c0), (t1, c1) in zip(BG_STOPS, BG_STOPS[1:]):
        if t <= t1:
            color = lerp(c0, c1, (t - t0) / (t1 - t0))
            break
    glow = 0.35 * math.exp(-(u * u + v * v) / 0.30)
    return tuple(min(1.0, c + k * glow) for c, k in zip(color, CYAN))


def over(dst, src, alpha):
    return tuple(d + (s - d) * alpha for d, s in zip(dst, src))


def render(variant):
    rows = []
    for j in range(SIZE):
        v = (j + 0.5) / SIZE * 2 - 1
        row = bytearray([0])  # PNG filter type: none
        for i in range(SIZE):
            u = (i + 0.5) / SIZE * 2 - 1
            d_rune = rune_dist(u, v)
            ring_alpha = 0.0
            d_ring_min = 9.0
            for radius, alpha in RINGS:
                d = arc_dist(u, v, radius)
                d_ring_min = min(d_ring_min, d)
                ring_alpha = max(ring_alpha, coverage(d) * alpha)
            rune_alpha = coverage(d_rune)

            if variant == "default":
                color = background(u, v)
                glow = 0.55 * math.exp(-max(d_rune, 0.0) / 0.07) + 0.30 * math.exp(-max(d_ring_min, 0.0) / 0.05)
                color = tuple(min(1.0, c + k * glow) for c, k in zip(color, CYAN))
                color = over(color, CYAN, ring_alpha)
                rune_color = lerp(WHITE, (0.80, 0.96, 1.0), max(0.0, min(1.0, (v + H) / (2 * H))))
                color = over(color, rune_color, rune_alpha)
                a = 1.0
            elif variant == "dark":
                # Transparent background; iOS supplies the dark backdrop.
                a = max(ring_alpha, rune_alpha)
                color = WHITE if a == 0 else lerp(CYAN, WHITE, rune_alpha / a)
            else:  # tinted: opaque grayscale, iOS applies the user's tint.
                gray = over((0.0,), (0.75,), ring_alpha)
                gray = over(gray, (1.0,), rune_alpha)
                color, a = (gray[0],) * 3, 1.0

            row += bytes(round(c * 255) for c in color)
            if variant == "dark":
                row.append(round(a * 255))
        rows.append(bytes(row))
        if j % 128 == 0:
            print(f"  {variant}: row {j}/{SIZE}", file=sys.stderr)
    return b"".join(rows)


def write_png(path, raw, alpha):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    # 8-bit RGBA for the transparent dark variant, RGB otherwise (App Store rejects alpha in opaque icons).
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6 if alpha else 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    variants = sys.argv[1:] or ["default", "dark", "tinted"]
    for name in variants:
        out = OUT_DIR / f"AppIcon-{name}.png"
        write_png(out, render(name), alpha=name == "dark")
        print(f"wrote {out}")
