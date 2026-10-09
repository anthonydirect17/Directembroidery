"""Mockup for the in-store review sign: same badge + logo as event_sign r2, new lower half."""
import math, numpy as np, cv2, importlib.util
from PIL import Image, ImageDraw, ImageFont
spec = importlib.util.spec_from_file_location('b', 'build_sign.py'); b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
RES, SW, SH, disk, xpx, ypx, blank = b.RES, b.SW, b.SH, b.disk, b.xpx, b.ypx, b.blank
SANS = b.SANS
def star(cx, cy, r):
    pts = []
    for k in range(10):
        ang = math.pi / 2 + k * math.pi / 5; rr = r if k % 2 == 0 else r * 0.45
        pts.append((xpx(cx + rr * math.cos(ang)), ypx(cy + rr * math.sin(ang))))
    m = blank(); cv2.fillPoly(m, [np.array(pts, np.int32)], 1); return m
TX, top = 61.0, 143.0
stars = blank()
for i in range(5): stars |= star(TX - 40 + i * 20, top - 12, 8.5)
leave = b.text_mask('LEAVE US', TX, top - 37, 15)
review = b.text_mask('A REVIEW', TX, top - 56, 15)
arrow = blank(); ay = ypx(top - 74)
cv2.line(arrow, (xpx(TX - 28), ay), (xpx(TX + 28), ay), 1, int(2.4 * RES))
cv2.fillPoly(arrow, [np.array([(xpx(TX + 36), ay), (xpx(TX + 26), ay - int(5.5 * RES)), (xpx(TX + 26), ay + int(5.5 * RES))], np.int32)], 1)
thanks = b.text_mask('Thank you for your support!', TX, top - 92, 6.2)
qr_panel = b.qr_panel
P = b.P
red = P['emb'] | P['tee_red'] | b.pill_red | stars | review | arrow
white = (red | b.emb_white | cv2.dilate(stars | review | arrow, disk(0.7)) | P['direct'] | P['amp'] | b.band_white
         | b.pill_white | b.border | qr_panel | leave | thanks) & b.badge
img = np.full((b.H, b.W, 3), 214, np.uint8)
img[b.badge > 0] = (22, 22, 22); img[white > 0] = (242, 242, 242); img[red > 0] = (212, 170, 40)
pil = Image.fromarray(img); d = ImageDraw.Draw(pil)
f = ImageFont.truetype(SANS, int(7 * RES)); cx = xpx(b.qx0 + b.QS / 2); cy = ypx(top - b.QS / 2)
d.text((cx, cy - int(6 * RES)), 'YOUR GOOGLE', font=f, fill=(150, 150, 150), anchor='mm')
d.text((cx, cy + int(4 * RES)), 'REVIEW QR', font=f, fill=(150, 150, 150), anchor='mm')
d.text((cx, cy + int(14 * RES)), 'goes here', font=ImageFont.truetype(SANS, int(5 * RES)), fill=(150, 150, 150), anchor='mm')
pil = pil.resize((pil.width // 5, pil.height // 5), Image.LANCZOS)
canvas = Image.new('RGB', (pil.width + 60, pil.height + 110), (214, 216, 219)); canvas.paste(pil, (30, 30))
cd = ImageDraw.Draw(canvas); sm = ImageFont.truetype(SANS, 15)
cd.text((30, pil.height + 45), 'Review sign mockup: same badge, logo and stand as the event sign. Accent shown in gold (your silk), colors still your pick.', font=sm, fill=(30, 30, 30))
cd.text((30, pil.height + 68), 'QR is a placeholder until I have your Google review link.', font=sm, fill=(30, 30, 30))
canvas.save('review_mockup_v1.png'); print(canvas.size)
