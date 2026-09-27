"""Layout-only PNG proof from uncompressed XML; not a native draw.io render."""
from pathlib import Path
import math
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).parent
FONT='C:/Windows/Fonts/malgun.ttf'
SCALE=.65

def style(c):
    return dict((p.split('=',1) if '=' in p else (p,'1')) for p in c.get('style','').split(';') if p)

for i,page in enumerate(ET.parse(ROOT/'pose_cnn_ctrl_fsm.drawio').getroot().findall('diagram'),1):
    model=page.find('mxGraphModel'); cells={c.get('id'):c for c in model.find('root')}
    W,H=int(model.get('pageWidth')),int(model.get('pageHeight'))
    image=Image.new('RGB',(round(W*SCALE),round(H*SCALE)), 'white'); draw=ImageDraw.Draw(image)
    def rect(c):
        g=c.find('mxGeometry')
        x,y,w,h=[float(g.get(k,0)) for k in ('x','y','width','height')]
        par=cells.get(c.get('parent'))
        if par is not None and par.get('vertex')=='1':
            px,py,_,_=rect(par); x+=px;y+=py
        return x,y,w,h
    def px(p):return tuple(round(v*SCALE) for v in p)
    def line(points,fill='#202020',width=1.3,dash=False):
        for (ax,ay),(bx,by) in zip(points,points[1:]):
            if not dash:draw.line([px((ax,ay)),px((bx,by))],fill=fill,width=max(1,round(width*SCALE)))
            else:
                length=math.hypot(bx-ax,by-ay)
                for t in range(0,math.ceil(length),12):
                    u=min(t+7,length)
                    draw.line([px((ax+(bx-ax)*t/length,ay+(by-ay)*t/length)),px((ax+(bx-ax)*u/length,ay+(by-ay)*u/length))],fill=fill,width=max(1,round(width*SCALE)))
    def label(text,box,st):
        x,y,w,h=box; f=ImageFont.truetype(FONT,max(8,round(float(st.get('fontSize',21))*SCALE)))
        lines=[]; maxw=max(20,(w-8)*SCALE)
        for raw in text.split('\n'):
            pending=''
            for ch in raw:
                if pending and draw.textlength(pending+ch,font=f)>maxw:
                    lines.append(pending);pending=ch
                else:pending+=ch
            lines.append(pending)
        lh=round(float(st.get('fontSize',21))*SCALE*1.38)
        yp=y*SCALE+(h*SCALE-lh*len(lines))/2
        for t in lines:
            tw=draw.textlength(t,font=f)
            align=st.get('align','center')
            xp=x*SCALE+ (0 if align=='left' else w*SCALE-tw if align=='right' else (w*SCALE-tw)/2)
            draw.text((xp,yp),t,font=f,fill=st.get('fontColor','#202020'))
            yp+=lh
    def anchor(cid,u,v):
        c=cells[cid];x,y,w,h=rect(c)
        if 'ellipse' in style(c):
            vx,vy=2*u-1,2*v-1;n=math.hypot(vx,vy)
            if n:vx/=n;vy/=n
            return x+w/2+vx*w/2,y+h/2+vy*h/2
        return x+w*u,y+h*v
    edge_labels=[]
    for c in cells.values():
        if c.get('edge')!='1':continue
        st=style(c);g=c.find('mxGeometry')
        ps=[anchor(c.get('source'),float(st.get('exitX',.5)),float(st.get('exitY',1)))]
        ps += [(float(pt.get('x')),float(pt.get('y'))) for pt in g.findall('./Array/mxPoint')]
        ps += [anchor(c.get('target'),float(st.get('entryX',.5)),float(st.get('entryY',0)))]
        color=st.get('strokeColor','#202020');line(ps,color,dash=st.get('dashed')=='1')
        ax,ay=ps[-2];bx,by=ps[-1]; angle=math.atan2(by-ay,bx-ax)
        arrow=[(bx,by),(bx-11*math.cos(angle-.4),by-11*math.sin(angle-.4)),(bx-11*math.cos(angle+.4),by-11*math.sin(angle+.4))]
        draw.polygon([px(p) for p in arrow],fill=color)
        if c.get('value'):
            lengths=[math.dist(a,b) for a,b in zip(ps,ps[1:])];half=sum(lengths)/2
            for j,length in enumerate(lengths):
                if half<=length:
                    t=half/length if length else 0;x=ps[j][0]+(ps[j+1][0]-ps[j][0])*t;y=ps[j][1]+(ps[j+1][1]-ps[j][1])*t;break
                half-=length
            of=g.find("mxPoint[@as='offset']")
            if of is not None:x+=float(of.get('x',0));y+=float(of.get('y',0))
            edge_labels.append((c.get('value'),x,y,st))
    for c in cells.values():
        if c.get('vertex')!='1':continue
        st=style(c);x,y,w,h=rect(c);box=px((x,y,x+w,y+h));stroke=st.get('strokeColor','#202020');fill=st.get('fillColor','#FFFFFF')
        if stroke!='none':
            if 'ellipse' in st:draw.ellipse(box,fill=fill,outline=stroke,width=1)
            elif 'rhombus' in st:draw.polygon([px(p) for p in [(x+w/2,y),(x+w,y+h/2),(x+w/2,y+h),(x,y+h/2)]],fill=fill,outline=stroke)
            elif 'line' in st:line([(x,y),(x+w,y+h)],stroke)
            elif st.get('rounded')=='1':draw.rounded_rectangle(box,radius=round(min(h,w)*.24*SCALE),fill=fill,outline=stroke,width=1)
            elif st.get('dashed')=='1':
                draw.rectangle(box,fill=fill);line([(x,y),(x+w,y),(x+w,y+h),(x,y+h),(x,y)],stroke,dash=True)
            else:draw.rectangle(box,fill=fill,outline=stroke,width=1)
        if c.get('value'):label(c.get('value'),(x+6,y,w-12,h),st)
    for text,x,y,st in edge_labels:
        f=ImageFont.truetype(FONT,max(8,round(float(st.get('fontSize',20))*SCALE)))
        tw=max(draw.textlength(t,font=f) for t in text.split('\n'))/SCALE+12
        th=len(text.split('\n'))*float(st.get('fontSize',20))*1.4+8
        draw.rectangle(px((x-tw/2,y-th/2,x+tw/2,y+th/2)),fill='white')
        label(text,(x-tw/2,y-th/2,tw,th),st)
    dest=ROOT/'preview'/f'layout_p{i}.png';dest.parent.mkdir(exist_ok=True)
    image.save(dest)
    print('LAYOUT ONLY:',dest)
