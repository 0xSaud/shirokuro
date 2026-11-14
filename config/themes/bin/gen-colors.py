#!/usr/bin/env python3
"""
Generate a Material 3 colour scheme from a wallpaper (or a fixed source colour)
and write it as JSON for the Quickshell panels to read.

No colour library needed. The pipeline is sRGB -> linear -> XYZ(D65) -> CIELAB
-> LCh, and every tone is gamut-mapped by reducing chroma until it lands inside
sRGB. Tone is CIELAB L*, which is the same axis Material's HCT uses, so the
tonal ramps line up with the Material 3 spec even though we skip CAM16.

Usage:
    gen-colors.py --image ~/Pictures/Wallpapers/x.jpg --out colors.json
    gen-colors.py --source '#8a5c3b' --out colors.json
    gen-colors.py --image x.jpg --print
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

# ---------------------------------------------------------------- colour maths

M_RGB2XYZ = np.array([
    [0.4123907992659595, 0.3575843393838780, 0.1804807884018343],
    [0.2126390058715104, 0.7151686787677559, 0.0721923153607337],
    [0.0193308187155918, 0.1191947797946259, 0.9505321522496608],
])
M_XYZ2RGB = np.linalg.inv(M_RGB2XYZ)
WHITE_D65 = np.array([0.95047, 1.00000, 1.08883])

EPS = 216.0 / 24389.0
KAPPA = 24389.0 / 27.0


def srgb_to_linear(c):
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.asarray(c, dtype=float)
    pos = np.clip(c, 0.0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * pos ** (1.0 / 2.4) - 0.055)


def rgb_to_lab(rgb):
    """rgb in 0..1, shape (..., 3) -> CIELAB."""
    xyz = srgb_to_linear(rgb) @ M_RGB2XYZ.T
    r = xyz / WHITE_D65
    f = np.where(r > EPS, np.cbrt(np.clip(r, 0, None)), (KAPPA * r + 16.0) / 116.0)
    return np.stack([
        116.0 * f[..., 1] - 16.0,
        500.0 * (f[..., 0] - f[..., 1]),
        200.0 * (f[..., 1] - f[..., 2]),
    ], axis=-1)


def lab_to_rgb(lab):
    """CIELAB -> rgb in 0..1 (may fall outside the gamut; caller decides)."""
    lab = np.asarray(lab, dtype=float)
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    fy = (L + 16.0) / 116.0
    fx = fy + a / 500.0
    fz = fy - b / 200.0

    def finv(t):
        t3 = t ** 3
        return np.where(t3 > EPS, t3, (116.0 * t - 16.0) / KAPPA)

    yr = np.where(L > KAPPA * EPS, ((L + 16.0) / 116.0) ** 3, L / KAPPA)
    xyz = np.stack([finv(fx), yr, finv(fz)], axis=-1) * WHITE_D65
    return linear_to_srgb(xyz @ M_XYZ2RGB.T)


def lab_to_lch(lab):
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    C = np.hypot(a, b)
    H = np.degrees(np.arctan2(b, a)) % 360.0
    return L, C, H


def lch_to_lab(L, C, H):
    rad = np.radians(H)
    return np.stack([np.asarray(L, dtype=float),
                     C * np.cos(rad),
                     C * np.sin(rad)], axis=-1)


def in_gamut(L, C, H, tol=1e-4):
    rgb = lab_to_rgb(lch_to_lab(L, C, H))
    return bool(np.all(rgb >= -tol) and np.all(rgb <= 1.0 + tol))


def lch_to_hex(L, C, H):
    """Gamut-mapped: keep L and H, shrink C until sRGB can represent it."""
    L = float(np.clip(L, 0.0, 100.0))
    if L <= 0.0:
        return "#000000"
    if L >= 100.0:
        return "#ffffff"
    best = C if in_gamut(L, C, H) else 0.0
    if best == 0.0 and C > 0.0:
        lo, hi = 0.0, float(C)
        for _ in range(24):
            mid = (lo + hi) / 2.0
            if in_gamut(L, mid, H):
                lo = mid
            else:
                hi = mid
        best = lo
    rgb = np.clip(lab_to_rgb(lch_to_lab(L, best, H)), 0.0, 1.0)
    r, g, b = (np.rint(rgb * 255.0).astype(int)).tolist()
    return "#%02x%02x%02x" % (r, g, b)


def hex_to_rgb01(s):
    s = s.strip().lstrip("#")
    if len(s) == 3:
        s = "".join(ch * 2 for ch in s)
    return np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


# ---------------------------------------------------------------- source colour

def kmeans_lab(points, k=6, iters=30, seed=0):
    """Plain Lloyd's with k-means++ seeding. Deterministic: same wallpaper in,
    same scheme out, so colours don't drift between runs."""
    rng = np.random.default_rng(seed)
    n = len(points)
    k = min(k, n)
    centres = [points[rng.integers(n)]]
    for _ in range(k - 1):
        d = np.min(((points[:, None, :] - np.array(centres)[None, :, :]) ** 2).sum(-1), axis=1)
        total = d.sum()
        if total <= 0:
            centres.append(points[rng.integers(n)])
            continue
        centres.append(points[rng.choice(n, p=d / total)])
    centres = np.array(centres, dtype=float)

    labels = np.zeros(n, dtype=int)
    for _ in range(iters):
        dist = ((points[:, None, :] - centres[None, :, :]) ** 2).sum(-1)
        new = dist.argmin(axis=1)
        if np.array_equal(new, labels):
            break
        labels = new
        for i in range(k):
            sel = points[labels == i]
            if len(sel):
                centres[i] = sel.mean(axis=0)
    counts = np.array([(labels == i).sum() for i in range(k)], dtype=float)
    return centres, counts / max(counts.sum(), 1)


