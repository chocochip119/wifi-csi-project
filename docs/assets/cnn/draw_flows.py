from pathlib import Path
from html import escape
import subprocess
from PIL import Image

OUT=Path(__file__).parent
C={'ink':'#17324D','muted':'#61788F','line':'#C7D5E2','blue':'#337DC1','bluebg':'#EAF3FC','teal':'#208F83','tealbg':'#E9F6F2','purple':'#815CB2','purplebg':'#F1ECF8','orange':'#C58A28','orangebg':'#FFF5E3','graybg':'#F5F8FB'}

class SVG:
 def __init__(self,w,h,title):
  self.w,self.h=w,h
  self.s=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img"><title>{escape(title)}</title>', '<defs>']
  for key in ['muted','blue','teal','purple','orange']:
   self.s.append(f'<marker id="arrow-{key}" markerWidth="10" markerHeight="10" refX="8" refY="4" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L8,4 L0,8 Z" fill="{C[key]}"/></marker>')
  self.s+=['</defs>',f'<rect width="{w}" height="{h}" fill="white"/>']
 def rect(self,x,y,w,h,fill='graybg',stroke='line',r=14):
  self.s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{C.get(fill,fill)}" stroke="{C.get(stroke,stroke)}" stroke-width="1.5"/>')
 def text(self,x,y,text,size=22,color='ink',weight=400,anchor='start'):
  self.s.append(f'<text x="{x}" y="{y}" font-family="DejaVu Sans, sans-serif" font-size="{size}" font-weight="{weight}" fill="{C.get(color,color)}" text-anchor="{anchor}">{escape(text)}</text>')
 def line(self,points,color='muted',width=2.5,arrow=True,dash=False):
  p=' '.join(f'{x},{y}' for x,y in points)
  self.s.append(f'<polyline points="{p}" fill="none" stroke="{C.get(color,color)}" stroke-width="{width}" stroke-linejoin="round"'+(' stroke-dasharray="8 7"' if dash else '')+(f' marker-end="url(#arrow-{color})"' if arrow else '')+'/>')
 def box(self,x,y,w,h,title,lines=(),color='blue',title_size=25):
  self.rect(x,y,w,h,color+'bg',color)
  self.text(x+w/2,y+38,title,title_size,color,700,'middle')
  for i,s in enumerate(lines): self.text(x+w/2,y+73+i*29,s,21,'ink',400,'middle')
 def heading(self,num,y,title,sub=''):
  self.text(65,y,num,23,'blue',700)
  self.text(115,y,title,25,'ink',700)
  if sub:self.text(115,y+32,sub,19,'muted')
 def header(self,title,subtitle,badge):
  self.text(65,68,title,42,'ink',700)
  self.text(65,108,subtitle,23,'muted')
  self.text(self.w-65,65,badge,19,'muted',600,'end')
  self.line([(65,140),(self.w-65,140)],'line',1.5,False)
 def finish(self,name):
  self.s.append('</svg>')
  p=OUT/(name+'.svg');p.write_text('\n'.join(self.s))
  subprocess.run(['inkscape',str(p),'--export-type=png',f'--export-filename={OUT/(name+".png")}','--export-width=2400'],check=True,capture_output=True)
  png=OUT/(name+'.png')
  Image.open(png).convert('RGB').quantize(colors=256).save(png,optimize=True)

