"""Build editable, uncompressed draw.io XML. No RTL or specification edits."""
from pathlib import Path
import xml.etree.ElementTree as E

OUT = Path(__file__).with_name('pose_cnn_ctrl_fsm.drawio')
STATES = 'IDLE DECODE LD_RD1 LD_RD2 LD_WAIT IN_RD ENC FC1 FC2 FC3 WR ERR_DRAIN FINISH'.split()
CODES = {s: format(i, '04b') for i, s in enumerate(STATES)}
BLACK, ORANGE = '#202020', '#B86A15'
FONT = 'Malgun Gothic'
TARGET_NOTE = '목표 설계 도면. 현재 RTL 구현 범위는 PROJECT_CONTEXT.md 8절 참조.'
doc = E.Element('mxfile', host='app.diagrams.net', type='device', compressed='false')

class Page:
    def __init__(self, pid, name, width, height):
        self.pid, self.width, self.height, self.seq = pid, width, height, 0
        self.diagram = E.SubElement(doc, 'diagram', id=pid, name=name)
        model = E.SubElement(self.diagram, 'mxGraphModel', dx=str(width), dy=str(height),
            grid='0', gridSize='10', guides='1', tooltips='1', connect='1', arrows='1',
            fold='1', page='1', pageScale='1', pageWidth=str(width), pageHeight=str(height),
            math='0', shadow='0', background='#FFFFFF')
        self.root = E.SubElement(model, 'root')
        E.SubElement(self.root, 'mxCell', id='0')
        E.SubElement(self.root, 'mxCell', id='1', parent='0')
        self.text('title', f'pose_cnn_ctrl   {name}', 60, 28, width-120, 65, size=36)
        self.text('legend', '실선: 정상 경로·확정 계약     주황 점선: D08 미결     T = 참, F = 거짓',
                  60, 105, width-120, 34, size=20)
        self.text('target_note', TARGET_NOTE, 60, 145, width-120, 32, size=19)

    def id(self, key): return self.pid + '_' + key

    def node(self, key, value, x, y, w, h, style='', parent='1', **attrs):
        nid = self.id(key)
        base = f'html=0;whiteSpace=wrap;fontFamily={FONT};fontSize=21;fontColor={BLACK};strokeColor={BLACK};strokeWidth=1.3;fillColor=#FFFFFF;align=center;verticalAlign=middle;spacing=8;'
        c = E.SubElement(self.root, 'mxCell', id=nid, value=value, style=base+style,
                         vertex='1', parent=parent, **attrs)
        E.SubElement(c, 'mxGeometry', x=str(x), y=str(y), width=str(w), height=str(h), **{'as':'geometry'})
        return nid

    def text(self, key, value, x,y,w,h, size=21, align='left', parent='1', color=BLACK):
        return self.node(key,value,x,y,w,h,
            f'text;strokeColor=none;fillColor=none;spacing=0;fontSize={size};align={align};fontColor={color};',parent)

    def state(self, name, x,y,w,h, body, circle=False, pending=False):
        extra = 'ellipse;' if circle else 'rounded=0;'
        if pending: extra += f'dashed=1;dashPattern=7 5;strokeColor={ORANGE};'
        sid = self.node('state_'+name, '', x,y,w,h,extra)
        if circle:
            self.text('name_'+name,name,20,19,w-40,32,24,'center',sid)
            self.text('code_'+name,"4'b"+CODES[name],20,55,w-40,27,18,'center',sid)
            # A line is a vertex, not a transition edge.
            self.node('divider_'+name,'',8,89,w-16,1,'line;strokeWidth=1;',sid)
            self.text('body_'+name,body,12,98,w-24,h-119,18,'center',sid)
        else:
            self.text('name_'+name,name,15,10,w-145,32,23,'left',sid)
            self.text('code_'+name,"4'b"+CODES[name],w-126,11,109,30,19,'right',sid)
            self.text('body_'+name,body,16,55,w-32,h-67,21,'center',sid)
        return sid

    def diamond(self,key,value,x,y,w=240,h=120,pending=False):
        s='rhombus;spacing=0;'
        if pending: s+=f'dashed=1;dashPattern=7 5;strokeColor={ORANGE};'
        return self.node(key,value,x,y,w,h,s)

    def action(self,key,value,x,y,w=430,h=125,pending=False):
        s='rounded=1;arcSize=50;'
        if pending: s+=f'dashed=1;dashPattern=7 5;strokeColor={ORANGE};'
        return self.node(key,value,x,y,w,h,s)

    def link(self,key,target,x,y,pending=False):
        s='ellipse;fontSize='+('14;' if target=='ERR_DRAIN' else '19;')
        if pending: s+=f'dashed=1;dashPattern=7 5;strokeColor={ORANGE};'
        return self.node(key,target,x,y,112,112,s)

    def edge(self,key,source,target,label='',points=(),ports=(.5,1,.5,0),pending=False, labelpos=0, offset=(0,0), curved=False):
        a,b,c,d=ports
        s=f'edgeStyle=none;rounded=0;html=0;endArrow=classic;endFill=1;endSize=9;strokeColor={ORANGE if pending else BLACK};strokeWidth=1.3;fontFamily={FONT};fontSize=20;fontColor={ORANGE if pending else BLACK};labelBackgroundColor=#FFFFFF;exitX={a};exitY={b};exitDx=0;exitDy=0;entryX={c};entryY={d};entryDx=0;entryDy=0;'
        if pending:s+='dashed=1;dashPattern=7 5;'
        if curved:s+='curved=1;'
        e=E.SubElement(self.root,'mxCell',id=self.id(key),value=label,style=s,edge='1',parent='1',source=source,target=target)
        g=E.SubElement(e,'mxGeometry',x=str(labelpos),y='0',relative='1',**{'as':'geometry'})
        if points:
            ar=E.SubElement(g,'Array',**{'as':'points'})
            for px,py in points:E.SubElement(ar,'mxPoint',x=str(px),y=str(py))
        E.SubElement(g,'mxPoint',x=str(offset[0]),y=str(offset[1]),**{'as':'offset'})
        return e

    def note(self,key,value,x,y,w,h,pending=False):
        style='rounded=0;align=left;spacing=16;fontSize=20;'
        if pending:style+=f'dashed=1;dashPattern=7 5;strokeColor={ORANGE};fontColor={ORANGE};'
        return self.node(key,value,x,y,w,h,style)


