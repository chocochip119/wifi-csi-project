"""Catalogue for one newly trained Studio run. No legacy fitted-state import."""
from pathlib import Path
import hashlib
import json
import os

from labels import CLASSES, LOCATION_CLASSES, EMPTY_LABEL, POINTS_CM, TASK

CATALOG_SCHEMA = 'csi_studio_catalog_v2_presence'

ROOT = Path(__file__).resolve().parent
os.environ.setdefault('LOKY_MAX_CPU_COUNT', '1')
CASE_LABELS = {'custom': '사용자 지정 분리'}


def check_environment():
    from environment_probe import check_environment as check
    return check(strict=True)


def resolve_run_root(path):
    path = Path(path).resolve()
    if path.is_file() and path.name == 'model_catalog.json':
        path = path.parent
    if not (path/'model_catalog.json').is_file() and (path/'fit/model_catalog.json').is_file():
        path = path/'fit'
    return path


class ModelCatalog:
    def __init__(self, root=ROOT):
        self.root = resolve_run_root(root)
        path = self.root/'model_catalog.json'
        if not path.is_file():
            raise ValueError('학습 완료된 결과 폴더를 선택하세요. 먼저 01_Train_and_Evaluate.ipynb에서 학습합니다.')
        self.data = json.loads(path.read_text(encoding='utf-8'))
        if self.data.get('schema') != CATALOG_SCHEMA:
            raise ValueError('9지점+p10(p05 앉기)+empty의 11클래스 학습 결과가 필요합니다. 기존 5/6클래스 모델은 이 앱에서 열 수 없으니 새로 학습하세요.')
        if (self.data.get('classes') != list(CLASSES) or self.data.get('task') != TASK
                or self.data.get('empty_label') != EMPTY_LABEL
                or self.data.get('location_classes') != list(LOCATION_CLASSES)
                or self.data.get('points_cm') != POINTS_CM):
            raise ValueError('카탈로그의 11클래스/빈 공간/좌표 계약이 잘못되었습니다.')
        from location_model import runtime_versions
        if self.data.get('versions') != runtime_versions():
            raise ValueError('학습 당시 Python/라이브러리와 현재 환경이 다릅니다. 학습과 추론에 같은 .venv를 선택하세요.')
        self.entries = self.data['models']
        self.by_id = {e['id']: e for e in self.entries}
        if not self.entries or len(self.entries) != len(self.by_id):
            raise ValueError('비어 있거나 중복된 모델 목록')
        if self.data.get('default_id') not in self.by_id:
            raise ValueError('선정 모델이 목록에 없습니다.')

    def path(self, entry, verify=True):
        path = (self.root/entry['path']).resolve()
        if not path.is_relative_to(self.root/'models'):
            raise ValueError('모델 경로 범위 오류')
        if verify and hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('모델 SHA-256 불일치: '+entry['id'])
        sidecar = path.with_suffix('.joblib.metadata.json')
        if not sidecar.is_file():
            raise ValueError('모델 버전 sidecar가 없습니다: '+sidecar.name)
        meta = json.loads(sidecar.read_text('utf-8'))
        from location_model import SCHEMA
        if (meta.get('schema') != SCHEMA or meta.get('classes') != list(CLASSES)
                or meta.get('task') != TASK or meta.get('empty_label') != EMPTY_LABEL):
            raise ValueError('모델 sidecar가 11클래스 계약과 다릅니다. 새로 학습하세요.')
        if meta.get('sha256') != entry['sha256'] or meta.get('versions') != self.data['versions']:
            raise ValueError('모델 sidecar와 카탈로그가 다릅니다.')
        return path

    def verify_all(self):
        for entry in self.entries:
            self.path(entry)
        return {'models': len(self.entries), 'selected': sum(bool(e['selected']) for e in self.entries),
                'hashes_match': True}


def export_catalog(run_dir):
    """Called only after validation has selected a model; never considers test scores."""
    from location_model import runtime_versions
    root = Path(run_dir).resolve()
    report = json.loads((root/'training_report.json').read_text('utf-8'))
    if not report.get('complete') or report.get('test_scores_accessed'):
        raise ValueError('검증 완료 및 시험 미사용 학습 결과가 필요합니다.')
    if (report.get('classes') != list(CLASSES) or report.get('task') != TASK
            or report.get('empty_label') != EMPTY_LABEL or report.get('points_cm') != POINTS_CM):
        raise ValueError('11클래스 학습 결과가 필요합니다. 기존 모델을 변환하지 말고 새로 학습하세요.')
    target = root/'model_catalog.json'
    if target.exists():
        raise FileExistsError('기존 카탈로그를 보존합니다: '+str(target))
    entries = []
    for fit in report['fits']:
        candidate = fit['candidate']
        path = root/fit['model_path']
        entries.append({'id': candidate, 'candidate': candidate, 'path': fit['model_path'],
                        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                        'family': fit['family'], 'variant': fit['variant'],
                        'task': TASK, 'classes': list(CLASSES), 'empty_label': EMPTY_LABEL,
                        'study': 'local_training', 'study_label': root.parent.name,
                        'case': 'custom', 'case_label': '사용자 지정 분리',
                        'selected': candidate == report['selected_candidate'],
                        'validation_balanced_accuracy': fit['validation_balanced_accuracy'],
                        'validation_macro_f1': fit['validation_macro_f1']})
    value = {'schema': CATALOG_SCHEMA, 'versions': runtime_versions(),
             'task': TASK, 'classes': list(CLASSES), 'location_classes': list(LOCATION_CLASSES),
             'empty_label': EMPTY_LABEL, 'points_cm': POINTS_CM,
             'default_id': report['selected_candidate'], 'models': entries,
             'selection_rule': report['selection_rule'], 'test_used_for_selection': False}
    target.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
    ModelCatalog(root).verify_all()
    return target
