#!/usr/bin/env python3
"""
Draw the personal seal: a red hanko-style stamp carved with the handle, laid
out the way a name seal is, in a grid read top to bottom.

It is the launcher button on the bar, the mark on the fastfetch picture and
the lock screen. Colour comes from the current palette's primary.

    gen-seal.py                 # "reouii" -> ~/.config/quickshell/assets/seal.png
    gen-seal.py --text saud --size 512
"""
import argparse
import json
import os
import random
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

HOME = os.path.expanduser("~")
COLORS = os.path.join(HOME, ".config/quickshell/colors.json")


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def font_file(pattern):
    try:
        out = subprocess.run(["fc-match", "-f", "%{file}", pattern],
                             capture_output=True, text=True, timeout=5).stdout.strip()
        return out if out and os.path.isfile(out) else None
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--text", default=os.environ.get("USER", "reouii"))
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--out", default=os.path.join(HOME, ".config/quickshell/assets/seal.png"))
    ap.add_argument("--color", default=None)
    a = ap.parse_args()

    col = a.color
    if not col:
        try:
            col = json.load(open(COLORS))["dark"]["primary"]
        except Exception:
            col = "#ce4539"
    red = rgb(col)

    S = a.size
    text = a.text.upper()
    # Lay the letters out two to a row, like characters in a square seal.
    rows = [text[i:i + 2] for i in range(0, len(text), 2)]
    n = len(rows)

    # Alpha mask: the stamp body, then the letters and an inner frame cut out.
    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)
    m = int(S * 0.04)
    d.rounded_rectangle([m, m, S - m, S - m], radius=int(S * 0.13), fill=255)

    cut = Image.new("L", (S, S), 0)
    c = ImageDraw.Draw(cut)
    f = int(S * 0.115)
    c.rounded_rectangle([f, f, S - f, S - f], radius=int(S * 0.07), outline=255, width=max(2, int(S * 0.018)))

    path = font_file("Montserrat:weight=800") or font_file("Open Sans:bold") or font_file("sans:bold")
    inner = S - 2 * int(S * 0.19)
    row_h = inner / n
    fsize = int(row_h * 0.92)
    font = ImageFont.truetype(path, fsize) if path else ImageFont.load_default()
    top = int(S * 0.19)
    for i, row in enumerate(rows):
        cell = inner / max(1, len(row))
        for j, ch in enumerate(row):
            bb = c.textbbox((0, 0), ch, font=font)
            w, h = bb[2] - bb[0], bb[3] - bb[1]
            x = int(S * 0.19) + cell * j + (cell - w) / 2 - bb[0]
            y = top + row_h * i + (row_h - h) / 2 - bb[1]
            c.text((x, y), ch, font=font, fill=255)
    mask = ImageChops.subtract(mask, cut)

    # Worn ink: speckle out some of the stamp and roughen its edge.
    random.seed(11)
    wear = Image.effect_noise((S, S), 60).filter(ImageFilter.GaussianBlur(S / 300))
    wear = wear.point(lambda v: 0 if v > 205 else 255)
    mask = ImageChops.multiply(mask, wear)
    mask = mask.filter(ImageFilter.GaussianBlur(S / 400))
    mask = mask.point(lambda v: 255 if v > 118 else 0).filter(ImageFilter.GaussianBlur(S / 700))

    out = Image.new("RGBA", (S, S), red + (0,))
    out.putalpha(mask)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    out.save(a.out)
    print(a.out)


if __name__ == "__main__":
    main()