# Page 1: overview. State details are on the ASM pages, as in the example.
p=Page('fsm','FSM 상태도',3050,1490)
pos={'IDLE':(160,540),'DECODE':(570,540),'LD_RD1':(990,260),'LD_RD2':(1420,260),
 'LD_WAIT':(1850,260),'IN_RD':(570,1050),'ENC':(1000,1050),'FC1':(1430,1050),
 'FC2':(1860,1050),'FC3':(2290,1050),'WR':(2720,1050),'ERR_DRAIN':(1430,660),'FINISH':(2420,540)}
S={}
for n,(x,y) in pos.items():
    b='status_busy = '+('0' if n=='IDLE' else '1')
    if n=='ERR_DRAIN':b+='\nD08 미결'
    S[n]=p.state(n,x,y,200,200,b,circle=True,pending=n=='ERR_DRAIN')
reset=p.text('reset','reset',45,625,75,32,18)
p.edge('reset_edge',reset,S['IDLE'],ports=(1,.5,0,.5))
p.edge('t01',S['IDLE'],S['DECODE'],'reg_start',ports=(1,.5,0,.5),offset=(0,-24))
p.edge('t03',S['DECODE'],S['FINISH'],'cmd != 0 && cmd != 1 / err_code ← 1 (BAD_CMD)',[(810,495),(2350,495)],(.9,.15,.1,.15),offset=(0,-20))
p.edge('t04',S['DECODE'],S['FINISH'],'cmd == 0 && !cfg_ok / err_code ← 2 (NO_CFG)',[(830,590),(2350,590)],(1,.4,0,.4),offset=(0,22))
p.edge('t05',S['DECODE'],S['LD_RD1'],'cmd == 1',[(670,360)],(.5,0,0,.5),offset=(0,-22))
p.edge('t06',S['DECODE'],S['IN_RD'],'cmd == 0 && cfg_ok',ports=(.5,1,.5,0),offset=(134,0))
p.edge('t07',S['LD_RD1'],S['LD_RD2'],'mem_rd_busy 1→0',ports=(1,.5,0,.5),offset=(0,-24))
p.edge('t08',S['LD_RD2'],S['LD_WAIT'],'mem_rd_busy 1→0',ports=(1,.5,0,.5),offset=(0,-24))
p.edge('t09',S['LD_WAIT'],S['FINISH'],'loader_done\nloader_err이면 err_code ← 3',[(2180,360),(2520,360)],(1,.5,.5,0),offset=(0,-40))
for tid,a,b,label in [('10','IN_RD','ENC','mem_rd_busy 1→0'),('11','ENC','FC1','enc_done'),
 ('12','FC1','FC2','fc_done &&\n!mem_rd_busy'),('13','FC2','FC3','fc_done'),('14','FC3','WR','fc_done')]:
    p.edge('t'+tid,S[a],S[b],label,ports=(1,.5,0,.5),offset=(0,-27))
