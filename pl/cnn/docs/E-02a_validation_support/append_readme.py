from pathlib import Path
import json,re,shutil
r=Path(r'D:\2609_final_project');docs=r/'cnn_rtl/docs';w=Path(__file__).parent
rows=json.loads((docs/'E-02a_measurements.json').read_text())['runs'];by={v['tag']:v for v in rows}
tags=['encoder_default_10.000','encoder_performance_10.000','fc_default_10.000','fc_performance_10.000']
tags += [v['tag'] for v in rows if v['tag'].startswith('encoder_freq') and v['measurement_valid']]
table=[]
for tag in tags:
 v=by[tag];p=v['stages']['post_route'];s=(docs/'E-02a_runs'/tag/'utilization.rpt').read_text()
 def n(k):return re.search(r'\|\s*'+re.escape(k)+r'\s*\|\s*([\d.]+)',s)[1]
 table.append(f"| {'Encoder' if v['block']=='encoder' else 'FC MAC+RQ'} | {v['period_ns']:.3f} | {v['mode']} | {n('Slice LUTs')} | {n('Slice Registers')} | {n('Block RAM Tile')} | {n('DSPs')} | {p['WNS']:+.3f} ns | {p['failing_setup_endpoints']} |")
best=[by[t] for t in tags if by[t]['period_ns']!=10 and by[t]['stages']['post_route']['WNS']>=0 and by[t]['stages']['post_route']['WHS']>=0]
if best:
 b=min(best,key=lambda v:v['period_ns']);period=b['period_ns']
 found=f"Encoder OOC 확인 통과점은 {period:.3f} ns / {1000/period:.3f} MHz다. 기존 1,338,265 cycle 환산 {1338265*period/1e6:.6f} ms. 절대 Fmax나 최종 BD 보장값이 아니다."
else:found='3회 이내 주파수 확인에서 통과점을 확보하지 못했다. 상세 실패점은 보고서에 기록했다.'
marker='## 2026-09-26 E-02a requant P&R 측정'
text=f'''\n\n{marker}

RTL/TB 무변경. xc7z020clg400-1, Vivado 2020.2. 기존 timing_100mhz.xdc의
I/O delay 2 ns를 유지하고 새 impl_check.tcl로 OOC synth → opt → place → phys_opt → route 실행.
아래는 **post-route** 결과다. 기존 합성 추정값과 구분한다.

| 대상 | 주기 ns | directive | LUT | FF | BRAM tile | DSP | WNS | 실패 setup endpoint |
|---|---:|---|---:|---:|---:|---:|---:|---:|
{chr(10).join(table)}

100 MHz는 기본/성능 두 directive 모두 미달했다. 성능 실행에서도 Encoder requant
−2.986 ns, Conv MAC −2.824 ns, Pool −3.160 ns가 남아 requant 단독 문제로 볼 수 없다.
{found}
74.074 MHz 확인은 −0.052 ns로 실패했다. pipeline 여부와 D10 결정은 보류한다.

모든 완료 route: 래치 0 / 조합 루프 0 / hold 실패 0 / routing errors 0.
HD.CLK_SRC·HD.PARTPIN_LOCS 미지정으로 OOC clock/port 지연 일부는 추정이다.
특히 Pool 입력 경로와 그 경로로 계산한 Fmax는 이 한계를 받는다.
pose_cnn + 변경하지 않은 fc_stub 참고 실행은 fc_stub.v:76 합성 오류로 중단했다.
기본 10 ns 두 실행은 P&R 완료 후 보조 속성 조회 오류로 exit 1이었고,
저장 checkpoint를 다시 열어 동일 WNS·배선 완료를 검증했다. 원래 로그/종료 코드는 보존했다.

RTL 21 / TB 30 / golden 28 / others 14 / 참고 원본 299 / 기존 Tcl·XDC 2:
총 **394 파일 SHA-256 및 파일 목록 무변경**. 시뮬레이션 실행 없음.

[E-02a 측정 기록·모든 실행 로그](../docs/E-02a_측정기록.md) ·
[구간별 지연](../docs/E-02a_구간별지연.md) ·
[파일별 해시](../docs/E-02a_hash_audit.json)
'''
p=r/'cnn_rtl/syn/README.md';assert marker not in p.read_text(encoding='utf-8'),'Already appended'
with p.open('ab') as f:f.write(text.encode('utf-8'))
shutil.copy2(w/'append_readme.py',docs/'E-02a_validation_support/append_readme.py')
print('README_APPENDED',len(tags),'post-route rows')
