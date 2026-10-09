"""Two creative review-sign concepts: A) T-shirt silhouette, B) scalloped award seal."""
import math, numpy as np, segno
from PIL import Image, ImageDraw, ImageFont
PX = 6
BLACK=(22,22,22); WHITE=(242,242,242); GOLD=(212,170,40); BG=(214,216,219); STAND=(58,58,62); PH=(150,150,150)
SANS='/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf'
SERIF='/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'
def F(path, mm): return ImageFont.truetype(path, int(mm*PX))
def star_pts(cx, cy, r):
    return [(cx + (r if k%2==0 else r*0.45)*math.cos(math.pi/2 + k*math.pi/5), cy + (r if k%2==0 else r*0.45)*math.sin(math.pi/2 + k*math.pi/5)) for k in range(10)]
def P(pts, ox, oy, H): return [((ox+x)*PX, (oy+H-y)*PX) for x,y in pts]   # mm (y up) -> canvas px
def qr_placeholder(d, x0, ytop, size, ox, oy, H):
    d.rounded_rectangle([ (ox+x0)*PX, (oy+H-ytop)*PX, (ox+x0+size)*PX, (oy+H-ytop+size)*PX ], 3*PX, fill=WHITE)
    cx=(ox+x0+size/2)*PX; cy=(oy+H-ytop+size/2)*PX
    d.text((cx,cy-5*PX),'GOOGLE REVIEW',font=F(SANS,6.5),fill=PH,anchor='mm'); d.text((cx,cy+5*PX),'QR CODE',font=F(SANS,6.5),fill=PH,anchor='mm')
def txt(d, s, cx, cy, mm, ox, oy, H, fill=WHITE, font=SANS, outline=None):
    f=F(font,mm); X=(ox+cx)*PX; Y=(oy+H-cy)*PX
    if outline: d.text((X,Y),s,font=f,fill=fill,anchor='mm',stroke_width=int(0.8*PX),stroke_fill=outline)
    else: d.text((X,Y),s,font=f,fill=fill,anchor='mm')

W, Hc = 560, 330
img = Image.new('RGB', (W*PX, Hc*PX), BG); d = ImageDraw.Draw(img)
lab = F(SANS, 8); sm = F(SANS, 5)

# ---------------- A: T-shirt ----------------
ox, oy, H = 20, 40, 242.0
c = 121.0
right = [(c+24,238),(c+60,232),(c+92,222),(c+121,193),(c+101,166),(c+75,180),(c+74,0)]
pts = right + [(2*c-x, y) for x, y in reversed(right)]
neck = [(c-24+48*i/40, 238 - 14*math.sin(math.pi*i/40)) for i in range(41)]
shirt = [(c-24,238)] + [p for p in reversed(neck)][1:-1][::-1]  # placeholder, rebuilt below
outline = pts[:1] + pts[1:]  # start at right neck point going clockwise
poly = [ (c+24,238) ] + right[1:] + [(2*c-x, y) for x, y in reversed(right[1:])] + [(c-24,238)] + [ (c-24+48*i/40, 238 - 14*math.sin(math.pi*i/40)) for i in range(1,40) ]
d.text((ox*PX, 12*PX), 'A. T-shirt (recommended)', font=lab, fill=(20,20,20))
d.text((ox*PX, 23*PX), 'On brand for a shirt shop. 242 x 238 mm, new narrow stand under the hem.', font=sm, fill=(40,40,40))
d.polygon(P(poly, ox, oy, H), fill=BLACK)
# collar rib + sleeve cuffs (white), hem line
collar = [ (c-24+48*i/40, 238 - 14*math.sin(math.pi*i/40)) for i in range(41) ]
d.line(P(collar, ox, oy, H), fill=GOLD, width=int(2.2*PX)); d.line(P([(x, y-3.2) for x,y in collar], ox, oy, H), fill=WHITE, width=int(1*PX))
for s in (1, -1):
    a=(c+s*121,193); b2=(c+s*101,166)
    d.line(P([(a[0]-s*5.5,a[1]-4.5),(b2[0]-s*5.5,b2[1]+4.5)], ox, oy, H), fill=WHITE, width=int(1.2*PX))
