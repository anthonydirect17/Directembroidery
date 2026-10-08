import numpy as np, segno
from PIL import Image, ImageDraw, ImageFont
PX = 4  # pixels per mm
BLACK=(22,22,22); WHITE=(240,240,240); ACC=(178,38,46); BG=(205,210,214); GREY=(120,120,120)
SANS='/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf'
SERIF='/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'

def logo_img(width_mm):
    im=np.asarray(Image.open('logo_website.png').convert('RGBA')).astype(int)[0:1704]
    rgb, a = im[...,:3], im[...,3]
    g = (a>128)&(rgb[...,1]>rgb[...,0]+8)&(rgb.max(-1)<200)
    w = (a>128)&(rgb.min(-1)>200)
    out=np.zeros(im.shape[:2]+(4,),np.uint8)
    out[g]=ACC+(255,); out[w]=WHITE+(255,)
    img=Image.fromarray(out,'RGBA')
    wpx=int(width_mm*PX); return img.resize((wpx,int(img.height*wpx/img.width)),Image.LANCZOS)

def qr_img(panel_mm):
    q=segno.make('https://sarasotashirts.com', error='q', micro=False)
    m=q.matrix; n=len(m); quiet=4
    mod=panel_mm/(n+2*quiet)
    img=Image.new('RGB',(int(panel_mm*PX),)*2,WHITE); d=ImageDraw.Draw(img)
    for r,row in enumerate(m):
        for c,v in enumerate(row):
            if v:
                x0=(c+quiet)*mod*PX; y0=(r+quiet)*mod*PX
                d.rectangle([x0,y0,x0+mod*PX-1,y0+mod*PX-1],fill=BLACK)
    return img, q.version, n, mod

def plate(d, x, y, w, h, r=8):
    d.rounded_rectangle([x*PX,y*PX,(x+w)*PX,(y+h)*PX], r*PX, fill=BLACK)

def seam_h(d, x, y, w, tabs):
    # horizontal joint with dovetail tabs (drawn as thin gap)
    pts=[(x,y)]
    for cx in tabs:
        pts += [(cx-9,y),(cx-6,y+8),(cx+6,y+8),(cx+9,y)]
    pts.append((x+w,y))
    d.line([(px*PX,py*PX) for px,py in pts], fill=(70,70,70), width=3)

def seam_v(d, x, y, h, tabs):
    pts=[(x,y)]
    for cy in tabs:
        pts += [(x,cy-9),(x+8,cy-6),(x+8,cy+6),(x,cy+9)]
    pts.append((x,y+h))
    d.line([(px*PX,py*PX) for px,py in pts], fill=(70,70,70), width=3)

def hook(d, cx, top_y, bar_y):
    # slot in plate + hook shape over a bar (circle)
    d.rounded_rectangle([(cx-7)*PX,(top_y+5)*PX,(cx+7)*PX,(top_y+10)*PX], 2*PX, fill=BG)
    d.line([(cx*PX,(top_y+7)*PX),(cx*PX,(bar_y+14)*PX)], fill=GREY, width=4*PX)
    d.arc([(cx-14)*PX,(bar_y-14)*PX,(cx+14)*PX,(bar_y+14)*PX], 180, 360, fill=GREY, width=4*PX)
    d.line([((cx+14)*PX,bar_y*PX),((cx+14)*PX,(bar_y+10)*PX)], fill=GREY, width=4*PX)
    d.ellipse([(cx-12)*PX,(bar_y-12)*PX,(cx+12)*PX,(bar_y+12)*PX], outline=(90,90,90), width=2)

def text(d, cx, y, s, size_mm, font=SANS, fill=WHITE):
    f=ImageFont.truetype(font, int(size_mm*PX))
    d.text((cx*PX,y*PX), s, font=f, fill=fill, anchor='mt')

W,H = 900, 500
canvas=Image.new('RGB',(W*PX,H*PX),BG); d=ImageDraw.Draw(canvas)
lab=ImageFont.truetype(SANS, 9*PX); small=ImageFont.truetype(SANS, 6*PX)

# ---------- Option A: portrait, top logo piece + bottom QR piece ----------
ax, ay = 40, 95
topH, botH, PW = 140, 235, 250
d.text((ax*PX,14*PX),'A. Stacked (recommended)', font=lab, fill=(20,20,20))
d.text((ax*PX,27*PX),'250 x 375 mm total, 2 pieces, joint across the black gap', font=small, fill=(40,40,40))
d.line([(ax-10)*PX,(ay-28)*PX,(ax+PW+10)*PX,(ay-28)*PX], fill=(90,90,90), width=3*PX)  # tent bar
plate(d, ax, ay, PW, topH+botH)
lg=logo_img(228); canvas.paste(lg, (int((ax+11)*PX), int((ay+16)*PX)), lg)
seam_h(d, ax, ay+topH, PW, [ax+40, ax+125, ax+210])
text(d, ax+PW/2, ay+topH+12, 'SCAN TO SHOP', 15)
qimg, ver, n, mod = qr_img(165)
canvas.paste(qimg, (int((ax+(PW-165)/2)*PX), int((ay+topH+34)*PX)))
text(d, ax+PW/2, ay+topH+34+165+8, 'sarasotashirts.com', 13, fill=WHITE)
for hx in (ax+30, ax+PW-30): hook(d, hx, ay, ay-28)

# ---------- Option B: side by side ----------
bx, by = 360, 175
PH = 200; PW2 = 240
d.text((bx*PX,94*PX),'B. Side by side', font=lab, fill=(20,20,20))
d.text((bx*PX,107*PX),'480 x 200 mm total, 2 pieces, joint between logo and QR', font=small, fill=(40,40,40))
d.line([(bx-10)*PX,(by-28)*PX,(bx+2*PW2+10)*PX,(by-28)*PX], fill=(90,90,90), width=3*PX)
plate(d, bx, by, 2*PW2, PH)
lg2=logo_img(222); canvas.paste(lg2, (int((bx+9)*PX), int((by+(PH-lg2.height/PX)/2)*PX)), lg2)
seam_v(d, bx+PW2, by, PH, [by+40, by+100, by+160])
text(d, bx+PW2+PW2/2, by+10, 'SCAN TO SHOP', 13)
q2,_,_,mod2 = qr_img(140)
canvas.paste(q2, (int((bx+PW2+(PW2-140)/2)*PX), int((by+30)*PX)))
text(d, bx+PW2+PW2/2, by+30+140+7, 'sarasotashirts.com', 11)
for hx in (bx+30, bx+2*PW2-30): hook(d, hx, by, by-28)

d.text((360*PX,400*PX),'Colors shown are placeholders (black + white + one accent).', font=small, fill=(40,40,40))
d.text((360*PX,412*PX),'Grey hooks slot into the top edge and hang over the tent bar.', font=small, fill=(40,40,40))
d.text((360*PX,424*PX),'QR is real and scannable: try it with your phone on this image.', font=small, fill=(40,40,40))
canvas.save('sign_mockup_v1.png')
print('QR version', ver, 'modules', n, 'module mm A %.2f B %.2f' % (mod, mod2))
