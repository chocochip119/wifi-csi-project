"""Editable recording manifest, strict split checks, shared offline/live features.

Original CSVs are opened for reading only. Generic collector names do not encode
a location/person: those fields remain blank until the operator labels them.
"""
from __future__ import annotations

from collections import Counter
import hashlib
import math
import os
from pathlib import Path
import re

import numpy as np
import pandas as pd

from location_core import cycle_from_rows, make_windows, validate_config
from labels import CLASSES as ALL_CLASSES, EMPTY_LABEL, EMPTY_PERSON, POINTS_CM

CLASSES = list(ALL_CLASSES)
SPLITS = ('train','validation','test')
MANIFEST_COLUMNS = ['path','point_id','person','session','repeat','split','enabled','sha256','note']
_CANONICAL = re.compile(r'(?P<date>\d{8})_l(?P<layout>\d{2})_(?P<block>b\d{2})_'
                        r'(?P<person>s\d{2}|none)_(?P<repeat>r\d{2})_(?P<point>p\d{2}|empty)'
                        r'(?:_take\d{2})?(?:_\d{8}_\d{6}(?:_\d{2})?(?:_\d{3})?)?$',re.I)
# person: Korean name (2-5 Hangul) as collected, or a one-letter pseudonym (A..Z) for shared examples.
_KOREAN = re.compile(r'(?P<session>\d{4}_\d{1,2}시(?:반)?)_(?P<point>p0[1-9]|p10)(?P<person>[가-힣]{2,5}|[A-Z])(?P<repeat>[1-9]\d*)$',re.I)
_EMPTY_CANONICAL = re.compile(r'(?P<date>\d{8})_l(?P<layout>\d{2})_(?P<block>b\d{2})_'
                              r'(?P<repeat>r\d{2})_empty'
                              r'(?:_take\d{2})?(?:_\d{8}_\d{6}(?:_\d{2})?(?:_\d{3})?)?$',re.I)
_EMPTY_KOREAN = re.compile(r'(?P<session>\d{4}(?:\d{4})?_\d{1,2}시(?:반)?)_'
                           r'(?:empty|사람없음|빈공간)_?(?:r)?(?P<repeat>[1-9]\d*|0[1-9])$',re.I)


def _require(condition,message):
    if not condition: raise ValueError(message)


def file_sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def _enabled(value):
    if isinstance(value,(bool,np.bool_)): return bool(value)
    value=str(value).strip().lower()
    if value in {'1','true','yes','y'}: return True
    if value in {'0','false','no','n',''}: return False
    raise ValueError(f'enabled는 true/false여야 합니다: {value}')


def read_manifest(path):
    path=Path(path).resolve()
    frame=pd.read_csv(path,dtype=str,keep_default_na=False,encoding='utf-8-sig')
    frame.attrs['manifest_dir']=str(path.parent)
    frame.attrs['manifest_path']=str(path)
    return frame


def _manifest_path(path,base):
    """Use relative paths on one drive; Windows cross-drive sources stay absolute."""
    path=Path(path).resolve()
    try: return os.path.relpath(path,base)
    except ValueError: return str(path)


def save_manifest(frame,path,*,overwrite=False):
    """Save an explicitly edited manifest, preserving its relative path meaning."""
    path=Path(path).resolve()
    if path.exists() and not overwrite: raise FileExistsError(f'기존 manifest 보존: {path}')
    base=Path(frame.attrs.get('manifest_dir',Path.cwd()))
    result=frame.copy()
    result['path']=[_manifest_path(base/str(p),path.parent) for p in result['path']]
    path.parent.mkdir(parents=True,exist_ok=True)
    result.to_csv(path,index=False,encoding='utf-8-sig')
    result.attrs.update(manifest_dir=str(path.parent),manifest_path=str(path))
    return result