def source_from_image(path, max_side=160):
    im = Image.open(path)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGBA", im.size, (0, 0, 0, 255))
        im = Image.alpha_composite(bg, im)
    im = im.convert("RGB")
    im.thumbnail((max_side, max_side))
    px = (np.asarray(im, dtype=float) / 255.0).reshape(-1, 3)

    lab = rgb_to_lab(px)
    L, C, _ = lab_to_lch(lab)
    # Ignore near-black and near-white pixels; they carry no usable hue and
    # would otherwise dominate a dark or washed-out wallpaper.
    keep = (L > 8.0) & (L < 94.0)
    cand = lab[keep] if keep.sum() >= 32 else lab

    centres, weights = kmeans_lab(cand, k=6)
    cl, cc, ch = lab_to_lch(centres)

    best_i, best_score = 0, -1e9
    for i in range(len(centres)):
        score = (cc[i] - 12.0) + weights[i] * 70.0
        if 90.0 <= ch[i] <= 111.0:      # muddy yellow-greens read badly as UI accents
            score -= 25.0
        if cc[i] < 8.0:                  # nearly grey, poor accent
            score -= 40.0
        if score > best_score:
            best_score, best_i = score, i

    hue = float(ch[best_i])
    chroma = float(cc[best_i])
    src_hex = lch_to_hex(float(cl[best_i]), chroma, hue)
    return src_hex, hue, chroma


def source_from_hex(s):
    lab = rgb_to_lab(hex_to_rgb01(s))
    L, C, H = lab_to_lch(lab)
    return s if s.startswith("#") else "#" + s, float(H), float(C)


# ---------------------------------------------------------------- M3 scheme

TONES = [0, 4, 6, 10, 12, 17, 20, 22, 24, 25, 30, 35, 40, 50, 60,
         70, 80, 87, 90, 92, 94, 95, 96, 98, 99, 100]


def tonal_palette(hue, chroma):
    return {str(t): lch_to_hex(float(t), float(chroma), float(hue)) for t in TONES}


# Terminal ANSI colours. Real hues, so red still reads as red, but each is
# nudged a fraction toward the scheme's hue so the terminal belongs to the theme
# instead of sitting next to it.
# Below this the a/b components are basically zero, so the hue that falls out of
# atan2 is noise. A greyscale wallpaper genuinely has no colour to take.
ACHROMATIC_CHROMA = 8.0

ANSI = [
    ("red",     22.0,  58.0),
    ("green",  142.0,  48.0),
    ("yellow",  85.0,  58.0),
    ("blue",   262.0,  48.0),
    ("magenta", 320.0, 48.0),
    ("cyan",   198.0,  44.0),
]