p.edge('t15',S['WR'],S['FINISH'],'mem_wr_busy 1→0\nmem_wr_err이면 err_code ← 5',[(2820,885),(2710,885)],(.5,0,1,.85),offset=(125,-45))
p.edge('t16a',S['LD_RD1'],S['ERR_DRAIN'],'mem_rd_err\nerr_code ← 4 [D08]',[(1090,745)],(.5,1,0,.45),True,offset=(-30,20))
p.edge('t16b',S['LD_RD2'],S['ERR_DRAIN'],'mem_rd_err\nerr_code ← 4 [D08]',ports=(.5,1,.5,0),pending=True,offset=(125,0))
p.edge('t16c',S['IN_RD'],S['ERR_DRAIN'],'mem_rd_err / err_code ← 4 [D08]',[(870,975),(1270,975),(1270,810)],(.85,.1,0,.75),True,offset=(-15,18))
p.edge('t16d',S['FC1'],S['ERR_DRAIN'],'mem_rd_err\nerr_code ← 4 [D08]',ports=(.5,0,.5,1),pending=True,offset=(125,0))
p.edge('t17',S['ERR_DRAIN'],S['FINISH'],'!mem_rd_busy && !mem_wr_busy [D08]',[(2110,760)],(1,.5,0,.85),True,offset=(0,-25))
p.edge('t18',S['FINISH'],S['IDLE'],'무조건 (FINISH 1 cycle)',[(2970,540),(2970,205),(260,205)],(.9,.2,.5,0),offset=(0,-18))
p.note('d06','D06 확정 (2026-09-25) — FC1 read base\nload_base_reg = DECODE→LD_RD1 에서 적재한 LOAD 당시 값. 현재 reg_weight_addr 을 쓰지 않는다',1550,1290,780,90)
p.text('counts','13 states · 20 transitions · 자기 전이 생략\n세부 레벨 출력·전이 동작: ASM 2–4쪽',60,1335,1120,65,21)
p.text('mapping','T-01R  IDLE / DECODE / FINISH     T-03  LD_RD1 / LD_RD2 / LD_WAIT     T-04  IN_RD / ENC\nT-05  FC1     T-06  FC2 / FC3 / WR     T-07  ERR_DRAIN·오류 진입 (D08)     ※ T-02 는 M00 단독 검증(상태 없음)',60,1410,2900,60,20)


