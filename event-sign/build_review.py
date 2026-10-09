"""Direct Embroidery in-store review sign: T-shirt silhouette, Google review QR, table stand.

Print frame: z = 0 is the bed (back), front up. Colour by height (same scheme as event_sign):
  base 0.0-3.0 mm | white 3.0-3.6 mm | accent 3.6-4.2 mm
Usage: python3 -I build_review.py [REVIEW_URL]   (no URL = preview only, QR drawn as a placeholder)
"""
import math, os, sys
import numpy as np, cv2, segno
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__)); OUT = os.path.join(HERE, 'out'); os.makedirs(OUT, exist_ok=True)
REV = 'r1'
URL = sys.argv[1] if len(sys.argv) > 1 else None
RES = 20 if URL else 10
SW, SH = 242.0, 240.0
Z_BASE, Z_WHITE, Z_ACC = 3.0, 3.6, 4.2
SANS = '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf'
SERIF = '/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'
W, H = int(SW * RES), int(SH * RES)
C = SW / 2
def disk(mm): r = max(1, int(round(mm * RES))); return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2*r+1, 2*r+1))
def X(x): return int(round(x * RES))
def Y(y): return int(round((SH - y) * RES))
def blank(): return np.zeros((H, W), np.uint8)
def fill(pts): m = blank(); cv2.fillPoly(m, [np.array([(X(x), Y(y)) for x, y in pts], np.int32)], 1); return m
def polyline(pts, width_mm, closed=False):
    m = blank(); cv2.polylines(m, [np.array([(X(x), Y(y)) for x, y in pts], np.int32)], closed, 1, max(1, int(round(width_mm * RES)))); return m
def dashed(pts, width_mm, dash=3.2, gap=2.2):
    # dashes along a polyline (mm)
    m = blank(); segs = []; acc = 0.0; on = True; cur = [pts[0]]
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        L = math.hypot(x1 - x0, y1 - y0); t = 0.0
        while t < L:
            step = min((dash if on else gap) - acc, L - t); t += step; acc += step
            p = (x0 + (x1 - x0) * t / L, y0 + (y1 - y0) * t / L)
            if on: cur.append(p)
            if acc >= (dash if on else gap) - 1e-9:
                if on: segs.append(cur)
                on = not on; acc = 0.0; cur = [p]
    for s in segs:
        cv2.polylines(m, [np.array([(X(x), Y(y)) for x, y in s], np.int32)], False, 1, max(1, int(round(width_mm * RES))))
    return m
def text(txt, cx, cy, mm, font=SANS):
    img = Image.new('L', (W, H), 0); d = ImageDraw.Draw(img)
    d.text((X(cx), Y(cy)), txt, font=ImageFont.truetype(font, int(mm * RES)), fill=255, anchor='mm')
    return (np.asarray(img) > 127).astype(np.uint8)
def star(cx, cy, r):
    return fill([(cx + (r if k % 2 == 0 else r * 0.44) * math.cos(math.pi / 2 + k * math.pi / 5),
                  cy + (r if k % 2 == 0 else r * 0.44) * math.sin(math.pi / 2 + k * math.pi / 5)) for k in range(10)])

# ---------------- shirt silhouette ----------------
def bez(p0, p1, p2, n=24):
    return [((1-t)**2*p0[0] + 2*(1-t)*t*p1[0] + t*t*p2[0], (1-t)**2*p0[1] + 2*(1-t)*t*p1[1] + t*t*p2[1]) for t in [i/n for i in range(n+1)]]
right = (bez((C+27, 234), (C+52, 233), (C+80, 223))          # shoulder, gently curved
         + bez((C+80, 223), (C+90, 220), (C+98, 212))[1:]     # round into the sleeve
         + [(C+121, 186), (C+104, 165)]                       # sleeve top edge, cuff
         + bez((C+104, 165), (C+86, 174), (C+77, 178))[1:]    # sleeve underside to armpit
         + bez((C+77, 178), (C+73, 120), (C+77, 0))[1:])       # body side, slight waist