for i in range(5): d.polygon(P(star_pts(c-36+i*18, 205, 7.5), ox, oy, H), fill=GOLD)
txt(d, 'LOVE YOUR SHIRTS?', c, 186, 11.5, ox, oy, H, fill=WHITE)
txt(d, 'LEAVE US A REVIEW', c, 170, 10.5, ox, oy, H, fill=GOLD, outline=WHITE)
qr_placeholder(d, c-50, 158, 100, ox, oy, H)
txt(d, 'DIRECT EMBROIDERY', c, 47, 7, ox, oy, H, fill=WHITE, font=SERIF)
d.rounded_rectangle([(ox+c-82)*PX, (oy+H-16)*PX, (ox+c+82)*PX, (oy+H+8)*PX], 3*PX, fill=STAND)

# ---------------- B: award seal ----------------
ox2, oy2 = 300, 40
cx, cy, R = 121.0, 125.0, 117.0
seal = []
for i in range(720):
    t = 2*math.pi*i/720; r = R - 4 + 4*math.cos(24*t)
    x, y = cx + r*math.cos(t), cy + r*math.sin(t)
    seal.append((x, max(y, 8.0)))                        # flat bottom for the stand slot
d.text((ox2*PX, 12*PX), 'B. Award seal', font=lab, fill=(20,20,20))
d.text((ox2*PX, 23*PX), 'Scalloped badge, curved text. 242 mm round with a flat bottom for its stand.', font=sm, fill=(40,40,40))
d.polygon(P(seal, ox2, oy2, H), fill=BLACK)
ring = [(cx + 103*math.cos(2*math.pi*i/360), max(cy + 103*math.sin(2*math.pi*i/360), 20)) for i in range(361)]
d.line(P(ring, ox2, oy2, H), fill=WHITE, width=int(1.6*PX))
def arc_text(s, radius, start_deg, end_deg, mm, fill, top=True):
    f = F(SANS, mm); n = len(s)
    for k, ch in enumerate(s):
        a = math.radians(start_deg + (end_deg - start_deg) * (k + 0.5) / n)
        x, y = cx + radius*math.cos(a), cy + radius*math.sin(a)
        rot = math.degrees(a) - 90 if top else math.degrees(a) + 90
        tile = Image.new('RGBA', (int(mm*PX*1.6),)*2, (0,0,0,0)); td = ImageDraw.Draw(tile)
        td.text((tile.width/2, tile.height/2), ch, font=f, fill=fill, anchor='mm')
        tile = tile.rotate(rot, resample=Image.BICUBIC)
        X, Y = int((ox2 + x)*PX - tile.width/2), int((oy2 + H - y)*PX - tile.height/2)
        img.paste(tile, (X, Y), tile)
arc_text('LOVE YOUR SHIRTS?', 89, 155, 25, 12, WHITE, top=True)
arc_text('LEAVE US A REVIEW', 91, 205, 335, 11.5, GOLD, top=False)
for i in range(5): d.polygon(P(star_pts(cx-34+i*17, cy+60, 6.5), ox2, oy2, H), fill=GOLD)
qr_placeholder(d, cx-46, cy+48, 92, ox2, oy2, H)
d.rounded_rectangle([(ox2+cx-70)*PX, (oy2+H-16)*PX, (ox2+cx+70)*PX, (oy2+H+8)*PX], 3*PX, fill=STAND)

d.text((20*PX, 305*PX), 'Colors are placeholders (gold shown as the accent, like your silk). Same 2 color changes: base, white, accent.', font=sm, fill=(40,40,40))
d.text((20*PX, 314*PX), 'QR stays a placeholder until I have your Google review link.', font=sm, fill=(40,40,40))
img = img.resize((img.width//2, img.height//2), Image.LANCZOS); img.save('review_mockup_v2.png'); print(img.size)
