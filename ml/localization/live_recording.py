"""Record explicitly labelled live trials; this module never fits a model."""
from datetime import datetime, timezone
from pathlib import Path
import csv
import json
import threading
import time
import uuid
from labels import CLASSES, EMPTY_LABEL, EMPTY_PERSON

PRED_FIELDS = ['recorded_utc','truth','prediction','correct','model_id','model_sha256',
               'window_start_ns','window_end_ns','latest_sample_ns','valid_cycles',
               'representative_x_cm','representative_y_cm']
RAW_FIELDS = ['wall_time_s','monotonic_ns','rx_index','trigger_seq','uart_seq','rssi',
              'csi_len','csi_raw_hex','active_nodes','received_nodes','timeout_fired']

def utc(): return datetime.now(timezone.utc).isoformat()
def write_json(path, value): path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

class TrialRecorder:
    def __init__(self, root):
        self.root = Path(root)
        self.lock = threading.RLock()
        self.active = False
        self.last_result = None
        self.error = None

    def start(self, model, truth, seconds, subject='', raw=False, status=None):
        if truth not in ('', *CLASSES): raise ValueError('정답은 empty 또는 p01~p10 중 하나여야 합니다')
        if truth == EMPTY_LABEL:
            subject = EMPTY_PERSON
        seconds = float(seconds)
        if not 5 <= seconds <= 3600: raise ValueError('시험 길이는 5~3600초')
        with self.lock:
            if self.active: raise RuntimeError('현재 시험을 먼저 종료하세요')
            self.root.mkdir(parents=True, exist_ok=True)
            name = datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
            self.folder = self.root / name
            self.folder.mkdir()
            self.model, self.truth = dict(model), truth
            # Trial boundaries must use the same clock as samples/windows.
            self.begin_ns = time.perf_counter_ns()
            self.deadline_ns = self.begin_ns + int(seconds * 1e9)
            self.count = self.correct = self.raw_count = 0
            self.error = None
            self.ends = set()
            self.pred_file = (self.folder/'predictions.csv').open('x',newline='',encoding='utf-8-sig')
            self.pred_writer = csv.DictWriter(self.pred_file,fieldnames=PRED_FIELDS)
            self.pred_writer.writeheader()
            self.raw_file = None
            if raw:
                self.raw_file = (self.folder/'csi.csv').open('x',newline='',encoding='utf-8-sig')
                self.raw_writer = csv.DictWriter(self.raw_file,fieldnames=RAW_FIELDS,extrasaction='ignore')
                self.raw_writer.writeheader()
            self.meta = dict(schema='csi_live_trial_v2_presence', started_utc=utc(), status='recording', model=self.model,
                             truth=truth, subject=subject, requested_seconds=seconds, start_monotonic_ns=self.begin_ns,
                             deadline_monotonic_ns=self.deadline_ns, input_status=status,
                             monotonic_clock='time.perf_counter_ns',
                             window_s=2., inference_stride_s=.5, training_performed=False,
                             raw_csi_enabled=bool(raw), predictions_are_overlapping=True,
                             label_basis='User selected empty/point class; no camera ground truth',
                             classes=list(CLASSES), empty_room_detection=True,
                             empty_coordinate=None, unavailable_input_is_empty=False)
            write_json(self.folder/'metadata.json', self.meta)
            self.active = True
            return self.folder

    def on_prediction(self, event):
        with self.lock:
            if not self.active: return
            a, b = int(event['window_start_ns']), int(event['window_end_ns'])
            # No old or boundary-straddling input is labelled as a new trial.
            if a < self.begin_ns or b > self.deadline_ns or b in self.ends: return
            self.ends.add(b)
            correct = int(event['point_id'] == self.truth) if self.truth else ''
            row = dict(recorded_utc=utc(),truth=self.truth,prediction=event['point_id'],correct=correct,
                       model_id=self.model['id'],model_sha256=self.model['sha256'],
                       **{k:event[k] for k in PRED_FIELDS[6:]})
            try:
                self.pred_writer.writerow(row)
                self.pred_file.flush()
            except Exception as exc:
                self.error = '예측 CSV 저장 오류: ' + str(exc)
                raise
            self.count += 1
            self.correct += int(correct or 0)

    def on_sample(self, row):
        with self.lock:
            if not self.active or not self.raw_file: return
            if not self.begin_ns <= row['monotonic_ns'] <= self.deadline_ns: return
            try:
                self.raw_writer.writerow(row)
            except Exception as exc:
                self.error = '원본 CSI 저장 오류: ' + str(exc)
                raise
            self.raw_count += 1

    def finish(self, reason='manual_stop', status=None):
        with self.lock:
            if not self.active: return self.last_result
            self.active = False
            try:
                self.pred_file.close()
                if self.raw_file: self.raw_file.close()
            except Exception as exc:
                self.error = '기록 파일 종료 오류: ' + str(exc)
            self.meta.update(status='failed' if self.error else 'finished',end_reason=reason,ended_utc=utc(),
                             elapsed_seconds=(time.perf_counter_ns()-self.begin_ns)/1e9,
                             predictions=self.count,correct=self.correct if self.truth else None,
                             class_recall=self.correct/self.count if self.truth and self.count else None,
                             point_recall=self.correct/self.count if self.truth and self.count else None,
                             raw_rows=self.raw_count,output_status=status,error=self.error)
            write_json(self.folder/'metadata.json',self.meta)
            self.last_result = {'folder':str(self.folder),**self.meta}
            return self.last_result

    def snapshot(self):
        with self.lock:
            return dict(active=self.active,remaining_s=max(0,(self.deadline_ns-time.perf_counter_ns())/1e9) if self.active else 0,
                        predictions=getattr(self,'count',0),correct=getattr(self,'correct',0),
                        truth=getattr(self,'truth',''),folder=str(getattr(self,'folder','')),error=self.error)

def summarize_trials(root):
    """Only observed true labels contribute to BA; show label coverage explicitly."""
    import pandas as pd
    rows=[]
    for p in Path(root).glob('*/metadata.json'):
        m=json.loads(p.read_text(encoding='utf-8'))
        if m.get('status') != 'finished': continue
        rows.append(dict(trial=p.parent.name,model=m['model']['id'],subject=m.get('subject',''),
                         point=m['truth'],predictions=m['predictions'],correct=m.get('correct'),
                         class_recall=m.get('class_recall',m.get('point_recall')),
                         point_recall=m.get('point_recall'),end_reason=m['end_reason']))
    return pd.DataFrame(rows,columns=['trial','model','subject','point','predictions','correct','class_recall','point_recall','end_reason'])