left = [(2*C - x, y) for x, y in reversed(right)]
neck = [(C + 27 * math.cos(a), 234 - 15 * math.sin(a)) for a in np.linspace(math.pi, 0, 40)]   # scoop, left to right
outline = right + left + neck[1:-1]
shirt = fill(outline)
shirt = cv2.morphologyEx(cv2.morphologyEx(shirt, cv2.MORPH_CLOSE, disk(2.5)), cv2.MORPH_OPEN, disk(2.5))
# collar rib (accent) following the neck
collar_out = [(C + 27 * math.cos(a), 234 - 15 * math.sin(a)) for a in np.linspace(math.pi, 0, 60)]
collar = polyline([(C + 30.5 * math.cos(a), 234 - 18.5 * math.sin(a)) for a in np.linspace(math.pi * 0.98, math.pi * 0.02, 60)], 4.2) & shirt
collar_stitch = dashed([(C + 36 * math.cos(a), 234 - 24 * math.sin(a)) for a in np.linspace(math.pi * 0.93, math.pi * 0.07, 80)], 0.9, 2.6, 1.8)
# sleeve hem stitching (parallel to the cuff, 5 mm in)
def cuff_stitch(s):
    a, b = (C + s * 121, 186), (C + s * 104, 165)
    dx, dy = b[0] - a[0], b[1] - a[1]; L = math.hypot(dx, dy); nx, ny = -dy / L, dx / L
    if s > 0: nx, ny = -nx, -ny
    off = 5.0; pa = (a[0] + nx * off + dx / L * 2.5, a[1] + ny * off + dy / L * 2.5); pb = (b[0] + nx * off - dx / L * 3.5, b[1] + ny * off - dy / L * 3.5)
    return dashed([pa, pb], 1.0, 2.8, 1.8)
stitches = (cuff_stitch(1) | cuff_stitch(-1) | dashed([(C - 70, 24), (C + 70, 24)], 1.0, 2.8, 1.8)) & cv2.erode(shirt, disk(1.5))

# ---------------- stars on an arc ----------------
stars = blank()
for i, (dx, r) in enumerate([(-40, 6.5), (-20, 7.5), (0, 9.0), (20, 7.5), (40, 6.5)]):
    stars |= star(C + dx, 196 + 6 * math.cos(dx / 40 * math.pi / 2), r)
headline = text('LOVE YOUR SHIRTS?', C, 179.5, 11.0, SERIF)

# ---------------- ribbon banner ----------------
by0, by1 = 155.5, 170.5
band = fill([(C - 58, by0), (C + 58, by0), (C + 58, by1), (C - 58, by1)])
tails = blank(); folds = blank()
for s in (1, -1):
    x_in, x_out = C + s * 52, C + s * 70
    tails |= fill([(x_in, by0 - 4.5), (x_out, by0 - 4.5), (x_out - s * 5, (by0 + by1) / 2 - 4.5 + 0.0), (x_out, by1 - 4.5), (x_in, by1 - 4.5)])
    folds |= fill([(C + s * 58, by0), (C + s * 52, by0 - 4.5), (C + s * 58, by0 - 4.5)])
ribbon_letters = text('LEAVE US A REVIEW', C, (by0 + by1) / 2, 8.6)
tails &= 1 - cv2.dilate(band, disk(0.8))             # visible gap between band and tails
ribbon = band | tails

# ---------------- QR panel + scan brackets ----------------
QS = 100.0; qx0, qtop = C - QS / 2, 144.5
qr_panel = blank(); cv2.rectangle(qr_panel, (X(qx0), Y(qtop)), (X(qx0 + QS) - 1, Y(qtop - QS) - 1), 1, -1)
qr_panel = cv2.morphologyEx(qr_panel, cv2.MORPH_OPEN, disk(3.0))
qr_mod = blank(); QUIET = 3; mod_mm = None; version = None
if URL:
    q = segno.make(URL, error='m', micro=False); version = q.version
    mat = [[1 if v else 0 for v in row] for row in q.matrix]; N = len(mat); mod_mm = QS / (N + 2 * QUIET)
    for r in range(N):
        for c2 in range(N):
            if mat[r][c2]:
                x0 = qx0 + (c2 + QUIET) * mod_mm; y0 = qtop - (r + QUIET) * mod_mm
                cv2.rectangle(qr_mod, (X(x0), Y(y0)), (X(x0 + mod_mm) - 1, Y(y0 - mod_mm) - 1), 1, -1)
brackets = blank(); g, arm, th = 3.5, 15.0, 2.2
for sx, sy, cx0, cy0 in ((1, 1, qx0 - g, qtop + g), (-1, 1, qx0 + QS + g, qtop + g), (1, -1, qx0 - g, qtop - QS - g), (-1, -1, qx0 + QS + g, qtop - QS - g)):
    brackets |= polyline([(cx0 + sx * arm, cy0), (cx0, cy0), (cx0, cy0 - sy * arm)], th)
brand = text('DIRECT EMBROIDERY', C, 32.5, 7.2, SERIF)

# ---------------- colour layers ----------------
accent = (collar | stars | (ribbon & (1 - ribbon_letters)) | brackets) & shirt
white = (accent | cv2.dilate(collar | stars | ribbon | brackets, disk(0.8)) | ribbon_letters & band | headline
         | stitches | (qr_panel & (1 - qr_mod)) | brand) & shirt