def create_manifest(data_root,out_csv):
    """Inventory a dedicated data folder; do not infer labels from order or folders.

    Explicit point/empty filename conventions are recognized. Collector timestamps alone
    do not identify position or person. Unknown files start disabled for review.
    sha256 is informational; training independently recalculates each file hash.
    """
    data_root,out_csv=Path(data_root).resolve(),Path(out_csv).resolve()
    _require(data_root.is_dir(),f'원본 폴더 없음: {data_root}')
    if out_csv.exists(): raise FileExistsError(f'기존 manifest 보존: {out_csv}')
    rows=[]
    for path in sorted(data_root.rglob('*.csv')):
        if path.resolve()==out_csv: continue
        row=dict.fromkeys(MANIFEST_COLUMNS,'')
        row.update(path=_manifest_path(path,out_csv.parent),enabled=False,sha256=file_sha256(path))
        match=_CANONICAL.fullmatch(path.stem)
        if match and match['point'].lower() in CLASSES:
            row.update(point_id=match['point'].lower(),person=match['person'].lower(),
                       session=f"{match['date']}_l{match['layout']}_{match['block'].lower()}",
                       repeat=match['repeat'].lower(),note='파일명 해석됨: 배치/사람/지점 확인 후 enabled=true 및 split 지정')
        else:
            empty_match=_EMPTY_CANONICAL.fullmatch(path.stem)
            short_empty=_EMPTY_KOREAN.fullmatch(path.stem)
            match=_KOREAN.fullmatch(path.stem)
            if empty_match:
                row.update(point_id=EMPTY_LABEL,person=EMPTY_PERSON,
                           session=f"{empty_match['date']}_l{empty_match['layout']}_{empty_match['block'].lower()}",
                           repeat=empty_match['repeat'].lower(),note='empty 파일명 해석됨: 영역 내 사람이 없었는지 확인 후 활성화')
            elif short_empty:
                row.update(point_id=EMPTY_LABEL,person=EMPTY_PERSON,
                           session=f'{path.parent.name}/{short_empty["session"]}',repeat=f'r{int(short_empty["repeat"]):02d}',
                           note='empty 파일명 해석됨: 영역 내 사람이 없었는지 확인 후 활성화')
            elif match:
                # Parent folder participates in session identity; hour alone must
                # not silently collapse sessions collected on different dates.
                row.update(point_id=match['point'].lower(),person=match['person'],
                           session=f'{path.parent.name}/{match["session"]}',repeat=f'r{int(match["repeat"]):02d}',
                           note='파일명 해석됨: session/배치/지점 확인 후 enabled=true 및 split 지정')
            else:
                row['note']='자동 라벨 불가: point_id/person/session/repeat/split 직접 입력 후 enabled=true'
        rows.append(row)
    _require(bool(rows),'이 폴더에는 CSV가 없습니다')
    result=pd.DataFrame(rows,columns=MANIFEST_COLUMNS)
    result.attrs['manifest_dir']=str(out_csv.parent)
    return save_manifest(result,out_csv)


