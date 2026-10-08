import numpy as np, cv2, segno, math
from PIL import Image, ImageDraw, ImageFont
PX=4
BLACK=(20,20,20); WHITE=(242,242,242); RED=(196,32,44); BG=(214,216,219); STAND=(52,52,56); STAND_TOP=(80,80,86)
SANS='/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf'
OBL='/usr/share/fonts/truetype/freefont/FreeSansBoldOblique.ttf'
SERIF='/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'

# ---- approximate the red logo from the website file (labels per connected component) ----
im=np.asarray(Image.open('logo_website.png').convert('RGBA')).astype(int)
rgb,a=im[...,:3],im[...,3]
g=((a>128)&(rgb[...,1]>rgb[...,0]+8)&(rgb.max(-1)<200)).astype(np.uint8)
w=((a>128)&(rgb.min(-1)>200)).astype(np.uint8)
ng,lg,sg,_=cv2.connectedComponentsWithStats(g,8); nw,lw,sw,_=cv2.connectedComponentsWithStats(w,8)
H0,W0=g.shape
direct=np.zeros_like(g); embro=np.zeros_like(g); letters=np.zeros_like(g); teeline=np.zeros_like(g); teefill=np.zeros_like(g)
for i in range(1,ng):
    x,y,ww,hh,ar=sg[i]
    if y<300: direct|=(lg==i)
    elif ar>100000 and ww<700: teefill|=(lg==i)
for i in range(1,nw):
    x,y,ww,hh,ar=sw[i]
    if y<700 and hh>250: embro|=(lw==i)
    elif ww>500 and hh>500 and y<700: teeline|=(lw==i)
    elif 780<y<900: letters|=(lw==i)
k=lambda r: cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(2*r+1,2*r+1))
crop=slice(0,1260)
# pill (stadium) ring, skipping the tee
pill=np.zeros_like(g); cv2.rectangle(pill,(231,737),(3600-231,1199),1,-1)
cv2.circle(pill,(231,968),231,1,-1); cv2.circle(pill,(3600-231,968),231,1,-1)
tee=cv2.dilate(teefill|teeline,k(20))
ring_red=(pill-cv2.erode(pill,k(19)))&(1-tee)
ring_white=(cv2.dilate(pill,k(14))-pill)&(1-tee)
tee_red=teeline; tee_white=(cv2.dilate(teeline|teefill,k(14))-(teeline|teefill))
embro_white=cv2.dilate(embro,k(14))
out=np.zeros((H0,W0,4),np.uint8)
def put(m,c): out[m.astype(bool)]=c+(255,)
put(embro_white,WHITE); put(embro,RED); put(direct,WHITE)
put(ring_white,WHITE); put(ring_red,RED); put(tee_white,WHITE); put(tee_red,RED); put(letters,WHITE)
logo=Image.fromarray(out[crop],'RGBA')
d=ImageDraw.Draw(logo)
d.text((3560,560),'&',font=ImageFont.truetype(SERIF,260),fill=WHITE+(255,),anchor='mm')
f=ImageFont.truetype(OBL,78)
d.text((1730,900),'CUSTOM',font=f,fill=WHITE+(255,),anchor='mm'); d.text((1730,995),'TEES',font=f,fill=WHITE+(255,),anchor='mm')
bb=logo.getbbox(); logo=logo.crop(bb)

# ---- badge outline (mm, y up), flat bottom sits in the stand ----
SW,SH=245,245
def badge_pts(inset=0.0):
    pts=[]; c=SW/2
    for i in range(0,101):                      # top edge, left to right
        x=i/100*SW; t=abs(x-c)/c
        y=218+24*((1+math.cos(math.pi*t))/2)**1.4
        pts.append((x,y))
    for i in range(1,100):                      # right side, top to bottom (concave)
        y=218-i/100*218; pts.append((SW-11*math.sin(math.pi*y/218)**0.8,y))
    pts += [(SW,0),(0,0)]
    for i in range(1,100):
        y=i/100*218; pts.append((11*math.sin(math.pi*y/218)**0.8,y))
    return pts
def to_px(pts,ox,oy): return [((ox+x)*PX,(oy+SH-y)*PX) for x,y in pts]
def poly_mask(pts,ox,oy,size,erode_mm=0):
    m=np.zeros(size,np.uint8)
    cv2.fillPoly(m,[np.array(to_px(pts,ox,oy),np.int32)],1)
    if erode_mm: m=cv2.erode(m,k(int(erode_mm*PX)))
    return m

