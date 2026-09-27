from pathlib import Path
from collections import defaultdict,Counter
import json,re,shutil

r=Path(r'D:\2609_final_project');w=Path(__file__).parent;docs=r/'cnn_rtl/docs';runs=docs/'E-02a_runs'
rows=json.loads((w/'summary.json').read_text());by={v['tag']:v for v in rows}
basetags=['encoder_default_10.000','encoder_performance_10.000','fc_default_10.000','fc_performance_10.000']
freq=[v for v in rows if v['tag'].startswith('encoder_freq') and v['measurement_valid']]
assert freq,'Need an E4 completed route before the final report'
assert len(freq)<=3
passed=[v for v in freq if v['stages']['post_route']['WNS']>=0 and v['stages']['post_route']['WHS']>=0]
best=min(passed,key=lambda v:v['period_ns']) if passed else None
fmt=lambda n:f'{n:+.3f}'
labels={'encoder':'CNN_Encoder','fc':'FC MAC + FC requant','core':'pose_cnn + fc_stub'}

def stage_line(v):
 vals=[fmt(v['stages'][s]['WNS']) for s in ['post_synth','post_place','post_phys_opt','post_route']]
 return '| '+ ' | '.join([labels[v['block']],v['mode'],f"{v['period_ns']:.3f}"]+vals+[str(v['stages']['post_route']['failing_setup_endpoints']),f"{v['seconds']:.3f}"])+ ' |'

stage_table='\n'.join(stage_line(by[t]) for t in basetags)+'\n'+'\n'.join(stage_line(v) for v in freq)
estimate_rows=[]
for t in basetags:
 v=by[t];mhz=v['fmax_estimate_mhz'];p=v['period_estimate_ns']
 estimate_rows.append(f"| {labels[v['block']]} / {v['mode']} | {v['stages']['post_route']['WNS']:+.3f} | {p:.3f} | {mhz:.3f} |")

groups={}
for t in ['encoder_default_10.000','encoder_performance_10.000']:
 g=defaultdict(list)
 for line in (runs/t/'failing_paths.tsv').read_text().splitlines():
  s,a,b=line.split('\t');key=next((k for k in ['u_enc_rq','u_conv_mac','u_pool'] if k in b),b.split('/')[0])
  g[key].append((float(s),a,b))
 groups[t]={k:{'count':len(v),'worst':min(v)} for k,v in g.items()}
group_table='\n'.join(f"| {t.split('_')[1]} | {k} | {v['count']} | {v['worst'][0]:+.3f} | `{v['worst'][1]}` → `{v['worst'][2]}` |" for t,g in groups.items() for k,v in sorted(g.items()))

path_table=[];quality=[];warnings={}
for t in basetags+[v['tag'] for v in freq]:
 v=by[t];p=v['stages']['post_route'];base=runs/t
 path_table.append(f"| {t} | `{p['start']}` → `{p['end']}` | {p['data_ns']:.3f} | {p['logic_ns']:.3f} | {p['route_ns']:.3f} | {p['levels']} / {p['primitives']} |")
 util=(base/'utilization.rpt').read_text()
 def amount(k):
  q=re.search(r'\|\s*'+re.escape(k)+r'\s*\|\s*([\d.]+)',util);return q[1] if q else '?'
 route=(base/'route_status.rpt').read_text()
 fully=re.search(r'fully routed nets\.+\s*:\s*(\d+)',route)[1]
 errors=re.search(r'nets with routing errors\.+\s*:\s*(\d+)',route)[1]
 check=(base/'check_timing.rpt').read_text();assert 'checking loops (0)' in check and 'checking unconstrained_internal_endpoints (0)' in check
 assert p['failing_hold_endpoints']==0 and errors=='0'
 drc=(base/'drc.rpt').read_text()
 violations=re.search(r'Violations found:\s*(\d+)',drc)[1]
 quality.append(f"| {t} | {amount('Slice LUTs')} | {amount('Slice Registers')} | {amount('Block RAM Tile')} | {amount('DSPs')} | {amount('Register as Latch')} / 0 | {p['WHS']:+.3f} | {fully} / {errors} | {violations} |")
 txt=(base/'full.log').read_text(encoding='utf-8',errors='replace')
 warnings[t]=dict(Counter(re.findall(r'^(?:CRITICAL )?WARNING: \[([^\]]+)\]',txt,re.M)))

