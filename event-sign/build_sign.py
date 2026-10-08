"""Direct Embroidery event sign: badge-shaped table sign with QR code + stand.

Print frame: z = 0 is the bed (back of the sign), front faces up. Colour by height:
  black base 0.0-3.0 mm | white 3.0-3.6 mm | red (accent) 3.6-4.2 mm
Every feature is a 2D mask at RES px/mm, traced to polygons and extruded with manifold3d.
Run: python3 -I build_sign.py   (needs numpy, opencv, pillow, segno, manifold3d, trimesh)
"""
import math, os
import numpy as np, cv2, segno, trimesh
from PIL import Image, ImageDraw, ImageFont
from manifold3d import CrossSection, FillRule, Manifold

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out'); os.makedirs(OUT, exist_ok=True)
REV = 'r2'
RES = 20                      # px per mm for all masks
SW, SH = 242.0, 245.0         # sign outline (flat bottom sits in the stand slot)
Z_BASE, Z_WHITE, Z_RED = 3.0, 3.6, 4.2
URL = 'https://sarasotashirts.com'
SANS = '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf'
W, H = int(SW * RES), int(SH * RES)

def disk(mm): r = max(1, int(round(mm * RES))); return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2*r+1, 2*r+1))
def ypx(y_mm): return int(round((SH - y_mm) * RES))      # mm above sign bottom -> image row
def xpx(x_mm): return int(round(x_mm * RES))
def blank(): return np.zeros((H, W), np.uint8)

# ---------------- badge outline ----------------
def badge_pts():
    pts, c = [], SW / 2
    for i in range(201):
        x = i / 200 * SW; t = abs(x - c) / c
        pts.append((x, 218 + 24 * ((1 + math.cos(math.pi * t)) / 2) ** 1.4))
    for i in range(1, 200):
        y = 218 - i / 200 * 218; pts.append((SW - 11 * math.sin(math.pi * y / 218) ** 0.8, y))
    pts += [(SW, 0.0), (0.0, 0.0)]
    for i in range(1, 200):
        y = i / 200 * 218; pts.append((11 * math.sin(math.pi * y / 218) ** 0.8, y))
    return pts
badge = blank()
cv2.fillPoly(badge, [np.array([(xpx(x), ypx(y)) for x, y in badge_pts()], np.int32)], 1)
border = cv2.erode(badge, disk(6.0)) - cv2.erode(badge, disk(7.6))
border[ypx(19.0):, :] = 0                                   # stop above the stand slot

# ---------------- logo (red_d.png) ----------------
im = np.asarray(Image.open(os.path.join(HERE, 'logo_red_d.png')).convert('RGBA')).astype(int)
rgb, a = im[..., :3], im[..., 3]; R, G, B = rgb[..., 0], rgb[..., 1], rgb[..., 2]
op = a > 128
m_red = (op & (R > 120) & (G < 110) & (B < 110) & (R - G > 50)).astype(np.uint8)
m_blk = (op & (rgb.max(-1) < 80)).astype(np.uint8)
m_wht = (op & (rgb.min(-1) > 200)).astype(np.uint8)
LH, LW = m_red.shape
SHIFT = 40                                   # logo px: drop the band 3 mm to clear EMBROIDERY
def split(mask, test):
    n, lab, st, _ = cv2.connectedComponentsWithStats(mask, 8)
    out = np.zeros_like(mask)
    for i in range(1, n):
        if test(*st[i]): out[lab == i] = 1
    return out
emb = split(m_red, lambda x, y, w, h, ar: y < 300)               # EMBROIDERY letters
tee_red = split(m_red, lambda x, y, w, h, ar: y >= 300)          # tee outline (red)
direct = split(m_blk, lambda x, y, w, h, ar: y < 200)            # DIRECT (black -> white on sign)
amp = split(m_blk, lambda x, y, w, h, ar: x > 2200 and y < 450)  # & (black -> white)
band_white = split(m_wht, lambda x, y, w, h, ar: y > 400)       # SCREEN PRINTING, CUSTOM TEES, tee outer lines
tee_body = split(m_blk, lambda x, y, w, h, ar: 900 < x < 1050 and w < 400 and h > 300)
# pill (stadium) from the band's bounding box, rimmed red + white because it is black-on-black
pill = np.zeros_like(m_red)
py0, py1 = 490, 796; rr = (py1 - py0) // 2
cv2.rectangle(pill, (1 + rr, py0), (LW - 1 - rr, py1), 1, -1)
cv2.circle(pill, (1 + rr, py0 + rr), rr, 1, -1); cv2.circle(pill, (LW - 1 - rr, py0 + rr), rr, 1, -1)
def shift_down(m): o = np.zeros((LH + SHIFT, LW), np.uint8); o[SHIFT:] = m; return o
def keep(m): o = np.zeros((LH + SHIFT, LW), np.uint8); o[:LH] = m; return o
L = {'emb': keep(emb), 'direct': keep(direct), 'amp': keep(amp), 'tee_red': shift_down(tee_red),
     'band_white': shift_down(band_white), 'tee_body': shift_down(tee_body), 'pill': shift_down(pill)}