# Page 2: common ASM. Sticky status rules remain separate from the flow.
p=Page('common','ASM - 공통',3030,1920)
idle=p.state('IDLE',120,265,420,115,'status_busy = 0')
start=p.diamond('start_q','reg_start?',210,485,240,120)
p.edge('idle_start',idle,start)
p.edge('t02',start,idle,'F',[(65,545),(65,322)],(0,.5,0,.5),offset=(-20,0))
snap=p.action('snapshot','cmd ← reg_cmd\ninput_addr ← reg_input_addr\nweight_addr ← reg_weight_addr\noutput_addr ← reg_output_addr\nerr_code ← 0',100,710,460,230)
p.edge('start_snapshot',start,snap,'T',offset=(26,0))
decode_link=p.link('to_decode','DECODE',274,1050)
p.edge('t01',snap,decode_link)
p.note('snapshot_note','START 수락 에지에 snapshot\n같은 에지에 DECODE 진입 → busy = 1\n표시 해제는 오른쪽 독립 갱신 표 참조',95,1230,485,150)

dec=p.state('DECODE',780,265,410,115,'status_busy = 1\n1 cycle 고정')
cmd1=p.diamond('cmd1_q','cmd == 1?',875,475,220,110)
p.edge('decode_cmd1',dec,cmd1)
ldact=p.action('start_load','loader_start = 1\nmem_rd_start = 1\naddr = load_base + 0\nbytes = 5,936',1220,442,380,180)
p.edge('cmd1_load',cmd1,ldact,'T',ports=(1,.5,0,.5),offset=(0,-24))
ldlink=p.link('to_ld1','LD_RD1',1640,475)
p.edge('t05',ldact,ldlink,ports=(1,.5,0,.5))
cmd0=p.diamond('cmd0_q','cmd == 0?',875,765,220,110)
p.edge('not_load',cmd1,cmd0,'F',offset=(25,0))
bad=p.action('bad_cmd','err_code ← 1\nBAD_CMD',1240,752,340,125)
p.edge('bad_branch',cmd0,bad,'F',ports=(1,.5,0,.5),offset=(0,-22))
badend=p.link('bad_finish','FINISH',1640,760)
p.edge('t03',bad,badend,ports=(1,.5,0,.5))
cfg=p.diamond('cfg_q','cfg_ok?',875,1060,220,110)
p.edge('infer_check',cmd0,cfg,'T',offset=(26,0))
inact=p.action('start_input','mem_rd_start = 1\naddr = input_addr\nbytes = 11,520\nbeat ← 0',1220,1020,380,180)
p.edge('cfg_input',cfg,inact,'T',ports=(1,.5,0,.5),offset=(0,-24))
inlink=p.link('to_inrd','IN_RD',1640,1055)
p.edge('t06',inact,inlink,ports=(1,.5,0,.5))
nocfg=p.action('no_cfg','err_code ← 2\nNO_CFG',800,1300,370,120)
p.edge('cfg_error',cfg,nocfg,'F',offset=(25,0))
noend=p.link('no_cfg_finish','FINISH',929,1510)
p.edge('t04',nocfg,noend)

fin=p.state('FINISH',1840,265,410,115,'status_busy = 1\n1 cycle 고정')
finend=p.link('to_idle','IDLE',1989,550)
p.edge('t18',fin,finend,'무조건',offset=(62,0))
p.note('finish_note','FINISH를 떠나는 에지에 결과 기록\n(아래 독립 갱신 표)',1790,755,510,100)
err=p.state('ERR_DRAIN',2440,265,470,215,'status_busy = 1\nmem_rd_ready = 1\n수신 데이터 폐기\n소비 블록 구동 중지 [D08]',pending=True)
drain=p.diamond('drain_q','!mem_rd_busy\n&& !mem_wr_busy?',2530,610,290,145,True)
p.edge('drain_check',err,drain,pending=True)
p.edge('drain_wait',drain,err,'F',[(2970,683),(2970,372)],(1,.5,1,.5),True,offset=(22,0))
drainend=p.link('drain_finish','FINISH',2619,900,True)
p.edge('t17',drain,drainend,'T',pending=True,offset=(28,0))

