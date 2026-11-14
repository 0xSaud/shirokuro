#!/usr/bin/env python3
"""
Draw the "Sadu" wallpaper: a dark clay field with bands of woven geometry
(diamonds, stepped triangles, stitched lines) in the current palette.

It reads ~/.config/quickshell/colors.json, so re-running it after a colour
change produces a wallpaper that matches the new scheme.

    gen-wallpaper.py                       # 1920x1080 -> ~/Pictures/Wallpapers/sadu.png
    gen-wallpaper.py --size 2560x1440 --out /tmp/x.png
"""
import argparse
import json
import os
import random

from PIL import Image, ImageDraw, ImageFilter

HOME = os.path.expanduser("~")
COLORS = os.path.join(HOME, ".config/quickshell/colors.json")


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diamond(d, cx, cy, r, fill=None, outline=None, width=1):
    pts = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    d.polygon(pts, fill=fill, outline=outline, width=width) if outline else d.polygon(pts, fill=fill)


def band_diamonds(d, y, h, x0, x1, cols, step):
    """A row of nested diamonds."""
    r = h / 2
    cy = y + r
    x = x0 + step / 2
    i = 0
    while x < x1:
        diamond(d, x, cy, r, fill=cols[i % len(cols)])
        diamond(d, x, cy, r * 0.56, fill=cols[(i + 1) % len(cols)])
        diamond(d, x, cy, r * 0.22, fill=cols[(i + 2) % len(cols)])
        x += step
        i += 1


def band_teeth(d, y, h, x0, x1, col, step, up=True):
    """Stepped triangles, the 'teeth' that edge a Sadu band."""
    x = x0
    while x < x1:
        if up:
            d.polygon([(x, y + h), (x + step / 2, y), (x + step, y + h)], fill=col)
        else:
            d.polygon([(x, y), (x + step / 2, y + h), (x + step, y)], fill=col)
        x += step


def band_stitch(d, y, x0, x1, col, dash=10, gap=8, w=2):
    x = x0
    while x < x1:
        d.rectangle([x, y, min(x + dash, x1), y + w - 1], fill=col)
        x += dash + gap


def band_zigzag(d, y, h, x0, x1, col, step, w=3):
    pts = []
    x = x0
    up = True
    while x <= x1 + step:
        pts.append((x, y if up else y + h))
        x += step / 2
        up = not up
    d.line(pts, fill=col, width=w, joint="curve")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--out", default=os.path.join(HOME, "Pictures/Wallpapers/sadu.png"))
    a = ap.parse_args()
    W, H = (int(v) for v in a.size.lower().split("x"))
    SS = 2                                   # supersample for clean diagonals
    w, h = W * SS, H * SS

    scheme = "dark"
    try:
        scheme = json.load(open(os.path.join(HOME, ".config/quickshell/settings.json"))).get("scheme", "dark")
    except Exception:
        pass
    allc = json.load(open(COLORS))
    c = allc[scheme] if scheme in allc else allc["dark"]
    if scheme == "light":
        # Paper-cut: the desktop is the table the paper sheets lie on, so it is
        # a terracotta field. Windows are sand and their shadows are ink; both
        # have to read against it, which a sand or a near-black field would not
        # allow.
        paper = rgb(c["surface"])
        ink = rgb(c["onSurface"])
        accent = rgb(c["primary"])
        bg = mix(accent, paper, 0.16)
        clay = mix(accent, paper, 0.26)
        line = mix(bg, ink, 0.30)
        prim = paper
        deep = mix(accent, ink, 0.55)
        gold = rgb(c["tertiaryContainer"])
        sand = paper
        edge_dark = mix(bg, ink, 0.35)
    else:
        bg = rgb(c["surfaceContainerLowest"])
        clay = rgb(c["surface"])
        line = rgb(c["outlineVariant"])
        prim = rgb(c["primary"])
        deep = rgb(c["primaryContainer"])
        gold = rgb(c["tertiary"])
        sand = rgb(c["onSurface"])
        edge_dark = mix(bg, (0, 0, 0), 0.5)

    im = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(im)

    # Soft vertical falloff so the field is not one flat colour.
    for y in range(h):
        t = abs(y / h - 0.5) * 2
        d.line([(0, y), (w, y)], fill=mix(clay, bg, t ** 1.4))

    # Faint all-over weave: a diamond lattice barely above the background.
    lat = mix(clay, line, 0.30)
    g = 54 * SS
    for x in range(-h, w + h, g):
        d.line([(x, 0), (x + h, h)], fill=lat, width=SS)
        d.line([(x, h), (x + h, 0)], fill=lat, width=SS)

    # The main woven strip, set below centre so windows and the rail sit on
    # quiet ground and the pattern shows in the gaps.
    u = 13 * SS                              # base unit
    cy = int(h * 0.60)
    x0, x1 = 0, w

    def strip(top, height, col):
        d.rectangle([x0, top, x1, top + height], fill=col)

    y = cy - 15 * u
    band_stitch(d, y, x0, x1, mix(bg, sand, 0.35), dash=u, gap=u, w=SS * 2)
    y += 2 * u
    band_teeth(d, y, 2 * u, x0, x1, deep, 2 * u, up=True)
    y += 2 * u
    strip(y, u // 2, deep)
    y += u
    band_zigzag(d, y, 3 * u, x0, x1, gold, 6 * u, w=SS * 3)
    y += 4 * u
    strip(y, SS * 2, line)
    y += u
    band_diamonds(d, y, 8 * u, x0, x1, [prim, bg, gold], 8 * u)
    y += 9 * u
    strip(y, SS * 2, line)
    y += u
    band_zigzag(d, y, 3 * u, x0, x1, gold, 6 * u, w=SS * 3)
    y += 4 * u
    strip(y, u // 2, deep)
    y += u // 2
    band_teeth(d, y, 2 * u, x0, x1, deep, 2 * u, up=False)
    y += 4 * u
    band_stitch(d, y, x0, x1, mix(bg, sand, 0.35), dash=u, gap=u, w=SS * 2)

    # A thin echo of the strip near the top.
    y = int(h * 0.12)
    band_stitch(d, y, x0, x1, line, dash=u, gap=u, w=SS * 2)
    band_teeth(d, y + u, u, x0, x1, mix(bg, deep, 0.7), u, up=False)

    im = im.resize((W, H), Image.LANCZOS)

    # Woven-cloth grain: fine noise, slightly blurred, at low strength.
    random.seed(7)
    noise = Image.effect_noise((W, H), 22).convert("L").filter(ImageFilter.GaussianBlur(0.6))
    grain = Image.merge("RGB", (noise, noise, noise))
    im = Image.blend(im, Image.blend(im, grain, 0.5), 0.10)

    # Vignette so the edges fall away behind the rail and gaps.
    vig = Image.new("L", (W, H), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-W * 0.25, -H * 0.35, W * 1.25, H * 1.35], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(W * 0.12))
    dark = Image.new("RGB", (W, H), edge_dark)
    im = Image.composite(im, dark, vig)

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    im.save(a.out)
    print(a.out)


if __name__ == "__main__":
    main()