def ansi_block(hue, neutral, dark=True, pull=0.18, vivid=1.0):
    """color0-15 for kitty. `pull` is how far each hue drifts toward the source."""
    def toward(base):
        delta = ((hue - base + 540.0) % 360.0) - 180.0     # shortest way round
        return (base + delta * pull) % 360.0

    normal = 68.0 if dark else 44.0
    bright = 80.0 if dark else 56.0
    out = {}
    # 0 / 8 / 7 / 15 come from the neutral ramp so they sit on the background.
    out["color0"]  = neutral["20"] if dark else neutral["25"]
    out["color8"]  = neutral["40"] if dark else neutral["50"]
    out["color7"]  = neutral["80"] if dark else neutral["40"]
    out["color15"] = neutral["95"] if dark else neutral["20"]
    for i, (_, base, chroma) in enumerate(ANSI):
        h = toward(base)
        c = chroma * vivid
        out["color%d" % (i + 1)] = lch_to_hex(normal, c, h)
        out["color%d" % (i + 9)] = lch_to_hex(bright, c, h)
    return out


def build(source_hex, hue, chroma, vivid=1.0, harmony=30.0, deep=0.0, paper=0.0, mono=0.0):
    """Chroma targets sit above Material's default TonalSpot, because a single
    muted accent is what made the first pass read as one flat colour.

    The floor RAMPS with the source's own chroma instead of being fixed. A hard
    floor is what turned a black-and-white wallpaper into saturated blue: with no
    colour in the image the extracted hue is pure noise, and the floor then
    rendered that noise at full strength."""
    achromatic = chroma < ACHROMATIC_CHROMA
    if achromatic:
        # Nothing to take a hue from. Stay monochrome rather than invent one.
        hue = 250.0                      # fixed, so repeated runs do not drift
        c_primary = 7.0 * vivid
        c_secondary = 4.0 * vivid
        c_tertiary = 5.5 * vivid
    else:
        # chroma 8 -> floor 12, ramping to floor 34 by chroma 30. A nearly-grey
        # photo gets a nearly-grey UI; a vivid one still gets a vivid accent.
        t = min(1.0, (chroma - ACHROMATIC_CHROMA) / 22.0)
        floor = 12.0 + (34.0 - 12.0) * t
        c_primary = float(np.clip(chroma * 1.25, floor, 52.0)) * vivid
        c_secondary = float(np.clip(chroma / 3.0, floor / 2.4, 24.0)) * vivid
        c_tertiary = float(np.clip(chroma * 0.75, floor * 0.76, 44.0)) * vivid
    # How far the third accent rotates away from the source hue. Material's own
    # default is +60, which turns an orange source into a yellow-green tertiary —
    # a colour the user never asked for. Adjustable, defaulting to a rotation
    # small enough to stay in the same family.
    h_tertiary = (hue + harmony) % 360.0

    # "Mono" (ink) scheme: surfaces and the two side accents go to neutral
    # grey / cool steel, and only the primary keeps its colour. The result is
    # black, white and one accent, like ink on paper with a red seal.
    mono = max(0.0, min(1.0, float(mono)))
    n_chroma, nv_chroma = (1.5, 3.0) if achromatic else (6.0, 12.0)
    if mono > 0.0:
        n_chroma = n_chroma * (1.0 - mono) + 0.6 * mono
        nv_chroma = nv_chroma * (1.0 - mono) + 1.6 * mono
        c_secondary = c_secondary * (1.0 - mono) + 2.0 * mono
        c_tertiary = c_tertiary * (1.0 - mono) + 7.0 * mono
        h_tertiary = 250.0 if mono >= 0.5 else h_tertiary

    pal = {
        "primary": tonal_palette(hue, c_primary),
        "secondary": tonal_palette(hue, c_secondary),
        "tertiary": tonal_palette(h_tertiary, c_tertiary),
        # Surfaces go essentially grey for an achromatic source, otherwise they
        # carry a visible tint that the wallpaper never had.
        "neutral": tonal_palette(hue, n_chroma),
        "neutralVariant": tonal_palette(hue, nv_chroma),
        "error": tonal_palette(25.0, 84.0),
    }
    P, S, T = pal["primary"], pal["secondary"], pal["tertiary"]
    N, NV, E = pal["neutral"], pal["neutralVariant"], pal["error"]

    dark = {
        "primary": P["80"], "onPrimary": P["20"],
        "primaryContainer": P["30"], "onPrimaryContainer": P["90"],
        "secondary": S["80"], "onSecondary": S["20"],
        "secondaryContainer": S["30"], "onSecondaryContainer": S["90"],
        "tertiary": T["80"], "onTertiary": T["20"],
        "tertiaryContainer": T["30"], "onTertiaryContainer": T["90"],
        "error": E["80"], "onError": E["20"],
        "errorContainer": E["30"], "onErrorContainer": E["90"],
        "background": N["6"], "onBackground": N["90"],
        "surface": N["6"], "onSurface": N["90"],
        "surfaceVariant": NV["30"], "onSurfaceVariant": NV["80"],
        "surfaceDim": N["6"], "surfaceBright": N["24"],
        "surfaceContainerLowest": N["4"], "surfaceContainerLow": N["10"],
        "surfaceContainer": N["12"], "surfaceContainerHigh": N["17"],
        "surfaceContainerHighest": N["22"],
        "outline": NV["60"], "outlineVariant": NV["30"],
        "inverseSurface": N["90"], "inverseOnSurface": N["20"],
        "inversePrimary": P["40"],
        "shadow": "#000000", "scrim": "#000000",
    }
    light = {
        "primary": P["40"], "onPrimary": P["100"],
        "primaryContainer": P["90"], "onPrimaryContainer": P["10"],
        "secondary": S["40"], "onSecondary": S["100"],
        "secondaryContainer": S["90"], "onSecondaryContainer": S["10"],
        "tertiary": T["40"], "onTertiary": T["100"],
        "tertiaryContainer": T["90"], "onTertiaryContainer": T["10"],
        "error": E["40"], "onError": E["100"],
        "errorContainer": E["90"], "onErrorContainer": E["10"],
        "background": N["98"], "onBackground": N["10"],
        "surface": N["98"], "onSurface": N["10"],
        "surfaceVariant": NV["90"], "onSurfaceVariant": NV["30"],
        "surfaceDim": N["87"], "surfaceBright": N["98"],
        "surfaceContainerLowest": N["100"], "surfaceContainerLow": N["96"],
        "surfaceContainer": N["94"], "surfaceContainerHigh": N["92"],
        "surfaceContainerHighest": N["90"],
        "outline": NV["50"], "outlineVariant": NV["80"],
        "inverseSurface": N["20"], "inverseOnSurface": N["95"],
        "inversePrimary": P["80"],
        "shadow": "#000000", "scrim": "#000000",
    }
    # "Deep" accents. Material puts dark-scheme accents at tone 80, which turns
    # every earthy source (terracotta, ochre, olive) into a pastel. `deep` pulls
    # the dark primary and tertiary down toward the source's own weight, and
    # swaps the on-colour to tone 10 so text on them keeps its contrast.
    deep = max(0.0, min(1.6, float(deep)))   # above 1 = darker still (blood red, oxblood)
    if deep > 0.0:
        pt = 80.0 - 22.0 * deep
        tt = 80.0 - 9.0 * deep
        dark["primary"] = lch_to_hex(pt, c_primary, hue)
        dark["tertiary"] = lch_to_hex(tt, c_tertiary, h_tertiary)
        if pt < 72.0:
            dark["onPrimary"] = P["10"]
        if pt < 54.0:
            # Too dark for dark text: print on it in near-white instead.
            dark["onPrimary"] = P["98"]
        if tt < 72.0:
            dark["onTertiary"] = T["10"]

    # "Paper" light scheme. Material's light surfaces are near-white (tone 98)
    # with the source hue, which for a warm source reads as pink-white glare.
    # `paper` drops them to a sand tone and pulls the neutral hue toward
    # yellow, so the light scheme looks like unbleached paper with brown ink.
    paper = max(0.0, min(1.0, float(paper)))
    if paper > 0.0 and not achromatic:
        nh = hue + (82.0 - hue) * 0.85 * paper          # neutral hue -> sand
        def P_(tone, ch):
            return lch_to_hex(98.0 - (98.0 - tone) * paper, ch * paper, nh)
        light.update({
            "background": P_(91.0, 13.0), "surface": P_(91.0, 13.0),
            "surfaceBright": P_(94.0, 11.0), "surfaceDim": P_(83.0, 15.0),
            "surfaceContainerLowest": P_(94.5, 10.0),
            "surfaceContainerLow": P_(89.0, 14.0),
            "surfaceContainer": P_(87.0, 15.0),
            "surfaceContainerHigh": P_(84.0, 16.0),
            "surfaceContainerHighest": P_(80.5, 17.0),
            "surfaceVariant": P_(82.0, 16.0),
            "outlineVariant": P_(70.0, 16.0),
            "inverseOnSurface": P_(92.0, 11.0),
            "onBackground": lch_to_hex(13.0, 7.0, hue),
            "onSurface": lch_to_hex(13.0, 7.0, hue),
            "onSurfaceVariant": lch_to_hex(30.0, 12.0, hue),
            "outline": lch_to_hex(42.0, 14.0, hue),
            "inverseSurface": lch_to_hex(15.0, 7.0, hue),
            "primary": lch_to_hex(43.0, c_primary, hue),
            "primaryContainer": lch_to_hex(78.0, c_primary * 0.55, hue),
            "onPrimaryContainer": P["10"],
            "secondaryContainer": P_(78.0, 22.0),
            "onSecondaryContainer": lch_to_hex(13.0, 7.0, hue),
            "tertiary": lch_to_hex(42.0, c_tertiary, h_tertiary),
            "tertiaryContainer": lch_to_hex(80.0, c_tertiary * 0.75, h_tertiary),
            "onTertiaryContainer": T["10"],
            "error": E["40"],
        })

    # Ink scheme: "selected" containers stop being a block of accent colour and
    # become a reversed pale block, so the accent stays rare.
    if mono >= 0.5:
        dark["primaryContainer"] = N["90"]
        dark["onPrimaryContainer"] = N["10"]
        light["primaryContainer"] = N["20"]
        light["onPrimaryContainer"] = N["95"]

    return {
        "source": source_hex,
        "paper": paper,
        "deep": deep,
        "hue": round(hue, 2),
        "chroma": round(chroma, 2),
        "dark": dark,
        "light": light,
        "palettes": pal,
        "achromatic": bool(achromatic),
        "ansiDark":  ansi_block(hue, N, dark=True,  vivid=min(1.25, vivid)),
        "ansiLight": ansi_block(hue, N, dark=False, vivid=min(1.25, vivid)),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image")
    ap.add_argument("--source", help="hex colour, overrides --image")
    ap.add_argument("--out")
    ap.add_argument("--vivid", type=float, default=1.0,
                    help="chroma multiplier, 0.6 = muted, 1.4 = punchy")
    ap.add_argument("--harmony", type=float, default=30.0,
                    help="degrees the tertiary accent rotates from the source hue "
                         "(0 = one family, 60 = Material default, 180 = opposite)")
    ap.add_argument("--deep", type=float, default=0.0,
                    help="0 = Material pastel accents, 1 = deep earthy accents (dark scheme)")
    ap.add_argument("--mono", type=float, default=0.0,
                    help="1 = neutral grey surfaces and steel side accents; only the primary keeps colour")
    ap.add_argument("--paper", type=float, default=0.0,
                    help="0 = Material near-white light scheme, 1 = sand-paper light scheme")
    ap.add_argument("--print", dest="show", action="store_true")
    a = ap.parse_args()

    if a.source:
        src, hue, chroma = source_from_hex(a.source)
        mode = "manual"
    elif a.image:
        if not os.path.isfile(a.image):
            sys.exit("no such image: %s" % a.image)
        src, hue, chroma = source_from_image(a.image)
        mode = "wallpaper"
    else:
        sys.exit("need --image or --source")

    scheme = build(src, hue, chroma, vivid=max(0.2, a.vivid), harmony=a.harmony, deep=a.deep, paper=a.paper, mono=a.mono)
    scheme["mode"] = mode
    scheme["harmony"] = a.harmony
    if a.image:
        scheme["wallpaper"] = os.path.abspath(a.image)

    text = json.dumps(scheme, indent=2)
    if a.out:
        tmp = a.out + ".tmp"
        with open(tmp, "w") as fh:
            fh.write(text + "\n")
        os.replace(tmp, a.out)          # atomic, so the shell never reads a half file
    if a.show or not a.out:
        d = scheme["dark"]
        print("source %s   hue %.1f   chroma %.1f   (%s)" % (src, hue, chroma, mode))
        for k in ("background", "surfaceContainer", "primary", "secondary",
                  "tertiary", "onSurface", "outline"):
            print("  %-22s %s" % (k, d[k]))


if __name__ == "__main__":
    main()