LOGO_W = 190.0
s = LOGO_W * RES / LW                       # sign px per logo px
lx0 = xpx((SW - LOGO_W) / 2); ly0 = ypx(221.0)
def place(m):
    big = cv2.resize(m.astype(np.float32), (int(round(LW * s)), int(round((LH + SHIFT) * s))), interpolation=cv2.INTER_LINEAR)
    out = blank(); h, w = big.shape
    out[ly0:ly0 + h, lx0:lx0 + w] = (big > 0.5)
    return out
P = {k: place(v) for k, v in L.items()}
LOGO_H_MM = (LH + SHIFT) * s / RES
tee_all = P['tee_red'] | P['tee_body'] | cv2.dilate(P['tee_red'], disk(0.3))
tee_keepout = cv2.dilate(P['tee_red'] | P['tee_body'], disk(1.2))
pill_red = (P['pill'] - cv2.erode(P['pill'], disk(1.2))) & (1 - tee_keepout)
pill_white = (cv2.dilate(P['pill'], disk(0.9)) - P['pill']) & (1 - tee_keepout)
# CUSTOM TEES / thin white strokes: thicken anything thinner than 0.85 mm
thin_src = P['band_white']
dist = cv2.distanceTransform(thin_src, cv2.DIST_L2, 5)
n, lab, st, _ = cv2.connectedComponentsWithStats(thin_src, 8)
band_white = thin_src.copy()
for i in range(1, n):
    comp = (lab == i).astype(np.uint8)
    width_mm = 2 * dist[lab == i].max() / RES
    if width_mm < 0.85:
        grow = (0.85 - width_mm) / 2
        band_white |= cv2.dilate(comp, disk(grow)) & cv2.dilate(P['tee_body'] | comp, disk(0.01))
emb_white = cv2.dilate(P['emb'], disk(0.9))

# ---------------- QR ----------------
qr = segno.make(URL, error='q', micro=False)
mat = np.array([[1 if v else 0 for v in row] for row in qr.matrix], np.uint8); N = len(mat); QUIET = 3
QS = 106.0; MOD = QS / (N + 2 * QUIET)
qx0, qtop = 117.0, 143.0                  # panel left x, top y (mm)
qr_panel = blank()
cv2.rectangle(qr_panel, (xpx(qx0), ypx(qtop)), (xpx(qx0 + QS) - 1, ypx(qtop - QS) - 1), 1, -1)
qr_panel = cv2.morphologyEx(qr_panel, cv2.MORPH_OPEN, disk(3.0))       # rounded corners
qr_mod = blank()
for r in range(N):
    for c in range(N):
        if mat[r, c]:
            x0 = qx0 + (c + QUIET) * MOD; y0 = qtop - (r + QUIET) * MOD
            cv2.rectangle(qr_mod, (xpx(x0), ypx(y0)), (xpx(x0 + MOD) - 1, ypx(y0 - MOD) - 1), 1, -1)
qr_white = qr_panel & (1 - qr_mod)

# ---------------- text + arrow ----------------
def text_mask(txt, cx, cy, size_mm):
    img = Image.new('L', (W, H), 0); d = ImageDraw.Draw(img)
    d.text((xpx(cx), ypx(cy)), txt, font=ImageFont.truetype(SANS, int(size_mm * RES)), fill=255, anchor='mm')
    return (np.asarray(img) > 127).astype(np.uint8)
TX = 61.0
scan = text_mask('SCAN', TX, qtop - 20, 17)
toshop = text_mask('TO SHOP', TX, qtop - 42, 17)
url = text_mask('sarasotashirts.com', TX, qtop - 82, 8.2)
arrow = blank(); ay = ypx(qtop - 62)
cv2.line(arrow, (xpx(TX - 28), ay), (xpx(TX + 28), ay), 1, int(2.4 * RES))
cv2.fillPoly(arrow, [np.array([(xpx(TX + 36), ay), (xpx(TX + 26), ay - int(5.5 * RES)), (xpx(TX + 26), ay + int(5.5 * RES))], np.int32)], 1)