# A visibly separate register-update table. The values are sticky, not Moore pulses.
p.note('status_table',
 'status_done / status_error 갱신 — 상태 흐름과 독립\n\n'
 'reg_start 수락 edge   : done ← 0, error ← 0                         [D02 R1]\n\n'
 'reg_clear_status         : done ← 0, error ← 0                         [D02 R3]\n'
 '                                  실행과 내부 err_code는 불변\n\n'
 'FINISH를 떠나는 edge : err_code == 0 → done ← 1, error ← 0\n'
 '                                  그 외 → done ← 0, error ← err_code [D02 R2]\n\n'
 '같은 edge 경합          : 기록 > 해제                                     [D02 R4]\n'
 '이벤트가 없으면         : 이전 done / error 유지 (sticky)\n\n'
 'R1 해제와 R2 기록은 서로 다른 edge에서 수행된다.\n'
 '따라서 새 결과가 START의 해제에 덮이지 않는다 (D02 R2 구조적 보장).',
 1780,1125,1170,620)
p.text('asm_legend','직사각형: 상태 동안 유지되는 레벨·등식   /   마름모: 판정   /   둥근 박스: 전이 시 펄스·적재\n작은 원: 다른 상태로 이어지는 연결자(추가 상태 아님). 각 판정의 F 대기 경로는 상태로 복귀한다.',70,1805,2850,70,20)


# Common memory-read ASM pattern for LOAD and input/FC1.
def read_branch(p,name,x,y,body,normal_cond,action_text,next_state,tid,errtid,sw=510,sh=230,normal_y=None):
    st=p.state(name,x,y,sw,sh,body)
    mid=x+sw/2
    ey=y+sh+90
    dq=p.diamond(name+'_errq','mem_rd_err?',mid-120,ey,240,120,True)
    p.edge(name+'_to_errq',st,dq)
    ea=p.action(name+'_erract','err_code ← 4\nMEM_RD_ERR\n[D08]',x+sw+55,ey-15,205,150,True)
    p.edge(name+'_err_true',dq,ea,'T',ports=(1,.5,0,.5),pending=True,offset=(0,-20))
    el=p.link(name+'_errlink','ERR_DRAIN',x+sw+101,ey+200,True)
    p.edge(errtid,ea,el,pending=True)
    ny=normal_y if normal_y is not None else ey+310
    nq=p.diamond(name+'_doneq',normal_cond,mid-150,ny,300,140)
    p.edge(name+'_err_false',dq,nq,'F',offset=(24,0))
    p.edge(name+'_wait',nq,st,'F',[(x-60,ny+70),(x-60,y+sh/2)],(0,.5,0,.5),offset=(-20,0))
    if action_text:
        act=p.action(name+'_nextact',action_text,x-5,ny+250,sw+10,165)
        p.edge(name+'_done_true',nq,act,'T',offset=(25,0))
        end=p.link(name+'_nextlink',next_state,mid-56,ny+505)
        p.edge(tid,act,end)
    else:
        end=p.link(name+'_nextlink',next_state,mid-56,ny+250)
        p.edge(tid,nq,end,'T',offset=(25,0))
    return st

p=Page('load','ASM - LOAD',2720,1660)
loadbody='status_busy = 1\nld_valid = mem_rd_valid\nmem_rd_ready = ld_ready\nld_data = mem_rd_data'
read_branch(p,'LD_RD1',140,245,loadbody,'mem_rd_busy\n1→0?',
 'mem_rd_start = 1\naddr = load_base + 399,152\nbytes = 23,840','LD_RD2','t07','t16a',sh=210)