def network_compact():
 d=SVG(1920,1330,'WiSensing RX5 INT8 CNN dataflow')
 d.header('WiSensing | RX5 Pose CNN','Input [15, 128, 10] · INT8 inference · shared encoder weights · 12-joint coordinate regression','RX5 / tensor order [C, S, T]')
 d.heading('01',195,'Shared receiver encoder','One RX uses base / delta / mask; the same trained weights are applied to RX0–RX4.')
 # Four stages in one receiver path.
 xs=[90,550,1010,1470]; w=360
 blocks=[('RX input',['[3, 128, 10]','base / delta / mask'],'blue'),('Conv1 + RQ + GELU',['3 → 16 · kernel 5×3','[16, 128, 10]'],'blue'),('Conv2 + RQ + GELU',['16 → 32 · kernel 3×3','[32, 128, 10]'],'purple'),('Adaptive AvgPool',['output size 8×4','[32, 8, 4]'],'teal')]
 for i,(title,lines,color) in enumerate(blocks):
  d.box(xs[i],263,w,145,title,lines,color,24)
  if i<3:d.line([(xs[i]+w,335),(xs[i+1]-12,335)])
 d.text(90,443,'RQ = Requantization. BatchNorm is folded into Conv weights/bias for FPGA inference.',21,'muted')
 d.heading('02',513,'Receiver feature aggregation','Each receiver contributes 32×8×4 = 1,024 INT8 features.')
 rx_x=[90,448,806,1164,1522]
 for i,x in enumerate(rx_x):
  d.box(x,578,308,115,f'RX{i} encoder result',['[32, 8, 4]'], 'teal',23)
  d.line([(x+154,693),(x+154,732)],'teal',2.4,False)
 d.line([(244,732),(1676,732)],'teal',2.4,False)
 d.line([(960,732),(960,768)],'teal')
 d.box(710,768,500,100,'Concat along channels',['[160, 8, 4] = 5,120 features'],'teal',25)
 d.text(1250,811,'5 RX × 1,024',25,'teal',700)
 d.text(1250,845,'weights shared; features kept per RX',19,'muted')
 # The wraparound route is in whitespace above the FC row.
 d.line([(960,868),(960,903),(40,903),(40,1087),(80,1087)],'teal')
 d.heading('03',961,'FC head · coordinate regression')
 x=[90,448,806,1164,1522]
 b=[('Flatten',['5,120 features','C → S → T within each RX'],'teal'),('FC1 + GELU',['5120 → 128','128 INT8 activations'],'orange'),('FC2 + GELU',['128 → 128','128 INT8 activations'],'orange'),('FC3',['128 → 24','Requant · no GELU'],'orange'),('Pose output',['24 INT8 values','12 joints × (x, y)'],'blue')]
 for i,(title,lines,color) in enumerate(b):
  d.box(x[i],1015,308,145,title,lines,color,25)
  if i<4:d.line([(x[i]+308,1087),(x[i+1]-10,1087)])
 d.rect(65,1200,1790,69,'graybg','line',10)
 d.text(90,1243,'FC1 / FC2 include Requant before GELU. Dropout is omitted during inference. Coordinates = INT8 × output_scale.',21,'muted')
 d.text(65,1305,'Source: pl/cnn/README.md · pl/cnn/rtl/FC/fc_top.v · ml/pose/INT8.md',17,'muted')
 d.finish('WiSensing_RX5_CNN_Flow')

def fc():
 d=SVG(1920,1420,'WiSensing shared FC accelerator dataflow and control')
 d.header('FC Accelerator | Dataflow & Control','5120 → 128 → 128 → 24 · one shared MAC / Requant / GELU datapath','PERSONAL SCOPE / FC RTL')
 d.heading('01',195,'Select activation and weight sources by layer')
 # Read-side sources; write-side views below refer to the same physical banks.
 cards=[(80,'FC1 · 5120 → 128',['Activation: Feature RAM / Flatten','Weights: 512×64 FWFT FIFO','640 groups / output · 8 INT8 lanes'],'blue'),(660,'FC2 · 128 → 128',['Activation: Hidden RAM bank 0','Weights: FC weight RAM','16 groups / output · 8 INT8 lanes'],'teal'),(1240,'FC3 · 128 → 24',['Activation: Hidden RAM bank 1','Weights: FC weight RAM','16 groups / output · 8 INT8 lanes'],'purple')]
 for x,title,lines,c in cards:
  d.box(x,235,540,177,title,lines,c,25)
  d.line([(x+270,412),(x+270,465)],'muted',2.4,False)
 d.line([(350,465),(1510,465)],'muted',2.4,False)
 d.line([(600,465),(600,525),(350,525),(350,545)])
 d.heading('02',512,'Shared compute path')
 d.box(180,555,340,150,'Layer input MUX',['activation[63:0]','weight[63:0]'],'blue')
 d.line([(520,630),(595,630)])
 d.box(605,555,330,150,'8-lane FC MAC',['signed INT8 × INT8','adder tree → INT32 acc'],'blue')
 d.line([(935,630),(1010,630)])
 d.box(1020,555,340,150,'Requant',['bias → multiply → round','shift → INT8 saturation'],'purple')
 d.line([(1360,630),(1420,630),(1420,580),(1500,580)],'purple')
 d.text(1510,480,'FC1 / FC2',20,'purple',700)
 d.box(1510,505,330,150,'GELU LUT',['layer-specific lookup','INT8 activation'],'purple')
 d.line([(1675,655),(1675,755)],'purple')
 d.box(1510,755,330,170,'Hidden RAM · write',['FC1 → bank 0 (128 B)','FC2 → bank 1 (128 B)','8-bit write / 64-bit read'],'teal',23)
 # FC3 bypasses GELU completely.
 d.line([(1360,630),(1420,630),(1420,1033),(1500,1033)],'orange')
 d.text(1438,1001,'FC3',20,'orange',700)
 d.box(1510,958,330,150,'Pose Buffer',['24 INT8 coordinates','address 0–23'],'orange')
 d.rect(80,755,1280,100,'graybg','line')
 d.text(105,793,'Memory hand-off between layers',24,'teal',700)
 d.text(105,830,'FC1 writes bank 0 → FC2 reads bank 0; FC2 writes bank 1 → FC3 reads bank 1.',21,'ink')
 d.text(1510,949,'Same Hidden RAM as the read-side sources above.',14,'muted')
 d.heading('03',930,'Controller · address generation and completion')
 d.box(80,970,1280,140,'FC Controller',['select layer / generate read addresses / issue valid, first, last and tag','FC1 FIFO empty → pause issue and keep counters; final result stored → fc_done'],'blue',26)
 # Separate control and completion paths from data arrows.
 d.line([(80,1040),(45,1040),(45,630),(170,630)],'blue',2,True,True)
 d.text(62,874,'control',18,'blue',600)
 d.line([(1510,875),(1390,875),(1390,1145),(1180,1145),(1180,1118)],'teal',2,True,True)
 d.line([(1675,1108),(1675,1145),(1390,1145)],'orange',2,False,True)
 d.text(950,1180,'last Hidden / Pose write → layer_store_done',20,'muted')
 d.rect(65,1230,1790,113,'graybg','line',10)
 d.text(90,1268,'Dataflow, not a cycle-accurate timing waveform. Solid arrows: data. Dashed arrows: control / completion.',21,'muted')
 d.text(90,1307,'Shared RAM/LUT loaders supply weights, bias/multiplier/shift and GELU tables; memory ports are simplified here.',21,'muted')
 d.text(65,1387,'Source: pl/cnn/rtl/FC/fc_top.v · fc_controller.v · fc_mac.v · requant_core.v · gelu_core.v',17,'muted')
 d.finish('WiSensing_FC_Dataflow')