run_lines=[]
for v in rows:
 if 'seconds' not in v:continue
 t=v['tag'];role=('유효 post-route' if v['measurement_valid'] else '합성 전 setup 오류' if t.startswith('setup_failure_') or t=='encoder_freq1_13.160' else 'E5 합성 실패')
 if t in ['encoder_default_10.000','fc_default_10.000']:role='P&R 완료, 후처리 오류; checkpoint 재확인'
 run_lines.append(f"| [{t}](E-02a_runs/{t}/full.log) | {v['exit']} | {v['seconds']:.3f} | {role} |")
 for name in ['inspection_initial','inspection']:
  p=runs/t/(name+'.json')
  if p.exists():
   q=json.loads(p.read_text());log='inspect_initial.log' if name.endswith('initial') else 'inspect.log'
   run_lines.append(f"| [{t} {name}](E-02a_runs/{t}/{log}) | {q['exit']} | {q['seconds']:.3f} | 기존 checkpoint 읽기, P&R 반복 아님 |")

audit=json.loads((docs/'E-02a_hash_audit.json').read_text())
assert not audit['changed'] and not audit['added'] and not audit['removed']
(docs/'E-02a_measurements.json').write_text(json.dumps({'runs':rows,'encoder_failure_groups':groups,'warnings_by_code':warnings},indent=2),encoding='utf-8')

if best:
 p=best['period_ns'];mhz=1000/p;ms=1338265*p/1e6
 e4result=f"확인 P&R {len(freq)}회 중 가장 빠른 통과점은 **{p:.3f} ns = {mhz:.3f} MHz**다. post-route WNS **{best['stages']['post_route']['WNS']:+.3f} ns**, WHS **{best['stages']['post_route']['WHS']:+.3f} ns**. 이는 측정한 Encoder OOC에서의 통과점이며, 절대 최대 주파수나 코어/보드 보증값이 아니다."
 notionclock=f"Encoder OOC 통과점 {mhz:.3f} MHz ({p:.3f} ns), 추론 시간 환산 {ms:.3f} ms."
else:
 e4result=f"확인 P&R {len(freq)}회 안에서 통과 주기를 얻지 못했다. 확인한 실패점만 범위 자료로 남기며 달성 가능한 최대 주파수를 확정하지 않는다."
 notionclock='제한된 주파수 확인 횟수 안에서 통과점을 확보하지 못함. D10 미확정.'
time_rows=['| 100.000 MHz (10.000 ns) | 13.382650 ms | 1.000× | 시간 계산 기준, 타이밍 미달 |']
for v in freq:
 p=v['period_ns'];post=v['stages']['post_route'];ok=post['WNS']>=0 and post['WHS']>=0
 time_rows.append(f"| {1000/p:.3f} MHz ({p:.3f} ns) | {1338265*p/1e6:.6f} ms | {p/10:.4f}× | Encoder OOC {'통과' if ok else '미달'}, WNS {post['WNS']:+.3f} ns |")

