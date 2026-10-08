"""Re-load the exported STLs, slice at each colour height, render, decode the QR, check feature widths."""
import sys, numpy as np, cv2, trimesh
from PIL import Image
REV = sys.argv[1] if len(sys.argv) > 1 else 'r1'
RES = 8
t = trimesh.load(f'out/event_sign_{REV}.stl')
print('loaded', t.extents.round(2), 'watertight', t.is_watertight, 'bodies', len(t.split(only_watertight=False)))
x0, y0 = t.bounds[0][:2]; Wd, Hd = (t.extents[:2] * RES).astype(int) + 4
def section_mask(z):
    sec = t.section(plane_origin=[0, 0, z], plane_normal=[0, 0, 1])
    m = np.zeros((Hd, Wd), np.uint8)
    p2, _ = sec.to_2D(np.eye(4))
    for loop in p2.discrete:                      # even-odd fill: holes cancel out
        pts = ((np.asarray(loop) - [x0, y0]) * RES).astype(np.int32); pts[:, 1] = Hd - 1 - pts[:, 1]
        one = np.zeros_like(m); cv2.fillPoly(one, [pts], 1); m ^= one
    return m
base, white, red = section_mask(1.5), section_mask(3.3), section_mask(3.9)
img = np.full((Hd, Wd, 3), 214, np.uint8)
img[base > 0] = (22, 22, 22); img[white > 0] = (242, 242, 242); img[red > 0] = (196, 32, 44)
Image.fromarray(img).save(f'out/preview_top_{REV}.png')
det = cv2.QRCodeDetector()
bgr = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
print('QR decode full view:', repr(det.detectAndDecode(bgr)[0]))
small = cv2.resize(bgr, None, fx=0.35, fy=0.35, interpolation=cv2.INTER_AREA)
print('QR decode at 35% size:', repr(det.detectAndDecode(small)[0]))
# feature width checks on the as-exported slices (mm)
def lost(mask, width_mm, positive=True):
    r = max(1, int(round(width_mm * RES / 2)))
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))
    if positive: gone = mask & (1 - cv2.morphologyEx(mask, cv2.MORPH_OPEN, k))
    else: gone = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, k) & (1 - mask)
    return gone
for name, m in (('white top', white & (1 - red)), ('red', red)):
    g = lost(m, 0.8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(g, 8)
    blobs = sorted([st[i][4] for i in range(1, n)], reverse=True)
    print(f'{name}: area thinner than 0.8 mm = {g.sum() / RES**2:.1f} mm2 in {n - 1} spots, largest {blobs[:3]} px')
g = lost(white, 0.4, positive=False)
print(f'black gaps in white narrower than 0.4 mm: {g.sum() / RES**2:.1f} mm2')