W,Hc=560,320
canvas=Image.new('RGB',(W*PX,Hc*PX),BG); dr=ImageDraw.Draw(canvas)
ox,oy=30,40
size=(Hc*PX,W*PX)
outer=poly_mask(badge_pts(),ox,oy,size)
canvas.paste(Image.new('RGB',canvas.size,BLACK),(0,0),Image.fromarray(outer*255))
b1=poly_mask(badge_pts(),ox,oy,size,6); b2=poly_mask(badge_pts(),ox,oy,size,7.6)
canvas.paste(Image.new('RGB',canvas.size,WHITE),(0,0),Image.fromarray((b1-b2)*255))
# logo
lw_mm=192; lgi=logo.resize((int(lw_mm*PX),int(logo.height*lw_mm*PX/logo.width)),Image.LANCZOS)
lh_mm=lgi.height/PX
canvas.paste(lgi,(int((ox+(SW-lw_mm)/2)*PX),int((oy+SH-221)*PX)),lgi)
# QR right, text left
q=segno.make('https://sarasotashirts.com',error='q',micro=False); m=q.matrix; n=len(m); quiet=3
QS=102; mod=QS/(n+2*quiet); qx,qy=ox+122,oy+SH-150
dr.rounded_rectangle([qx*PX,qy*PX,(qx+QS)*PX,(qy+QS)*PX],3*PX,fill=WHITE)
for r,row in enumerate(m):
    for c,v in enumerate(row):
        if v:
            x0=(qx+(c+quiet)*mod)*PX; y0=(qy+(r+quiet)*mod)*PX
            dr.rectangle([x0,y0,x0+mod*PX-1,y0+mod*PX-1],fill=BLACK)
big=ImageFont.truetype(SANS,int(17*PX)); mid=ImageFont.truetype(SANS,int(8.2*PX))
tx=ox+66
dr.text((tx*PX,(qy+20)*PX),'SCAN',font=big,fill=RED,anchor='mm')
dr.text((tx*PX,(qy+42)*PX),'TO SHOP',font=big,fill=WHITE,anchor='mm')
ar_y=(qy+62)*PX
dr.line([((tx-28)*PX,ar_y),((tx+30)*PX,ar_y)],fill=RED,width=int(2.4*PX))
dr.polygon([((tx+36)*PX,ar_y),((tx+27)*PX,ar_y-5*PX),((tx+27)*PX,ar_y+5*PX)],fill=RED)
dr.text((tx*PX,(qy+82)*PX),'sarasotashirts.com',font=mid,fill=WHITE,anchor='mm')
# stand (front view): plinth in front of the bottom 18 mm
sx0,sx1=ox-4,ox+SW+4; s_top=oy+SH-18; s_bot=oy+SH+10
dr.rounded_rectangle([sx0*PX,s_top*PX,sx1*PX,s_bot*PX],3*PX,fill=STAND)
dr.rectangle([sx0*PX+6,s_top*PX,sx1*PX-6,(s_top+3)*PX],fill=STAND_TOP)
# side view of the stand (drawn at 0.55 scale)
vx,vy,SC=360,250,0.55
lab=ImageFont.truetype(SANS,int(7*PX)); sm=ImageFont.truetype(SANS,int(5.2*PX))
dr.text((340*PX,60*PX),'Side view (half scale)',font=lab,fill=(25,25,25))
dr.text((340*PX,70*PX),'Sign drops into a full-width slot, leaning back 10 degrees.',font=sm,fill=(40,40,40))
P=lambda pts: [((vx+x*SC)*PX,(vy-y*SC)*PX) for x,y in pts]
ang=math.radians(10); L=245; t=4.2; bx,by=28,12
sign=[(bx,by),(bx+t,by),(bx+t+L*math.sin(ang),by+L*math.cos(ang)),(bx+L*math.sin(ang),by+L*math.cos(ang))]
dr.polygon(P(sign),fill=BLACK)
base=[(0,0),(90,0),(90,18),(40,30),(22,30),(0,24)]
slot=[(bx-0.2,by),(bx+t+0.2,by),(bx+t+0.2+18*math.tan(ang),30),(bx-0.2+18*math.tan(ang),30)]
dr.polygon(P(base),fill=STAND)
dr.polygon(P(sign),fill=BLACK)
dr.text(((vx+45*SC)*PX,(vy+8)*PX),'stand about 250 x 90 x 30 mm',font=sm,fill=(40,40,40),anchor='mt')
dr.text((340*PX,285*PX),'Sign: 245 x 245 mm, one piece, fills the P1S plate.',font=sm,fill=(40,40,40))
dr.text((340*PX,294*PX),'Colors are placeholders. Logo approximated until I have your red file.',font=sm,fill=(40,40,40))
dr.text((340*PX,303*PX),'QR is real: scan it on this image to test.',font=sm,fill=(40,40,40))
canvas.save('sign_mockup_v2.png'); print('QR v',q.version,'module mm %.2f'%mod)