def plan_splits(manifest,*,mode='repeats',train_people=(),validation_people=(),test_people=(),
                train_sessions=(),validation_sessions=(),test_sessions=(),
                train_repeats=('r01','r02','r03'),validation_repeats=('r04',),test_repeats=('r05',),
                fit_people=(),heldout_people=(),fit_train_repeats=('r01','r02','r03','r04'),
                fit_validation_repeats=('r05',),empty_mode='repeats',
                empty_train_repeats=('r01','r02','r03'),empty_validation_repeats=('r04',),empty_test_repeats=('r05',),
                empty_train_sessions=(),empty_validation_sessions=(),empty_test_sessions=()):
    """Assign entire recordings using explicit disjoint groups, never random rows.

    All enabled files must be allocated or deliberately disabled. Same-session
    repeat splits are a pilot protocol, not an unseen-person/time guarantee.
    In people/heldout_people modes, empty belongs to no person and uses the
    separate empty_* split plan. In sessions/repeats modes, the main plan applies
    to all eleven classes. Never duplicate empty files into several people's groups.
    """
    frame=read_manifest(manifest) if isinstance(manifest,(str,Path)) else manifest.copy()
    _require(mode in {'people','heldout_people','sessions','repeats'},'mode: people/heldout_people/sessions/repeats')

    def split_mapping(groups,field,split_names=SPLITS):
        groups=[set(map(str,g)) for g in groups]
        _require(all(groups),f'{field}: 사용할 모든 split의 그룹을 지정하세요')
        flattened=[item for group in groups for item in group]
        _require(len(flattened)==len(set(flattened)),f'동일 {field}를 여러 split에 배정할 수 없습니다')
        return {value:split for split,group in zip(split_names,groups) for value in group}

    is_empty=frame['point_id'].eq(EMPTY_LABEL)
    if mode=='heldout_people':
        fit_people=set(map(str,fit_people));heldout_people=set(map(str,heldout_people))
        _require(bool(fit_people) and bool(heldout_people),'fit_people와 heldout_people을 지정하세요')
        _require(not fit_people & heldout_people,'동일 person을 학습/검증과 시험에 배정할 수 없습니다')
        _require(EMPTY_PERSON not in fit_people|heldout_people,'none은 사람이 아닙니다. empty_* 분리를 사용하세요')
        mapping=split_mapping((fit_train_repeats,fit_validation_repeats),'fit repeat',('train','validation'))
        frame['split']=''
        fitting=~is_empty & frame['person'].isin(fit_people)
        frame.loc[fitting,'split']=frame.loc[fitting,'repeat'].map(mapping).fillna('')
        frame.loc[~is_empty & frame['person'].isin(heldout_people),'split']='test'
    else:
        field={'people':'person','sessions':'session','repeats':'repeat'}[mode]
        groups={'people':(train_people,validation_people,test_people),
                'sessions':(train_sessions,validation_sessions,test_sessions),
                'repeats':(train_repeats,validation_repeats,test_repeats)}[mode]
        mapping=split_mapping(groups,field)
        if mode=='people':
            _require(EMPTY_PERSON not in mapping,'none은 사람이 아닙니다. empty_* 분리를 사용하세요')
        frame['split']=frame[field].map(mapping).fillna('')
    if mode in {'people','heldout_people'}:
        _require(empty_mode in {'repeats','sessions'},'empty_mode: repeats/sessions')
        field='repeat' if empty_mode=='repeats' else 'session'
        groups=(empty_train_repeats,empty_validation_repeats,empty_test_repeats) if empty_mode=='repeats' else (
            empty_train_sessions,empty_validation_sessions,empty_test_sessions)
        mapping=split_mapping(groups,f'empty {field}')
        frame.loc[is_empty,'split']=frame.loc[is_empty,field].map(mapping).fillna('')
    frame.loc[~frame['enabled'].map(_enabled),'split']=''
    frame.attrs['split_mode']=mode
    if mode in {'people','heldout_people'}: frame.attrs['empty_split_mode']=empty_mode
    validate_manifest(frame,require_splits=SPLITS)
    return frame