read_branch(p,'LD_RD2',1030,245,loadbody,'mem_rd_busy\n1→0?',None,'LD_WAIT','t08','t16b',sh=210)
wait=p.state('LD_WAIT',1920,245,500,120,'status_busy = 1')
done=p.diamond('loader_done_q','loader_done?',2040,550,260,120)
p.edge('wait_done',wait,done)
p.edge('loader_wait',done,wait,'F',[(2580,610),(2580,305)],(1,.5,1,.5),offset=(20,0))
er=p.diamond('loader_err_q','loader_err?',2040,830,260,120)
p.edge('loader_complete',done,er,'T',offset=(25,0))
eact=p.action('blob_err','err_code ← 3\nBLOB_ERR',1820,1090,300,115)
p.edge('loader_bad',er,eact,'T',[(1970,1000)],(0,.5,.5,0),offset=(-28,0))
end=p.link('loader_finish','FINISH',2114,1350)
p.edge('loader_err_finish',eact,end,points=[(1970,1290)],ports=(.5,1,0,.5))
p.edge('t09',er,end,'F',[(2350,1020),(2350,1406)],(1,.5,1,.5),offset=(25,0))
p.text('pulse_note','진입 read 발행: DECODE → LD_RD1의 조건 출력 박스(공통 페이지).\nld_valid/ld_data와 mem_rd_ready는 상태 동안 연결되는 등식이며, 다음 상태 진입 펄스와 구분한다.',70,1550,2560,65,20)


p=Page('infer','ASM - INFER',3100,2890)
ins=p.state('IN_RD',130,245,510,245,'status_busy = 1\nmem_rd_ready = 1\nin_we = mem_rd_valid\nin_waddr = beat\nin_wdata = mem_rd_data')
ie=p.diamond('in_errq','mem_rd_err?',265,580,240,120,True)
p.edge('in_error_check',ins,ie)
iea=p.action('in_err4','err_code ← 4\nMEM_RD_ERR [D08]',710,570,285,120,True)
p.edge('in_error_true',ie,iea,'T',ports=(1,.5,0,.5),pending=True,offset=(0,-20))
iel=p.link('in_drain','ERR_DRAIN',797,770,True)
p.edge('t16c',iea,iel,pending=True)
iv=p.diamond('in_valid_q','mem_rd_valid?',265,850,240,120)
p.edge('in_error_false',ie,iv,'F',offset=(25,0))
ii=p.action('in_beat_inc','beat ← beat + 1',690,980,320,100)
p.edge('in_beat_accepted',iv,ii,'T',[(600,910),(600,1030)],(1,.5,0,.5),offset=(0,-20))
idone=p.diamond('in_done_q','mem_rd_busy\n1→0?',235,1110,300,140)
p.edge('in_no_beat',iv,idone,'F',offset=(-25,0))
p.edge('in_after_beat',ii,idone,points=[(850,1180)],ports=(.5,1,1,.5))
p.edge('in_wait',idone,ins,'F',[(70,1180),(70,367)],(0,.5,0,.5),offset=(-20,0))
ienc=p.action('in_enc_start','enc_start = 1',185,1330,400,105)
p.edge('in_complete',idone,ienc,'T',offset=(25,0))
iencl=p.link('in_to_enc','ENC',329,1510)
p.edge('t10',ienc,iencl)

enc=p.state('ENC',1150,245,500,120,'status_busy = 1')
ed=p.diamond('enc_done_q','enc_done?',1280,555,240,120)
p.edge('enc_check',enc,ed)
p.edge('enc_wait',ed,enc,'F',[(1090,615),(1090,305)],(0,.5,0,.5),offset=(-22,0))
ef=p.action('enc_to_fc1','fc_start = 1 (fc_sel = 0)\nmem_rd_start = 1\naddr = load_base_reg + 5,936\nbytes = 393,216',1100,845,600,190)
p.edge('enc_complete',ed,ef,'T',offset=(24,0))
fc1link=p.link('to_fc1','FC1',1344,1170)
p.edge('t11',ef,fc1link)
p.note('d06','D06 확정 (2026-09-25) — FC1 read base\nload_base_reg 는 DECODE→LD_RD1 에서 적재한\nLOAD 당시 weight_addr 이다. 현재 reg_weight_addr 을\n쓰지 않는다. 공통 문서 5.3절',1080,1375,640,170)