report=f'''# E-02a — requant post-route 타이밍 측정 기록

2026-09-26 / Vivado 2020.2 / xc7z020clg400-1. 측정 완료 범위는 아래 실행표를 따른다.

**측정한 OOC 제약과 기본·성능 directive에서는 100 MHz가 불가능하다. 근거는 post-route WNS가 Encoder −3.562/−3.160 ns, FC −2.413/−2.133 ns로 모두 음수라는 것이다.** 다른 제약·배치·최종 BD까지 수학적으로 불가능하다는 뜻은 아니다.

RTL 수정, TB 작성·수정, 시뮬레이션, pipeline/latency/DSP 속성 변경은 하지 않았다.
파이프라인 여부와 D10 클록은 **사용자·팀 결정 사항으로 남긴다**.

## 실행 전 명세 보정 및 이번에 확인한 차이

1. 같은 RTL도 통합 범위와 배치에 따라 최악 경로가 달라진다. Encoder와 FC를 각각 측정했다. logic 지연도 최적화·pin mapping에 따라 바뀌므로 “고정 5.885 ns”가 아니다.
2. `1000/(period-WNS)`는 현재 배선의 1차 추정이다. 변경 주기로 다시 P&R한 확인점과 구별한다. 전체 구성의 병목이 Encoder여서 E4 확인은 Encoder에 우선 배정했다. 최대 3회의 완료된 P&R을 한도로 했다.
3. E6는 RTL 연산자가 아닌 물리 핀 경계로 숫자를 뽑았다. half/라운딩이 오른쪽 shift 앞이며, 요청한 ㄱ과 ㄷ은 중첩된다. 레지스터 추가 효과는 기존 경로를 나눈 수치만 제시한다.
4. `fc_stub`는 task·문자열 오류 처리가 있는 TB 모형이므로 E5 합성 실패 가능성을 실행 전에 밝혔다. 실제로 그 부분에서 실패했고 수정하지 않았다.
5. **requant만이 유일한 실패 경로는 아니다.** 성능 실행의 Encoder 최악 경로는 Pool 입력이며, 내부 Conv MAC도 −2.824 ns다. requant 공통 산술을 고치면 두 블록의 해당 경로에 도움이 될 수 있지만, 한 번의 수정으로 Encoder 전체 100 MHz가 해결된다는 결론은 아니다.

## E1~E4 — 구성 × 시점 × WNS

WNS 단위 ns. 시간은 각 Vivado 프로세스 wall-clock 초다. E1/E2의 기본 실행은 P&R 후 보조 추출 오류 때문에 종료 코드 1이며, 저장 checkpoint를 열어 같은 WNS와 배선 완료를 재확인했다.

| 구성 | directive | 주기 ns | post-synth | post-place | post-phys_opt | post-route | route 실패 endpoint | wall s |
|---|---|---:|---:|---:|---:|---:|---:|---:|
{stage_table}

100 MHz post-synth **−3.641 / −3.494 ns를 정확히 재현**했다.
성능 directive의 route 개선은 Encoder **+0.402 ns**, FC **+0.280 ns**다.
더 많은 최적화가 항상 더 짧은 배선을 만들지는 않는다. 두 실행 모두 타이밍 미달이다.

성능 실행 명령은 `opt_design -directive Explore` → `place_design -directive ExtraTimingOpt` → `phys_opt_design -directive AggressiveExplore` → `route_design -directive Explore`다.
기본 실행은 같은 순서에서 directive를 생략했다. 모든 실행이 OOC synth부터 새로 시작했다.

## E1/E2 임계 경로 및 logic/route 분해

| 구성·실행 | post-route 시작 → 끝 | Data ns | Logic ns | Route ns | logic level / primitive 수 |
|---|---|---:|---:|---:|---|
{chr(10).join(path_table)}

기본 Encoder는 shift[5] 대신 **shift[4] (`param3[68]`)**가 최악이다. 기본 FC는 `param3[69] → rq[*]/R`를 유지했다.
성능 Encoder는 **Pool**이 최악이고, `param3[69] → rq[2]/R`로 제한해도 **−2.986 ns**다.
성능 FC는 Vivado 물리 최적화로 시작점이 `rq[7]_i_343_psdsp`(곱셈 결과 경로의 FF)로 바뀌었다.
그 경로도 requant의 가감·shift·포화로 이어진다. `param3[69]`와 그 복제본으로 시작점을 제한한 경로는 **−1.962 ns**다.
따라서 두 구성 모두 requant stage 3 문제는 남지만 “동일한 한 핀이 언제나 전체 최악”은 아니다.

경로 전문은 아래 파일에 생략 없이 보존했다. 각 파일은 `-max_paths 3 -nworst 1 -input_pins -delay_type max` 출력이다.

- [E1 Encoder 기본 전문](E-02a_runs/encoder_default_10.000/post_route_paths.rpt), [성능 전문](E-02a_runs/encoder_performance_10.000/post_route_paths.rpt), [성능 requant 지정 경로](E-02a_runs/encoder_performance_10.000/requant_paths.rpt)
- [E2 FC 기본 전문](E-02a_runs/fc_default_10.000/post_route_paths.rpt), [성능 전문](E-02a_runs/fc_performance_10.000/post_route_paths.rpt), [성능 shift[5] 지정 경로](E-02a_runs/fc_performance_10.000/requant_paths.rpt)

## requant 외 실패 경로

모든 음수 slack endpoint를 `get_timing_paths -slack_lesser_than 0 -max_paths 5000 -nworst 1`로 모았다.
endpoint는 핀 기준이며 한 FF의 D/R/S가 따로 셀 수 있다. 각 합계는 report_timing_summary와 같다.

| Encoder 실행 | 도착 블록 | 실패 endpoint 수 | 최악 ns | 해당 블록의 최악 시작 → 끝 |
|---|---|---:|---:|---|
{group_table}

Pool 시작점 `pool_shift`는 OOC 입력이므로 2 ns I/O delay와 미지정 port 위치의 영향을 받는다.
Conv MAC의 BRAM 출력→누산/결과 FF 경로는 내부 경로다. 단독 Conv_MAC 합성의 +1.093 ns를 Encoder 통합 배치의 보장값으로 쓰면 안 된다.

## E4 — Fmax 추정과 새 P&R 확인

계산식은 `Fmax_est_MHz = 1000 / (10 - WNS_ns)`다.

| 구성 / directive | route WNS ns | 추정 주기 ns | 추정 Fmax MHz |
|---|---:|---:|---:|
{chr(10).join(estimate_rows)}

두 구성 중 더 느린 Encoder의 더 나은 결과에서 **13.160 ns**를 첫 확인 주기로 선택했다.
그 결과 WNS −0.268 ns이므로 새 추정은 13.428 ns였다. 이를 올림한 **13.500 ns**를 두 번째 확인 주기로 사용했다.
두 번째 결과도 −0.052 ns여서 재추정은 13.552 ns였다. 마지막 세 번째는 배치 변동 여유를 두고 **14.000 ns**로 확인했다.
기존 `timing_100mhz.xdc`를 먼저 읽고 실행 폴더의 `clock_period_override.xdc`에서 `create_clock` 주기만 바꿨다.
기존 파일의 byte, I/O delay 2 ns, part, timing exception은 바꾸지 않았다. 각 `clocks.rpt`에 실제 적용 주기가 남아 있다.

{e4result}

cycle 수는 이번에 시뮬레이션한 값이 아니라 사용자 지정 기존 실측 **1,338,265 cycle**을 사용했다.
`시간(ms) = 1,338,265 × period(ns) / 10^6`이다. DDR stall이나 최종 실물 FC로 cycle 수가 달라지면 이 시간도 달라진다.

| 주파수·주기 | 1회 추론 시간 | 100 MHz 대비 시간 | 판정 |
|---|---:|---:|---|
{chr(10).join(time_rows)}

FC의 별도 Fmax는 위 100 MHz 배선 추정치이며, 이 Encoder 확인값을 FC 새 P&R 결과라고 표기하지 않는다.

## E5 — 전체 코어 참고 측정

`pose_cnn` + ctrl/Loader/Encoder + **변경하지 않은** `tb/fc_stub.v`를 실제로 한 번 합성했다.
**18.050초, exit 1**, `fc_stub.v:76`의 문자열 오류 처리에서 `Synth 8-281 expression must be of a packed type`, `Synth 8-6058`이 발생했다.
합성 실패이므로 전체 코어의 place/route/WNS는 **없다**. 모형을 합성용으로 고치거나 자동 치환하지 않았다.
[명령과 출력 전문](E-02a_runs/core_default_10.000/full.log).

E5로 전체 코어 배치의 악화를 판정할 수는 없다. 위의 Pool·Conv MAC 발견은 **Encoder 단독 안에서** 확인한 결과다.

## E6 — 구간별 누적 지연과 가상 경계

[구간별 지연·핀 경계·netlist 근거 전문](E-02a_구간별지연.md)에 수록했다.

| 기본 100 MHz 경로 | C→Q | half 준비 | 가감 carry | shift·부호 선택 | 포화·출력 선택 | 합계 |
|---|---:|---:|---:|---:|---:|---:|
| Encoder | 0.419 | 1.899 | 2.486 | **4.329** | 3.821 | 12.954 |
| FC | 0.518 | 1.869 | 2.328 | 3.234 | **3.856** | 11.805 |

가장 긴 구간 앞에서 기존 경로를 나누면 Encoder는 **4.804 / 8.150 ns**, FC는 **7.949 / 3.856 ns**다.
같은 산술 경계(가감 뒤)를 FC에 적용해 나눈 값은 **4.715 / 7.090 ns**다.
이는 새 FF/배선/setup을 넣지 않은 산술 분해이며, 실제 pipeline의 WNS 예측이나 구현 승인이 아니다.

## 자원·배선·hold·DRC

| 실행 | LUT | FF | BRAM tile | DSP | 래치 / 조합 루프 | WHS ns | fully routed nets / routing errors | DRC 건수 |
|---|---:|---:|---:|---:|---|---:|---|---:|
{chr(10).join(quality)}

모든 완료된 route에서 hold 실패 0, 내부 미제약 endpoint 0을 확인했다.
각 실행 폴더에 `utilization.rpt`, `route_status.rpt`, `check_timing.rpt`, `drc.rpt`를 보존했다.
DRC는 OOC 참고 자료로만 기록했다. 클록/포트 배치까지 검증된 전체 IP의 DRC 통과라는 의미가 아니다.
경고 코드별 건수는 [측정 JSON](E-02a_measurements.json)에 있고 원문은 각 full.log에 있다.

## OOC 한계

**내부 데이터 net은 배선됐지만, 이 제약에는 HD.CLK_SRC와 HD.PARTPIN_LOCS가 없다.**
`Timing 38-242`, `Route 35-198` 경고가 발생했고 clock 및 일부 입력 net은 timing report에서 `unset`이다.
따라서 clock insertion/skew와 외부 포트 경로는 실제 BD/보드 배선 값이 아니다.
특히 성능 Encoder의 최악 Pool 입력 경로와 이 경로로 계산한 Fmax는 그 한계를 직접 받는다.
기존 제약을 바꾸지 말라는 범위를 지켜 클록 위치, false path, multicycle 예외를 추가하지 않았다.
E-02a는 지정된 OOC 조건에서 합성 추정이 배선 후에도 남는지에 답한다. 전체 코어/BD의 실제 보드 최대 주파수 확정은 별도다.

## 실행 종료 코드와 로그

각 full.log 첫머리에 CWD와 **실제 Vivado 명령 전체**, 끝에 exit code와 wall-clock이 있다.
실패 시도도 삭제하거나 exit 0으로 바꿔 기록하지 않았다.

| 실행·전문 링크 | exit | wall s | 해석 |
|---|---:|---:|---|
{chr(10).join(run_lines)}

초기 setup 실패 두 건은 Windows 역슬래시 출력 경로 정규화 문제로 합성 전에 종료됐다.
기본 두 건은 P&R 후 Vivado 2020.2에 없는 `TIMING_POINTS` 속성을 읽다가 종료됐다.
저장된 routed.dcp를 별도 프로세스에서 열어 동일 WNS/배선 오류 0을 확인했으므로 그 post-route 측정은 유효하다.
첫 E4 setup도 design이 열리기 전 `get_ports`를 호출해 종료됐고, XDC 지연 로딩 방식으로 고쳐 새 tag에서 실행했다.
합성 전 실패는 E4의 완료된 P&R {len(freq)}회에 포함하지 않는다. 실제 흐름은 새 [impl_check.tcl](../syn/impl_check.tcl)에 있다.

## 변경 범위와 SHA-256

추가·변경: `syn/impl_check.tcl`, `syn/README.md` 결과 행, `docs/E-02a_*` 측정·로그·보조 자료.
**394개 보호 파일에서 변경/추가/삭제 모두 0**. 파일 집합까지 비교했다.

| 보호 범위 | 파일 수 | 결과 |
|---|---:|---|
| rtl 전체 | 21 | SHA-256 무변경 |
| tb 전체 | 30 | SHA-256 무변경 |
| golden 전체 | 28 | SHA-256 무변경 |
| others 원본 | 14 | SHA-256 무변경 |
| wifi-csi-pose-main | 299 | SHA-256 무변경 |
| 기존 syn_check.tcl / timing_100mhz.xdc | 2 | SHA-256 무변경 |

- syn_check.tcl: `{audit['original_syn_check_sha256']}`
- timing_100mhz.xdc: `{audit['original_timing_xdc_sha256']}`
- 재사용 F-03a fixture: `{audit['fixture_sha256']}`
- [파일별 before/after 전체 해시](E-02a_hash_audit.json), [실행 보조 자료](E-02a_validation_support/README.md)

## Notion 복사용

E-02a에서 RTL/TB 변경 없이 Vivado 2020.2, xc7z020clg400-1 OOC P&R을 측정했다.
100 MHz post-route WNS는 Encoder 기본 −3.562 / 성능 −3.160 ns, FC 기본 −2.413 / 성능 −2.133 ns로 모두 미달했다.
requant 경로는 여전히 미달하며, 성능 Encoder에서 Pool −3.160 ns와 Conv MAC −2.824 ns도 확인했다.
requant만 수정하면 전체가 해결된다고 확정할 수 없다.
{notionclock}
이 값은 OOC 데이터 배선 기준이며 실제 클록/BD/코어 전체 Fmax를 보장하지 않는다.
pose_cnn + FC stub 참고 실행은 stub 문자열 검사 코드의 합성 실패로 중단했다.
보호 394개 파일과 기존 Tcl/XDC의 SHA-256은 모두 그대로다. 시뮬레이션은 실행하지 않았다.
파이프라인 재설계와 D10 클록 선택은 사용자·팀 판단으로 남겨 두었다.
'''
(docs/'E-02a_측정기록.md').write_text(report,encoding='utf-8')
shutil.copy2(w/'make_report.py',docs/'E-02a_validation_support/make_report.py')
print('REPORT_WRITTEN',len(report),'chars; E4 routed confirmations',len(freq),'best=',best['tag'] if best else None)