def validate_manifest(manifest,*,require_splits=SPLITS):
    """Recompute SHA; reject path/hash leakage and session/person/repeat leakage.

    Hashing held-out files verifies identity only: CSI features are not parsed.
    The editable sha256 column is deliberately not trusted.
    """
    frame=read_manifest(manifest) if isinstance(manifest,(str,Path)) else manifest.copy()
    needed={'path','point_id','person','session','repeat','split','enabled'}
    _require(needed<=set(frame.columns),f'manifest 필수 열 누락: {sorted(needed-set(frame.columns))}')
    base=Path(frame.attrs.get('manifest_dir',Path.cwd()))
    frame=frame.fillna('')
    rows=frame.loc[frame['enabled'].map(_enabled)]
    _require(len(rows)>0,'enabled=true 파일이 없습니다. 메타데이터 확인 후 활성화하세요')
    seen_paths,seen_hashes,group_splits={}, {}, {}
    records=[]
    for _,row in rows.iterrows():
        record={str(k):str(v).strip() for k,v in row.to_dict().items()}
        for name in needed-{'enabled'}:
            _require(bool(record[name]),f"{record['path']}: {name}가 비어 있습니다")
        _require(record['point_id'] in CLASSES,f"알 수 없는 point_id: {record['point_id']}; Q/번호를 자동 매핑하지 않습니다")
        if record['point_id']==EMPTY_LABEL:
            _require(record['person']==EMPTY_PERSON,f"{record['path']}: empty의 person은 none이어야 합니다 (사람별로 복사하지 마세요)")
        else:
            _require(record['person'].lower()!=EMPTY_PERSON,f"{record['path']}: 사람이 있는 지점에 person=none을 사용할 수 없습니다")
        _require(record['split'] in SPLITS,f"알 수 없는 split: {record['split']}")
        path=(base/record['path']).resolve()
        _require(path.is_file(),f'원본 파일 없음: {path}')
        _require(path.suffix.lower()=='.csv',f'원본은 CSV여야 합니다: {path}')
        _require(str(path) not in seen_paths,f'같은 원본 경로 중복: {path}')
        digest=file_sha256(path)
        _require(digest not in seen_hashes,f'원본 내용 SHA 중복/누출: {record["path"]}, {seen_hashes.get(digest)}')
        group=(record['session'],record['person'],record['repeat'])
        if group in group_splits:
            _require(group_splits[group]==record['split'],f'동일 session/person/repeat가 split에 섞였습니다: {group}')
        group_splits[group]=record['split']
        seen_paths[str(path)]=record['split'];seen_hashes[digest]=record['path']
        record.update(source_id=len(records),resolved_path=str(path),sha256=digest,
                      participant=record['person'],block=record['session'])
        records.append(record)
    for split in require_splits:
        found={r['point_id'] for r in records if r['split']==split}
        _require(found==set(CLASSES),f'{split}에는 9지점 + p10(p05 앉기) + empty의 11클래스 모두 필요합니다. 누락: {sorted(set(CLASSES)-found)}')
    return records


def _read_record(record,config):
    """Read one original recording. Camera columns never become model features."""
    path=record['resolved_path']
    before=file_sha256(path)
    _require(before==record['sha256'],f"원본 SHA 변경: {record['path']}")
    frame=pd.read_csv(path,encoding='utf-8-sig')
    required={'trigger_seq','rx_index','rssi','csi_len'}
    _require(required<=set(frame.columns),f"{record['path']}: CSI 필수 열 누락 {required-set(frame.columns)}")
    _require('iq_pairs' in frame or 'csi_raw_hex' in frame,'iq_pairs 또는 csi_raw_hex가 필요합니다')
    _require(len(frame)>0,f"빈 CSV: {record['path']}")
    if 'csi_host_time' in frame:
        stamp=pd.to_datetime(frame['csi_host_time'],format='mixed',errors='coerce',utc=True)
        _require(stamp.notna().all(),'유효하지 않은 csi_host_time')
        times=(stamp-stamp.min()).dt.total_seconds().to_numpy(dtype=float)
        time_basis='csi_host_time'
    elif 'time_s' in frame or 'monotonic_ns' in frame:
        field='time_s' if 'time_s' in frame else 'monotonic_ns'
        values=pd.to_numeric(frame[field],errors='coerce').to_numpy(dtype=float)
        _require(np.isfinite(values).all(),f'유효하지 않은 {field}')
        times=(values-values.min())/(1e9 if field=='monotonic_ns' else 1)
        time_basis=field
    else: raise ValueError('csi_host_time/time_s/monotonic_ns 중 시간 열이 필요합니다')
    _require((np.diff(times)>=-1e-9).all(),f"시간 역전이 있는 파일: {record['path']}")
    frame['time_s']=times
    for field in ('trigger_seq','rx_index'):
        values=pd.to_numeric(frame[field],errors='coerce').to_numpy(dtype=float)
        _require(np.isfinite(values).all() and (values==np.floor(values)).all(),f'{field}는 유한 정수여야 합니다')
        frame[field]=values.astype(np.int64)
    _require((np.diff(frame.trigger_seq.to_numpy())>=0).all(),f"trigger_seq 역전/재시작 파일: {record['path']}; 세션 분리가 필요합니다")
    _require(set(frame.rx_index.unique())==set(config['rx_ids']),f"{record['path']}: RX0~4가 모두 필요합니다")
    duration=float(times.max());start=float(config['trim_start_s']);end=duration-float(config['trim_end_s'])
    _require(end>start,f"{record['path']}: trim 이후 길이 부족")
    cycles=[];rejected=Counter()
    for _,group in frame.groupby('trigger_seq',sort=False):
        try: cycles.append(cycle_from_rows(group.to_dict('records'),config))
        except (ValueError,TypeError,KeyError) as exc: rejected[str(exc)]+=1
    cycles.sort(key=lambda c:c['time_s'])
    selected=[];last=-np.inf
    for c in cycles:
        t=float(c['time_s'])
        if start<=t<=end and t-last+1e-9>=config['min_interval_s']:
            c['source_id']=record['source_id'];selected.append(c);last=t
    windows=make_windows(selected,config,start_s=start,end_s=end)
    candidates=max(0,math.floor((end-start-config['window_s']+1e-9)/config['stride_s'])+1)
    count_fail=span_fail=0
    for i in range(candidates):
        a=start+i*config['stride_s'];b=a+config['window_s']
        group=[c for c in selected if a<=c['time_s']<b]
        if len(group)<config['min_window_cycles']: count_fail+=1
        elif group[-1]['time_s']-group[0]['time_s']+1e-9<config['min_window_span_s']: span_fail+=1
    _require(file_sha256(path)==before,f"읽는 동안 원본 변경: {record['path']}")
    audit={**record,'rows':len(frame),'duration_s':duration,'time_basis':time_basis,
           'complete_cycles':len(cycles),'selected_cycles':len(selected),'rejected_cycles':sum(rejected.values()),
           'rejection_reasons':dict(rejected),'candidate_windows':candidates,'accepted_windows':len(windows),
           'rejected_windows':candidates-len(windows),'min_cycle_count_failed':count_fail,
           'min_span_failed':span_fail,'sample_count':len(windows),'stride_s':config['stride_s']}
    return audit,windows


