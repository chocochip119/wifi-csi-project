#!/usr/bin/env python3
"""실제 Backend /health + /api/snapshot 검증/JSONL 녹화.
표준 라이브러리만 사용. PS 서버 5000/5001에 직접 연결하지 않아
Backend 단일 TCP 클라이언트 연결을 방해하지 않는다.
"""
import argparse
import json
import math
from pathlib import Path
import sys
import time
from urllib.error import URLError, HTTPError
from urllib.request import urlopen

IDS = {11,12,13,14,15,16,23,24,25,26,27,28}

def get_json(base, path):
    with urlopen(f'{base}{path}', timeout=3) as response:
        return json.load(response)

def valid_pose(pose):
    if not isinstance(pose, dict) or not pose.get('valid'):
        return False
    joints = pose.get('joints')
    if not isinstance(joints, list) or len(joints) != 12:
        return False
    try:
        return {int(j['id']) for j in joints} == IDS and all(
            math.isfinite(float(j['x'])) and math.isfinite(float(j['y']))
            for j in joints)
    except (TypeError, ValueError, KeyError):
        return False

def main():
    ap = argparse.ArgumentParser(description='WiSensing 실장비 Backend/Pose/Location 확인')
    ap.add_argument('--url', default='http://127.0.0.1:8000')
    ap.add_argument('--seconds', type=float, default=30)
    ap.add_argument('--interval', type=float, default=0.5)
    ap.add_argument('--record', type=Path, help='O 키에서 열 수 있는 snapshot JSONL 저장 경로')
    ap.add_argument('--require-pose', action='store_true', help='유효한 실제 Pose 최소 1개 필요')
    ap.add_argument('--require-location', action='store_true', help='유효한 위치 결과 최소 1개 필요')
    ap.add_argument('--allow-fake', action='store_true', help='Fake 파이프라인 테스트를 명시적으로 허용')
    args = ap.parse_args()
    if args.seconds <= 0 or args.interval <= 0:
        ap.error('seconds/interval 값은 양수여야 합니다')
    base = args.url.rstrip('/')
    try:
        health = get_json(base, '/health')
    except (URLError, HTTPError, ValueError, TimeoutError) as exc:
        print(f'[FAIL] Backend HTTP 연결 실패: {exc}', file=sys.stderr)
        return 2
    print('[BACKEND]', json.dumps(health, ensure_ascii=False))
    if not health.get('ok'):
        print('[FAIL] HTTP Backend 자체가 준비되지 않았습니다.')
        return 2
    if health.get('fake') and not args.allow_fake:
        print('[FAIL] --fake 실행 중입니다. 실제 보드 시험으로 기록하지 않습니다.')
        return 2
    fh = None
    if args.record:
        args.record.parent.mkdir(parents=True, exist_ok=True)
        fh = args.record.open('w', encoding='utf-8')
        print(f'[RECORD] {args.record} (JSONL; 1행=1 snapshot)')
    seen = set()
    valid_pose_frames = 0
    valid_location_frames = 0
    pose_windows = set()
    connected_csi = connected_pose = False
    last_display_at = 0
    start = time.monotonic()
    try:
        while time.monotonic() - start < args.seconds:
            try:
                snap = get_json(base, '/api/snapshot')
            except (URLError, HTTPError, ValueError, TimeoutError) as exc:
                print(f'[WARN] snapshot 연결 실패: {exc}')
                time.sleep(args.interval)
                continue
            seq = snap.get('seq')
            if seq in seen:
                time.sleep(args.interval)
                continue
            seen.add(seq)
            if fh:
                fh.write(json.dumps(snap, ensure_ascii=False) + '\n')
                fh.flush()
            system = snap.get('system') or {}
            location = snap.get('location') or {}
            pose = snap.get('pose') or {}
            connected_csi |= bool(system.get('csi_connected'))
            connected_pose |= bool(system.get('pose_connected'))
            if location.get('valid'):
                valid_location_frames += 1
            if valid_pose(pose) and pose.get('coordinate_space') == 'model_output':
                valid_pose_frames += 1
                pose_windows.add(str(pose.get('window_id')))
            if time.monotonic() - last_display_at >= 2:
                last_display_at = time.monotonic()
                print(f"[SEQ {seq}] PS={bool(system.get('ps_connected'))} CSI={bool(system.get('csi_connected'))} "
                      f"POSE_TCP={bool(system.get('pose_connected'))} READY={bool(system.get('status_ready'))} "
                      f"RX={system.get('rx_active')}/{system.get('rx_total')} CONFIRMED={bool(system.get('identity_confirmed'))} "
                      f"INFER={bool(system.get('inference_running'))} "
                      f"LOC={location.get('point_id') if location.get('valid') else 'Unavailable'} "
                      f"POSE_VALID={valid_pose(pose)} AGE_MS={pose.get('age_ms')} "
                      f"SPACE={pose.get('coordinate_space')} REASON={system.get('reason')}")
                nodes = system.get('rx_nodes') or []
                if nodes:
                    print(' RX:', ' | '.join(
                        f"{n.get('rx_id')}:{n.get('mac')} "
                        f"({'LIVE' if n.get('live') else 'OFF'},{'SAVED' if n.get('saved') else 'UNSAVED'})"
                        for n in nodes))
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print('\n[STOP] 사용자 중단')
    finally:
        if fh: fh.close()
    print(f'\n[SUMMARY] Snapshots={len(seen)}, CSI_connected_seen={connected_csi}, '
          f'Pose_TCP_connected_seen={connected_pose}, valid_pose_snapshots={valid_pose_frames}, '
          f'unique_pose_windows={len(pose_windows)}, valid_location_snapshots={valid_location_frames}')
    if args.record: print('[RECORD DONE]', args.record)
    failures = []
    if not connected_csi: failures.append('CSI 5000 연결 확인 실패')
    if not connected_pose: failures.append('Pose 5001 연결 확인 실패')
    if args.require_pose and valid_pose_frames == 0: failures.append('실제 12관절 Pose 미수신')
    if args.require_location and valid_location_frames == 0: failures.append('위치 추론 결과 미수신 (RX 배치/STATUS/CSI 확인)')
    if failures:
        for fail in failures: print('[FAIL]', fail)
        return 3
    print('[PASS] 관찰한 조건 충족. 이 결과는 모델 정확도/FPGA BIT-EXACT 보증이 아닙니다.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