# ---------------- colour layers ----------------
red = P['emb'] | P['tee_red'] | pill_red | scan | arrow
white = (red | emb_white | cv2.dilate(scan | arrow, disk(0.7)) | P['direct'] | P['amp'] | band_white
         | pill_white | border | qr_white | toshop | url)
white &= badge
red &= cv2.erode(white, disk(0.05))           # red sits strictly inside white (no shared edges)
assert not (red & qr_panel).any(), 'red overlaps QR panel'
layers = {'base': badge, 'white': white, 'red': red}

def no_pinch(mask):
    # fill diagonal-only pixel contacts so traced outlines never touch at a single point
    m = mask.copy()
    for _ in range(10):
        a, b, c, d = m[:-1, :-1], m[:-1, 1:], m[1:, :-1], m[1:, 1:]
        p1 = (a & d) & (1 - b) & (1 - c); p2 = (b & c) & (1 - a) & (1 - d)
        if not (p1.any() or p2.any()): break
        m[:-1, 1:] |= p1; m[:-1, :-1] |= p2
    return m

def to_cross_section(mask):
    mask = no_pinch(mask)
    cs, _ = cv2.findContours(mask, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    rings = []
    for c in cs:
        c = cv2.approxPolyDP(c, 0.6, True).reshape(-1, 2)
        if len(c) < 3 or cv2.contourArea(c) < 4: continue
        rings.append([((x + 0.5) / RES, SH - (y + 0.5) / RES) for x, y in c])
    return CrossSection(rings, FillRule.EvenOdd)

def build_sign():
    parts = [to_cross_section(layers['base']).extrude(Z_BASE),
             to_cross_section(layers['white']).extrude(Z_WHITE - Z_BASE).translate((0, 0, Z_BASE)),
             to_cross_section(layers['red']).extrude(Z_RED - Z_WHITE).translate((0, 0, Z_WHITE))]
    return Manifold.batch_boolean(parts, __import__('manifold3d').OpType.Add)

# ---------------- stand ----------------
SLOT_W = 3.45; SLOT_FLOOR = 10.0; TOP_Z = 26.0; LEAN = math.radians(10)
END_WALL = 4.0; SLOT_LEN = SW + 1.2; STAND_L = SLOT_LEN + 2 * END_WALL
def build_stand():
    prof = CrossSection([[(0, 0), (75, 0), (75, 16), (36, 26), (20, 26), (0, 20)]])
    body = prof.extrude(STAND_L)                     # profile in (x=depth, y=z-height), extruded along z
    t = math.tan(LEAN); xs = 24.0; top = TOP_Z + 2
    slot = CrossSection([[(xs, SLOT_FLOOR), (xs + SLOT_W, SLOT_FLOOR),
                          (xs + SLOT_W + (top - SLOT_FLOOR) * t, top), (xs + (top - SLOT_FLOOR) * t, top)]])
    cut = slot.extrude(SLOT_LEN).translate((0, 0, END_WALL))
    m = body - cut
    # rotate so the extrusion axis becomes Y and the profile's y becomes Z (bed = z 0)
    return m.transform([[1, 0, 0, 0], [0, 0, 1, 0], [0, 1, 0, 0]])

def save(man, name):
    mesh = man.to_mesh()
    tm = trimesh.Trimesh(vertices=mesh.vert_properties[:, :3], faces=mesh.tri_verts, process=False)
    if tm.volume < 0: tm.invert()
    path = os.path.join(OUT, name); tm.export(path); return path, tm

if __name__ == '__main__':
    sign = build_sign(); stand = build_stand()
    p1, t1 = save(sign, f'event_sign_{REV}.stl'); p2, t2 = save(stand, f'event_sign_stand_{REV}.stl')
    np.savez_compressed(os.path.join(OUT, f'masks_{REV}.npz'), **layers, qr_panel=qr_panel)
    print('logo height mm %.1f, QR version %d, %d modules, module %.2f mm' % (LOGO_H_MM, qr.version, N, MOD))
    for p, t in ((p1, t1), (p2, t2)):
        print(os.path.basename(p), 'extents %.2f x %.2f x %.2f' % tuple(t.extents), 'watertight', t.is_watertight,
              'bodies', len(t.split(only_watertight=False)), 'shared-position verts', len(t.vertices) - len(np.unique(np.round(t.vertices, 6), axis=0)), 'faces', len(t.faces), 'vol cm3 %.1f' % (t.volume / 1000))
