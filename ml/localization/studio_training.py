"""New independent runs and explicitly unsealed held-out evaluation.

Each train/evaluation call runs in a fresh Python process using the current
kernel executable. No historical fitted model, scaler or cache is read to fit.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

import pandas as pd

from location_core import validate_config,inference_config
from location_data import (CLASSES,create_manifest,read_manifest,save_manifest,plan_splits,
                            validate_manifest,load_dataset,file_sha256)
from labels import EMPTY_LABEL, EMPTY_PERSON

DEFAULT_PARAMS={'knn':{'n_neighbors':5,'weights':'distance','n_jobs':1},
                'ridge':{'alpha':10.},
                'mlp':{'hidden_layer_sizes':(64,32),'alpha':1e-3,'max_iter':300,
                       'early_stopping':False,'n_iter_no_change':25,'solver':'adam','warm_start':False}}


def utc(): return datetime.now(timezone.utc).isoformat()
def _json(path,data):
    Path(path).write_text(json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')
def _read(path): return json.loads(Path(path).read_text(encoding='utf-8'))
def _require(ok,message):
    if not ok: raise ValueError(message)


def prepare_summary(manifest):
    """Manifest-only overview; labels are not inferred from camera or file order."""
    frame=read_manifest(manifest) if isinstance(manifest,(str,Path)) else manifest.copy()
    from location_data import _enabled
    active=frame.loc[frame.enabled.map(_enabled)].copy()
    return {'files':len(frame),'enabled_files':len(active),
            'empty_files':int(active.point_id.eq(EMPTY_LABEL).sum()),
            'by_split_point':active.groupby(['split','point_id'],dropna=False).size().rename('files').reset_index(),
            'by_person_session':active.groupby(['person','session'],dropna=False).size().rename('files').reset_index(),
            'missing_fields':active[['path','point_id','person','session','repeat','split']].loc[
                active[['point_id','person','session','repeat','split']].fillna('').eq('').any(axis=1)]}


def _run_subprocess(stage,run_dir):
    log=run_dir/f'{stage}.log'
    command=[sys.executable,'-X','utf8','-B',str(Path(__file__).resolve()),stage,str(run_dir)]
    with log.open('x',encoding='utf-8') as stream:
        process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                                 text=True,encoding='utf-8',errors='replace',bufsize=1,
                                 cwd=Path(__file__).resolve().parent,
                                 env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1','PYTHONUNBUFFERED':'1'})
        try:
            for line in process.stdout:
                stream.write(line);stream.flush();print(line,end='',flush=True)
            returncode=process.wait()
        except BaseException:
            process.terminate();process.wait(timeout=10)
            raise
        finally:
            if process.stdout: process.stdout.close()
    if returncode:
        raise RuntimeError(f'{stage} 실패. 원본과 실패 결과는 보존했습니다. 로그: {log}\n'+log.read_text(encoding='utf-8')[-5000:])


def train_new_run(manifest,output_root,config=None,*,families=('knn','ridge','mlp'),variant='amp_rssi',seed=17):
    """Freeze file identities; train/validate in a new process, never score test.

    Returns the outer run directory. Model catalogue lives in fit/model_catalog.json.
    Evaluation is a separate evaluate_run(run_dir) call after selection freeze.
    """
    _require(variant in ('amp_rssi','amp_phase_rssi'),'지원하지 않는 특징 입력')
    families=tuple(families)
    _require(bool(families) and len(set(families))==len(families) and set(families)<={'knn','ridge','mlp'},'후보 모델 지정 오류')
    cfg=validate_config({**(config or {}),'variant':variant})
    _require(cfg['mode']=='window','이 학습 워크플로는 window 모드입니다')
    _require(cfg['stride_s']==2. and cfg['window_s']==2.,'기본 비교 프로토콜은 학습/검증 2초 창,2초 stride입니다')
    frame=read_manifest(manifest) if isinstance(manifest,(str,Path)) else manifest.copy()
    records=validate_manifest(frame)
    output_root=Path(output_root).resolve()
    output_root.mkdir(parents=True,exist_ok=True)
    run_dir=output_root/(datetime.now().strftime('run_%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:8])
    run_dir.mkdir()
    snapshot=save_manifest(frame,run_dir/'manifest.csv')
    frozen_records=validate_manifest(snapshot)
    protocol={'schema':'csi_studio_run_v2_presence','created_utc':utc(),'seed':int(seed),'families':list(families),
              'variant':variant,'phase_experimental':variant=='amp_phase_rssi','config':cfg,
              'test_config':inference_config(cfg,stride_s=.5),'model_params':DEFAULT_PARAMS,
              'manifest_sha256':file_sha256(run_dir/'manifest.csv'),'records':frozen_records,
              'selection_rule':'validation balanced accuracy, macro F1, declared candidate order',
              'previous_fitted_state_used':False,'warm_start':False,'test_features_used_for_training':False,
              'source_csv_read_only':True,'refit_train_plus_validation':False,
              'test_scores_computed':False,'entry_python':sys.executable,
              'classes':CLASSES.copy(),'empty_label':EMPTY_LABEL,'empty_person_code':EMPTY_PERSON,
              'empty_has_coordinates':False,'no_input_is_empty':False,
              'split_mode':frame.attrs.get('split_mode','manifest_explicit'),
              'empty_split_mode':frame.attrs.get('empty_split_mode','main_plan_or_manifest_explicit'),
              'limitations':['Eleven classes: nine nominal points, p10 = p05 seated (same coordinate as p05), plus empty; not continuous coordinates.',
                             'Empty means the marked area is unoccupied; reception failure is not an empty prediction.',
                             'Empty classification requires separately labelled empty recordings in train/validation/test.',
                             'Test windows overlap 75%; window count is not an independent trial count.',
                             'Same-person/session repeat split is a pilot, not unseen-person/time evidence.',
                             'Phase variant is experimental relative cos/sin, not calibrated physical phase.']}
    _json(run_dir/'protocol.json',protocol)
    print('독립 학습 시작:',run_dir,flush=True)
    _run_subprocess('train',run_dir)
    _require((run_dir/'frozen.json').is_file(),'모델 freeze가 완료되지 않았습니다')
    print('검증 선정 완료. 시험 점수는 아직 계산하지 않았습니다.',flush=True)
    return run_dir


def _verify_sources(run_dir,protocol):
    _require(file_sha256(run_dir/'manifest.csv')==protocol['manifest_sha256'],'고정 manifest가 변경됐습니다')
    records=validate_manifest(run_dir/'manifest.csv')
    current={r['resolved_path']:r['sha256'] for r in records}
    expected={r['resolved_path']:r['sha256'] for r in protocol['records']}
    _require(current==expected,'고정 이후 원본 CSV 또는 경로가 변경됐습니다. 새 run을 만드세요')
    return records


def _quality(dataset,path):
    frame=dataset['records'].copy()
    if 'rejection_reasons' in frame:
        frame['rejection_reasons']=frame['rejection_reasons'].map(lambda d:json.dumps(d,ensure_ascii=False))
    frame.to_csv(path,index=False,encoding='utf-8-sig')


def _metrics_tables(metrics,folder):
    pd.DataFrame({'point':metrics['confusion_labels'],
                  'precision':[metrics['per_point_precision'][p] for p in metrics['confusion_labels']],
                  'recall':[metrics['per_point_recall'][p] for p in metrics['confusion_labels']]}).to_csv(
                      folder/'per_point_metrics.csv',index=False,encoding='utf-8-sig')
    pd.DataFrame(metrics['confusion_matrix'],index=metrics['confusion_labels'],columns=metrics['confusion_labels']).to_csv(
        folder/'confusion_matrix.csv',encoding='utf-8-sig',index_label='truth')


def _train_worker(run_dir):
    from environment_probe import check_environment
    check_environment(strict=True)
    from location_model import train_compare
    from live_catalog import export_catalog
    protocol=_read(run_dir/'protocol.json')
    records=_verify_sources(run_dir,protocol)
    data=load_dataset(run_dir/'manifest.csv',protocol['config'],splits=('train','validation'),records=records)
    _require({s['split'] for s in data['samples']}=={'train','validation'},'학습 입력에 test 혼입')
    _quality(data,run_dir/'train_validation_quality.csv')
    params={k:dict(v) for k,v in protocol['model_params'].items()}
    result=train_compare(data,run_dir/'fit',families=protocol['families'],variants=(protocol['variant'],),
                         seed=protocol['seed'],model_params=params)
    catalog=export_catalog(run_dir/'fit')
    report=_read(run_dir/'fit'/'training_report.json')
    for fitted in report['fits']:
        folder=run_dir/'validation'/fitted['candidate'];folder.mkdir(parents=True)
        _metrics_tables(fitted['validation'],folder)
    _verify_sources(run_dir,protocol)
    fitted_paths=list((run_dir/'fit').rglob('*'))
    frozen_files={p.relative_to(run_dir).as_posix():file_sha256(p) for p in fitted_paths if p.is_file()}
    _json(run_dir/'frozen.json',{'schema':'csi_studio_freeze_v2_presence','created_utc':utc(),'pid':os.getpid(),
        'protocol_sha256':file_sha256(run_dir/'protocol.json'),'files':frozen_files,
        'selected_candidate':result['selected_candidate'],'catalog_path':str(Path(catalog).relative_to(run_dir)),
        'model_count':len(result['models']),'test_evaluated':False,
        'parsed_csv_splits':['train','validation'],'parsed_csv_paths':data['records']['resolved_path'].tolist(),
        'training_process_fresh':True,'prior_model_loaded_for_fit':False})


def _verify_freeze(run_dir):
    frozen=_read(run_dir/'frozen.json')
    _require(file_sha256(run_dir/'protocol.json')==frozen['protocol_sha256'],'freeze 이후 protocol 변경')
    for relative,digest in frozen['files'].items():
        path=(run_dir/relative).resolve()
        _require(path.is_relative_to(run_dir/'fit'),'모델 산출물 경로 범위 오류')
        _require(file_sha256(path)==digest,f'freeze 이후 모델/설정/선정 기록 변경: {relative}')
    return frozen


def evaluate_run(run_dir):
    """Unseal held-out files once, after freeze. Preserve all prior test results."""
    run_dir=Path(run_dir).resolve()
    _verify_freeze(run_dir)
    if (run_dir/'evaluation').exists() or (run_dir/'evaluate.log').exists():
        raise FileExistsError('이 run은 이미 시험을 요청했습니다. 기존 결과/오류를 보존합니다')
    _run_subprocess('evaluate',run_dir)
    return _read(run_dir/'evaluation'/'evaluation_summary.json')


def _evaluate_worker(run_dir):
    from environment_probe import check_environment
    check_environment(strict=True)
    from location_model import evaluate_saved
    frozen=_verify_freeze(run_dir)
    protocol=_read(run_dir/'protocol.json')
    records=_verify_sources(run_dir,protocol)
    data=load_dataset(run_dir/'manifest.csv',protocol['test_config'],splits=('test',),records=records)
    folder=run_dir/'evaluation';folder.mkdir()
    _quality(data,folder/'test_quality.csv')
    report=_read(run_dir/'fit'/'training_report.json')
    rows=[]
    for candidate,relative in report['models'].items():
        destination=folder/candidate
        metrics=evaluate_saved(run_dir/'fit'/relative,data,split='test',output_dir=destination,inference_stride_s=.5)
        _metrics_tables(metrics,destination)
        rows.append({'candidate':candidate,'selected_by_validation':candidate==frozen['selected_candidate'],
            **{k:metrics[k] for k in ('sample_count','file_count','accuracy','balanced_accuracy','macro_f1','macro_precision',
                                      'file_majority_accuracy','empty_false_positive_rate','occupied_miss_rate',
                                      'occupied_location_accuracy','occupancy_accuracy','empty_sample_count','occupied_sample_count')}})
    pd.DataFrame(rows).to_csv(folder/'all_model_test_results.csv',index=False,encoding='utf-8-sig')
    _verify_freeze(run_dir);_verify_sources(run_dir,protocol)
    _json(folder/'evaluation_summary.json',{'schema':'csi_studio_evaluation_v2_presence','created_utc':utc(),'pid':os.getpid(),
        'selected_candidate':frozen['selected_candidate'],'selection_changed_after_test':False,
        'results':rows,'parsed_csv_splits':['test'],'parsed_csv_paths':data['records']['resolved_path'].tolist(),
        'freeze_sha256':file_sha256(run_dir/'frozen.json'),'training_performed':False,
        'test_stride_s':.5,'window_s':2.,'overlapping_windows_are_independent':False,
        'file_majority_is_auxiliary_not_live_smoothing':True})


def main():
    _require(len(sys.argv)==3 and sys.argv[1] in ('train','evaluate'),'내부 사용: train/evaluate run_dir')
    run_dir=Path(sys.argv[2]).resolve()
    if sys.argv[1]=='train': _train_worker(run_dir)
    else: _evaluate_worker(run_dir)


if __name__=='__main__':main()