accent &= cv2.erode(white, disk(0.05))
layers = {'base': shirt, 'white': white, 'accent': accent}

def preview(path):
    img = np.full((H, W, 3), 214, np.uint8)
    img[shirt > 0] = (22, 22, 22); img[white > 0] = (242, 242, 242); img[accent > 0] = (212, 170, 40)
    pil = Image.fromarray(img)
    if not URL:
        d = ImageDraw.Draw(pil); f = ImageFont.truetype(SANS, int(6.5 * RES))
        d.text((X(C), Y(qtop - QS / 2 - 5)), 'GOOGLE REVIEW', font=f, fill=(150, 150, 150), anchor='mm')
        d.text((X(C), Y(qtop - QS / 2 + 5)), 'QR CODE', font=f, fill=(150, 150, 150), anchor='mm')
    pil.save(path)

def no_pinch(mask):
    m = mask.copy()
    for _ in range(10):
        a, b, c, d = m[:-1, :-1], m[:-1, 1:], m[1:, :-1], m[1:, 1:]
        p1 = (a & d) & (1 - b) & (1 - c); p2 = (b & c) & (1 - a) & (1 - d)
        if not (p1.any() or p2.any()): break
        m[:-1, 1:] |= p1; m[:-1, :-1] |= p2
    return m

def to_cross_section(mask):
    from manifold3d import CrossSection, FillRule
    cs, _ = cv2.findContours(no_pinch(mask), cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    rings = []
    for c in cs:
        c = cv2.approxPolyDP(c, 0.6, True).reshape(-1, 2)
        if len(c) < 3 or cv2.contourArea(c) < 4: continue
        rings.append([((x + 0.5) / RES, SH - (y + 0.5) / RES) for x, y in c])
    return CrossSection(rings, FillRule.EvenOdd)

def build_sign():
    from manifold3d import Manifold, OpType
    parts = [to_cross_section(layers['base']).extrude(Z_BASE),
             to_cross_section(layers['white']).extrude(Z_WHITE - Z_BASE).translate((0, 0, Z_BASE)),
             to_cross_section(layers['accent']).extrude(Z_ACC - Z_WHITE).translate((0, 0, Z_WHITE))]
    return Manifold.batch_boolean(parts, OpType.Add)

def hem_width():
    cols = np.where(shirt[Y(0.5)] > 0)[0]; return (cols.max() - cols.min() + 1) / RES

SLOT_W = 3.45; SLOT_FLOOR = 10.0; TOP_Z = 26.0; LEAN = math.radians(10); END_WALL = 4.0
def build_stand(hem):
    from manifold3d import CrossSection
    slot_len = hem + 1.2; L = slot_len + 2 * END_WALL
    body = CrossSection([[(0, 0), (75, 0), (75, 16), (36, 26), (20, 26), (0, 20)]]).extrude(L)
    t = math.tan(LEAN); xs = 24.0; top = TOP_Z + 2
    slot = CrossSection([[(xs, SLOT_FLOOR), (xs + SLOT_W, SLOT_FLOOR), (xs + SLOT_W + (top - SLOT_FLOOR) * t, top), (xs + (top - SLOT_FLOOR) * t, top)]])
    m = body - slot.extrude(slot_len).translate((0, 0, END_WALL))
    return m.transform([[1, 0, 0, 0], [0, 0, 1, 0], [0, 1, 0, 0]])

def save(man, name):
    import trimesh
    mesh = man.to_mesh()
    tm = trimesh.Trimesh(vertices=mesh.vert_properties[:, :3], faces=mesh.tri_verts, process=False)
    if tm.volume < 0: tm.invert()
    path = os.path.join(OUT, name); tm.export(path)
    print(name, 'extents %.2f x %.2f x %.2f' % tuple(tm.extents), 'watertight', tm.is_watertight,
          'bodies', len(tm.split(only_watertight=False)), 'shared-position verts', len(tm.vertices) - len(np.unique(np.round(tm.vertices, 6), axis=0)))

if __name__ == '__main__':
    preview(os.path.join(OUT, f'review_preview_{REV}{"" if URL else "_placeholder"}.png'))
    print('preview written; QR', 'version %s module %.2f mm' % (version, mod_mm) if URL else 'placeholder')
    if URL:
        save(build_sign(), f'review_sign_{REV}.stl')
        hw = hem_width(); print('hem width %.2f mm' % hw)
        save(build_stand(hw), f'review_sign_stand_{REV}.stl')
