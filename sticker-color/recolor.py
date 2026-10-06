"""Recolor the teal in the Sarasota County "Protect Paradise" sticker.

Shifts every teal pixel (hue 150-200, including soft edges) by a hue offset and a
lightness lift that tapers to zero at black and white, so anti-aliased edges stay
clean. Output is cropped to the circle (transparent corners), tagged sRGB, and
sized for a 3.069 in sticker.

Usage:
  python3 -I recolor.py SOURCE.webp OUT.png --hue -6 --lift 0.07
  python3 -I recolor.py SOURCE.webp SHEET.png --sheet -6 0 7 14 --lift 0.07
"""
import argparse
import colorsys

import numpy as np
from PIL import Image, ImageCms, ImageDraw, ImageFont

STICKER_IN = 3.069
BASE_TEAL = (71, 149, 140)  # original file teal, #47958C


def recolor(src, hue_shift, lift):
    a = np.asarray(src.convert("RGBA")).astype(np.float64) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    l = (mx + mn) / 2
    d = mx - mn
    nz = d > 0
    s = np.where(~nz, 0, np.where(l < 0.5, d / np.maximum(mx + mn, 1e-9), d / np.maximum(2 - mx - mn, 1e-9)))
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    safe = np.where(nz, d, 1)
    h = np.where(mx == r, ((g - b) / safe) % 6, np.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4)) * 60
    h = np.where(nz, h, 0)

    base_l = colorsys.rgb_to_hls(*[c / 255 for c in BASE_TEAL])[1]
    teal = (h >= 150) & (h <= 200) & (s > 0.10) & nz
    w = np.clip(np.where(l <= base_l, l / base_l, 1 - (l - base_l) / (1 - base_l)), 0, 1)
    nh = np.where(teal, (h + hue_shift) % 360, h)
    nl = np.where(teal, np.clip(l + lift * w, 0, 1), l)

    c = (1 - np.abs(2 * nl - 1)) * s
    hp = nh / 60
    x = c * (1 - np.abs(hp % 2 - 1))
    m = nl - c / 2
    z = np.zeros_like(nh)
    conds = [hp < 1, hp < 2, hp < 3, hp < 4, hp < 5, hp >= 5]
    R = np.select(conds, [c, x, z, z, x, c])
    G = np.select(conds, [x, c, c, x, z, z])
    B = np.select(conds, [z, z, x, c, c, x])
    new = np.where(teal[..., None], np.stack([R + m, G + m, B + m], -1), rgb)
    out = np.clip(np.round(np.dstack([new, alpha]) * 255), 0, 255).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    return img.crop(img.getchannel("A").getbbox())


def main_teal_hex(img):
    a = np.asarray(img)
    px = a[..., :3][a[..., 3] == 255].reshape(-1, 3)
    vals, counts = np.unique(px, axis=0, return_counts=True)
    for v in vals[np.argsort(-counts)]:
        hh, ll, ss = colorsys.rgb_to_hls(*(v / 255))
        if 140 <= hh * 360 <= 210 and ss > 0.2:
            return "#%02X%02X%02X" % tuple(v)
    return "?"


def srgb_bytes():
    return ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("out")
    ap.add_argument("--hue", type=float, default=-6)
    ap.add_argument("--lift", type=float, default=0.07)
    ap.add_argument("--sheet", type=float, nargs="+", help="hue shifts for a labeled test sheet")
    args = ap.parse_args()
    src = Image.open(args.source)

    if not args.sheet:
        img = recolor(src, args.hue, args.lift)
        dpi = img.size[0] / STICKER_IN
        img.save(args.out, dpi=(dpi, dpi), icc_profile=srgb_bytes())
        print(args.out, img.size, "dpi %.1f" % dpi, "main teal", main_teal_hex(img))
        return

    stickers = [recolor(src, hs, args.lift) for hs in args.sheet]
    size = stickers[0].size[0]
    dpi = size / STICKER_IN
    gap, label_h, margin = int(0.3 * dpi), int(0.35 * dpi), int(0.25 * dpi)
    sheet = Image.new("RGBA", (margin * 2 + len(stickers) * size + (len(stickers) - 1) * gap, margin * 2 + size + label_h), "white")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", int(0.16 * dpi))
    except OSError:
        font = ImageFont.load_default()
    for i, (st, hs) in enumerate(zip(stickers, args.sheet)):
        x = margin + i * (size + gap)
        sheet.alpha_composite(st, (x, margin))
        label = "%d  %s" % (i + 1, main_teal_hex(st))
        draw.text((x + size // 2, margin + size + int(0.08 * dpi)), label, fill="black", font=font, anchor="ma")
        print("option", i + 1, "hue shift", hs, main_teal_hex(st))
    sheet.convert("RGB").save(args.out, dpi=(dpi, dpi), icc_profile=srgb_bytes())
    print(args.out, sheet.size, "%.2f x %.2f in" % (sheet.size[0] / dpi, sheet.size[1] / dpi))


if __name__ == "__main__":
    main()