def feature_stack(d,cx,y,w,h,planes,color,grid=True):
 for k in range(planes-1,-1,-1):
  x=cx-w/2+k*8; yy=y-k*6
  d.s.append(f'<rect x="{x}" y="{yy}" width="{w}" height="{h}" fill="{C[color+"bg"]}" stroke="{C[color]}" stroke-width="2"/>')
 if grid:
  for col in range(1,4):
   xx=cx-w/2+w*col/4
   d.line([(xx,y),(xx,y+h)],color,0.8,False)
  for row in range(1,6):
   yy=y+h*row/6
   d.line([(cx-w/2,yy),(cx+w/2,yy)],color,0.8,False)

def neuron_column(d,cx,ys,color):
 for y in ys:
  d.s.append(f'<circle cx="{cx}" cy="{y}" r="10" fill="{C[color+"bg"]}" stroke="{C[color]}" stroke-width="2"/>')
 for y in [1290,1302,1314]:
  d.s.append(f'<circle cx="{cx}" cy="{y}" r="2.7" fill="{C[color]}"/>')

def network():
 d=SVG(2400,1610,'Complete WiSensing RX5 INT8 Pose CNN architecture')
 d.header('WiSensing | Complete RX5 Pose CNN','Full layer flow · feature-map illustrations · INT8 FPGA inference · 12-joint coordinate regression','RX5 / [C, S, T], batch omitted')
 d.heading('01',198,'Shared receiver encoder','Total input [15, 128, 10] → gather base / delta / mask for each RX → apply the same trained encoder weights.')
 centers=[175,585,995,1405,1815,2220]
 data=[('Input','base / delta / mask','[3, 128, 10]','3 input channels',3,'blue'),('Conv1','3 → 16 · kernel 5×3','[16, 128, 10]','stride 1 · padding (2,1)',8,'blue'),('Requant + GELU','INT8 scale + LUT activation','[16, 128, 10]','shape unchanged',8,'purple'),('Conv2','16 → 32 · kernel 3×3','[32, 128, 10]','stride 1 · padding (1,1)',10,'blue'),('Requant + GELU','INT8 scale + LUT activation','[32, 128, 10]','shape unchanged',10,'purple'),('Adaptive AvgPool','output size 8×4','[32, 8, 4]','1,024 features / RX',8,'teal')]
 for i,(title,sub,shape,note,n,color) in enumerate(data):
  x=centers[i]
  d.text(x,294,title,28,color,700,'middle')
  d.text(x,330,sub,21,'muted',400,'middle')
  feature_stack(d,x-20,395,90 if i!=5 else 76,168 if i!=5 else 118,n,color)
  d.text(x,616,shape,27,'ink',700,'middle')
  d.text(x,652,note,21,'muted',400,'middle')
  if i<5:d.line([(x+126,482),(centers[i+1]-113,482)])
 d.line([(65,694),(2335,694)],'line',1.5,False)
 d.heading('02',746,'Receiver feature aggregation','Five receiver outputs are concatenated along channels; values are then flattened in RX → C → S → T order.')
 rxs=[155,445,735,1025,1315]
 for i,x in enumerate(rxs):
  d.text(x,833,f'RX{i} encoder output',22,'muted',500,'middle')
  feature_stack(d,x-17,871,62,86,6,'teal')
  d.text(x,998,'[32, 8, 4]',24,'ink',700,'middle')
  d.line([(x,1015),(x,1044)],'teal',2,False)
 d.line([(155,1044),(1515,1044),(1515,910),(1675,910)],'teal',2.5)
 d.text(1760,833,'Concat',28,'teal',700,'middle')
 feature_stack(d,1730,900,82,75,10,'teal')
 d.text(1760,998,'[160, 8, 4]',25,'ink',700,'middle')
 d.text(1760,1032,'5 × 32 × 8 × 4 = 5,120',20,'muted',400,'middle')
 d.line([(1885,910),(2070,910)],'teal')
 d.text(2210,833,'Flatten',28,'teal',700,'middle')
 for y in [867,885,903,939,957]:
  d.s.append(f'<circle cx="2210" cy="{y}" r="8" fill="{C["tealbg"]}" stroke="{C["teal"]}" stroke-width="2"/>')
 for y in [916,922,928]: d.s.append(f'<circle cx="2210" cy="{y}" r="2" fill="{C["teal"]}"/>')
 d.text(2210,998,'[5120]',25,'ink',700,'middle')
 # Wrap from the flatten output to the head without crossing the section title.
 d.line([(2210,1015),(2210,1080),(40,1080),(40,1300),(158,1300)],'teal',2.5)
 d.heading('03',1141,'FC head · pose coordinate regression')
 xs=[180,680,1180,1680]
 ys=[1236,1264,1340,1368,1396]
 for a,b in zip(xs,xs[1:]):
  for y1 in ys:
   for y2 in ys:
    d.line([(a+11,y1),(b-11,y2)],'line',0.9,False)
 labels=[('Head input','5,120 features','[5120]','Flatten output','blue'),('FC1 + Requant + GELU','5120 → 128','[128]','Hidden RAM bank 0','orange'),('FC2 + Requant + GELU','128 → 128','[128]','Hidden RAM bank 1','orange'),('FC3 + Requant','128 → 24','[24]','Pose Buffer · no GELU','orange')]
 for x,(title,sub,shape,note,c) in zip(xs,labels):
  d.text(x,1191,title,26,c,700,'middle')
  d.text(x,1222,sub,21,'muted',400,'middle')
  neuron_column(d,x,ys,c)
  d.text(x,1441,shape,26,'ink',700,'middle')
  d.text(x,1476,note,21,'muted',400,'middle')
 d.line([(1770,1315),(2020,1315)],'orange')
 d.text(2195,1191,'12-joint pose',28,'blue',700,'middle')
 d.text(2195,1222,'24 values × output_scale',21,'muted',400,'middle')
 pts={'ls':(2150,1262),'rs':(2240,1262),'le':(2127,1300),'re':(2263,1300),'lw':(2110,1339),'rw':(2280,1339),'lh':(2163,1330),'rh':(2227,1330),'lk':(2150,1371),'rk':(2240,1371),'la':(2140,1410),'ra':(2250,1410)}
 for a,b in [('ls','rs'),('ls','le'),('le','lw'),('rs','re'),('re','rw'),('ls','lh'),('rs','rh'),('lh','rh'),('lh','lk'),('lk','la'),('rh','rk'),('rk','ra')]: d.line([pts[a],pts[b]],'teal',3,False)
 for x,y in pts.values(): d.s.append(f'<circle cx="{x}" cy="{y}" r="5" fill="{C["teal"]}"/>')
 d.text(2195,1441,'12 × (x, y)',26,'ink',700,'middle')
 d.text(2195,1476,'2D coordinate output',21,'muted',400,'middle')
 d.line([(65,1510),(2335,1510)],'line',1.5,False)
 d.text(65,1547,'BatchNorm is folded into Conv weights/bias. Dropout is omitted during inference. All FC layers include Requant; FC3 has no GELU.',21,'muted')
 d.text(65,1581,'Blocks and neuron counts are schematic; labels show actual tensor sizes. Source: pl/cnn/README.md · pl/cnn/rtl/FC/fc_top.v',18,'muted')
 d.finish('WiSensing_RX5_CNN_Flow')

if __name__ == '__main__':
 network();fc()
