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


_M = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
_WHITE = np.array([0.95047, 1.0, 1.08883])


def _rgb_to_lch(rgb):
    c = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    xyz = (c @ _M.T) / _WHITE
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    L = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return L, np.hypot(a, b), np.degrees(np.arctan2(b, a)) % 360


def _lch_to_rgb(L, C, H):
    a = C * np.cos(np.radians(H))
    b = C * np.sin(np.radians(H))
    fy = (L + 16) / 116
    f = np.stack([fy + a / 500, fy, fy - b / 200], -1)
    xyz = np.where(f ** 3 > 216 / 24389, f ** 3, (116 * f - 16) / (24389 / 27)) * _WHITE
    lin = np.clip(xyz @ np.linalg.inv(_M).T, 0, 1)
    return np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * lin ** (1 / 2.4) - 0.055)


def recolor_lch(src, target_l, target_c, target_h):
    """Like recolor(), but works in CIE LCh so the main teal lands on an exact
    perceived lightness / colorfulness / hue. Other teal tones keep their offsets."""
    a = np.asarray(src.convert("RGBA")).astype(np.float64) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    nz = d > 0
    l_hls = (mx + mn) / 2
    s = np.where(~nz, 0, np.where(l_hls < 0.5, d / np.maximum(mx + mn, 1e-9), d / np.maximum(2 - mx - mn, 1e-9)))
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    safe = np.where(nz, d, 1)
    h_hls = np.where(mx == r, ((g - b) / safe) % 6, np.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4)) * 60
    teal = (h_hls >= 150) & (h_hls <= 200) & (s > 0.10) & nz

    L, C, H = _rgb_to_lch(rgb)
    L0, C0, H0 = [v.item() for v in _rgb_to_lch(np.array(BASE_TEAL, float) / 255)]
    w = np.clip(np.where(L <= L0, L / L0, 1 - (L - L0) / (100 - L0)), 0, 1)
    nL = L + (target_l - L0) * w
    nC = C * (target_c / C0)
    nH = (H + (target_h - H0)) % 360
    new = np.where(teal[..., None], _lch_to_rgb(nL, nC, nH), rgb)
    out = np.clip(np.round(np.dstack([new, alpha]) * 255), 0, 255).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    return img.crop(img.getchannel("A").getbbox())


def main_teal_hex(img):
    a = np.asarray(img)
    px = a[..., :3][a[..., 3] == 255].reshape(-1, 3)
    vals, counts = np.unique(px, axis=0, return_counts=True)
    for v in vals[np.argsort(-counts)]:
        hh, ll, ss = colorsys.rgb_to_hls(*(v / 255))
        if 140 <= hh * 360 <= 230 and ss > 0.2:
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
    ap.add_argument("--lch", type=float, nargs=3, metavar=("L", "C", "H"), help="exact CIE LCh target for the main teal")
    ap.add_argument("--lch-sheet", type=float, nargs="+", metavar="H",
                    help="labeled sheet: B2 as option 1, then these LCh hues at --lch-l/--lch-c")
    ap.add_argument("--lch-l", type=float, default=64.9)
    ap.add_argument("--lch-c", type=float, default=32.7)
    args = ap.parse_args()
    src = Image.open(args.source)

    if args.lch:
        img = recolor_lch(src, *args.lch)
        dpi = img.size[0] / STICKER_IN
        img.save(args.out, dpi=(dpi, dpi), icc_profile=srgb_bytes())
        print(args.out, img.size, "dpi %.1f" % dpi, "main teal", main_teal_hex(img))
        return

    if args.lch_sheet:
        stickers = [recolor(src, -6, 0.07)] + [recolor_lch(src, args.lch_l, args.lch_c, hh) for hh in args.lch_sheet]
        args.sheet = [-6] + args.lch_sheet
        return build_sheet(stickers, args)

    if not args.sheet:
        img = recolor(src, args.hue, args.lift)
        dpi = img.size[0] / STICKER_IN
        img.save(args.out, dpi=(dpi, dpi), icc_profile=srgb_bytes())
        print(args.out, img.size, "dpi %.1f" % dpi, "main teal", main_teal_hex(img))
        return

    build_sheet([recolor(src, hs, args.lift) for hs in args.sheet], args)


def build_sheet(stickers, args):
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
        print("option", i + 1, "setting", hs, main_teal_hex(st))
    sheet.convert("RGB").save(args.out, dpi=(dpi, dpi), icc_profile=srgb_bytes())
    print(args.out, sheet.size, "%.2f x %.2f in" % (sheet.size[0] / dpi, sheet.size[1] / dpi))


if __name__ == "__main__":
    main()