def load_dataset(manifest,config=None,*,splits=('train','validation'),expected_hashes=None,records=None):
    """Parse only requested splits; defaults keep held-out test CSV features sealed.

    Call test explicitly after model freeze. Features use the same core as live.
    A dataset has one stride, so train/validation and test are returned separately.
    """
    config=validate_config(config)
    splits=tuple(splits)
    _require(bool(splits) and set(splits)<=set(SPLITS),'잘못된 splits')
    records=records if records is not None else validate_manifest(manifest)
    if expected_hashes is not None:
        current={str(r['resolved_path']):r['sha256'] for r in records}
        _require(current==expected_hashes,'freeze 이후 원본 파일 목록 또는 SHA가 달라졌습니다')
    selected=[r for r in records if r['split'] in splits]
    samples=[];audits=[]
    for index,record in enumerate(selected,1):
        audit,windows=_read_record(record,config);audits.append(audit)
        print(f"CSV {index}/{len(selected)} [{record['split']}] {Path(record['path']).name}: "
              f"{len(windows)}/{audit['candidate_windows']} windows, "
              f"{audit['complete_cycles']} complete cycles",flush=True)
        for number,window in enumerate(windows):
            samples.append({'window':window,'sample_index':number,
                **{k:record[k] for k in ('split','point_id','source_id','sha256','path','participant','block','repeat')}})
    for split in splits:
        found={s['point_id'] for s in samples if s['split']==split}
        _require(found==set(CLASSES),f'{split}: 필터 통과 후 11클래스 일부/전체 누락: {set(CLASSES)-found}')
    return {'schema':'csi_presence_dataset_v2','config':config,'records':pd.DataFrame(audits),
            'samples':samples,'classes':CLASSES.copy(),'points_cm':dict(POINTS_CM)}


# Explicit compatibility aliases for the existing model API, not a second parser.
build_manifest=create_manifest
assign_splits=plan_splits