read_branch(p,'FC1',2190,245,'status_busy = 1\nfifo_we = mem_rd_valid && !fifo_full\nmem_rd_ready = !fifo_full\nfifo_wdata = mem_rd_data',
 'fc_done &&\n!mem_rd_busy?','fc_start = 1 (fc_sel = 1)','FC2','t12','t16d',sw=555,sh=245)

# Lower row: FC2, FC3 and WR.
def fc_stage(name,x,nextname,act,tid):
    state=p.state(name,x,1710,510,140,'status_busy = 1')
    decision=p.diamond(name+'_doneq','fc_done?',x+135,2040,240,120)
    p.edge(name+'_check',state,decision)
    p.edge(name+'_wait',decision,state,'F',[(x-60,2100),(x-60,1780)],(0,.5,0,.5),offset=(-20,0))
    action=p.action(name+'_action',act,x-5,2350,520,170)
    p.edge(name+'_complete',decision,action,'T',offset=(25,0))
    end=p.link(name+'_next',nextname,x+199,2630)
    p.edge(tid,action,end)
fc_stage('FC2',130,'FC3','fc_start = 1 (fc_sel = 2)','t13')
fc_stage('FC3',1150,'WR','mem_wr_start = 1\naddr = output_addr\nbytes = 24\nbeat ← 0','t14')
wr=p.state('WR',2175,1690,585,165,'status_busy = 1\nmem_wr_data = pose_data[64*beat +: 64]')
wready=p.diamond('wr_ready_q','mem_wr_ready?',2230,1945,255,120)
p.edge('wr_beat_check',wr,wready)
inc=p.action('wr_beat_inc','beat ← beat + 1',2710,1942,310,110)
p.edge('wr_advance',wready,inc,'T',ports=(1,.5,0,.5),offset=(0,-20))
wdone=p.diamond('wr_done_q','mem_wr_busy\n1→0?',2230,2190,255,125)
p.edge('wr_no_advance',wready,wdone,'F',offset=(-28,0))
p.edge('wr_after_advance',inc,wdone,points=[(2865,2252)],ports=(.5,1,1,.5))
p.edge('wr_wait',wdone,wr,'F',[(2090,2252),(2090,1772)],(0,.5,0,.5),offset=(-22,0))
we=p.diamond('wr_err_q','mem_wr_err?',2230,2410,255,120)
p.edge('wr_complete',wdone,we,'T',offset=(-27,0))
wa=p.action('wr_err5','err_code ← 5\nMEM_WR_ERR',2710,2410,310,115)
p.edge('wr_bad',we,wa,'T',ports=(1,.5,0,.5),offset=(0,-22))
wend=p.link('wr_finish','FINISH',2301,2670)
p.edge('t15',we,wend,'F',offset=(-25,0))
p.edge('wr_err_finish',wa,wend,points=[(2865,2726)],ports=(.5,1,1,.5))
p.text('infer_footer','작은 원은 다음 상태 연결자. ERR_DRAIN 진입은 IN_RD / FC1에서만 표시.\nWR 오류는 마지막 write 완료 후 FINISH로 직행하며, ENC / FC2 / FC3에는 오류 출처가 없다.\nfc_sel은 fc_start 샘플링 시점에 올바른 값이어야 한다 (08_FC r12·r45). 이후 값 유지도 허용하며, 도면에는 시작 전이의 값으로 표기한다.',70,2800,2950,90,20)

# ElementTree escapes &, <, > and quotes; replace newline references only for
# the requested readable XML spelling (no compressed diagram content).
E.indent(doc, space='  ')
xml=E.tostring(doc,encoding='unicode',xml_declaration=False).replace('&#10;', '&#10;')
OUT.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+xml+'\n',encoding='utf-8')
print('CREATED',OUT)
for d in doc.findall('diagram'):
    cells=d.findall('./mxGraphModel/root/mxCell')
    print(d.get('name'), 'states=',sum('_state_' in c.get('id','') for c in cells),
          'edge_segments=',sum(c.get('edge')=='1' for c in cells))
