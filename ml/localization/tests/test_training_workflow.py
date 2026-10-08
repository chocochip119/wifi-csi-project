"""Synthetic CSV workflow tests only. Never accesses a user's real dataset."""
from __future__ import annotations

import csv
import json
from pathlib import Path
import os
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import pandas as pd

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from location_data import (CLASSES,create_manifest,read_manifest,save_manifest,plan_splits,
                            validate_manifest,load_dataset,file_sha256)
from location_core import DEFAULT_CONFIG,make_features
from studio_training import train_new_run,evaluate_run,prepare_summary
from labels import EMPTY_LABEL, EMPTY_PERSON


def write_synthetic_csv(path,point,repeat):
    """8.1 seconds with complete five-RX cycles and deliberately irrelevant pose."""
    fields=['time_s','trigger_seq','rx_index','rssi','csi_len','csi_raw_hex','camera_label']
    with path.open('w',newline='',encoding='utf-8') as stream:
        writer=csv.DictWriter(stream,fieldnames=fields);writer.writeheader()
        for step in range(82):
            for rx in range(5):
                iq=np.empty((192,2),dtype=np.int8)
                iq[:,0]=point*11+rx+repeat
                iq[:,1]=(np.arange(192)+point+step)%9+2
                iq[:2]=127
                writer.writerow(dict(time_s=step*.1,trigger_seq=step,rx_index=rx,rssi=-35-3*point-rx-repeat,
                                     csi_len=384,csi_raw_hex=iq.tobytes().hex(),camera_label='NOT_A_FEATURE'))


class ManifestChecks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name);self.data=self.base/'data';self.data.mkdir()

    def fixture(self):
        rows=[]
        for repeat,split in ((1,'train'),(2,'validation'),(3,'test')):
            for point,label in enumerate(CLASSES):
                path=self.data/f'raw_{repeat}_{point}.csv'
                write_synthetic_csv(path,point,repeat)
                rows.append(dict(path=str(path),point_id=label,person=EMPTY_PERSON if label==EMPTY_LABEL else 'synthetic',session='synthetic_session',
                                 repeat=f'r{repeat:02d}',split=split,enabled=True,sha256='DO_NOT_TRUST_EDITED_HASH',note='synthetic'))
        frame=pd.DataFrame(rows);frame.attrs['manifest_dir']=str(self.base)
        return save_manifest(frame,self.base/'manifest.csv')

    def test_generic_names_remain_unlabelled_disabled_and_csv_unchanged(self):
        original=self.data/'sync_csi_pose_20261001_220833_20261001_220833.csv'
        write_synthetic_csv(original,0,1)
        before=file_sha256(original)
        frame=create_manifest(self.data,self.base/'manifest.csv')
        self.assertEqual(frame.loc[0,'point_id'],'')
        self.assertEqual(frame.loc[0,'person'],'')
        self.assertFalse(bool(frame.loc[0,'enabled']))
        self.assertEqual(frame.loc[0,'sha256'],before)
        self.assertEqual(file_sha256(original),before)
        with self.assertRaises(FileExistsError): create_manifest(self.data,self.base/'manifest.csv')

    def test_explicit_filename_metadata_is_inferred_but_requires_review(self):
        for name in ('1001_14시_p01G1.csv','20261001_l02_b01_s02_r03_p05.csv'):
            write_synthetic_csv(self.data/name,0,1)
        frame=create_manifest(self.data,self.base/'manifest.csv')
        self.assertEqual(set(frame.point_id),{'p01','p05'})
        self.assertEqual(set(frame.person),{'G','s02'})
        self.assertFalse(frame.enabled.any())

    def test_original_hash_is_recomputed_and_duplicate_contents_fail(self):
        frame=self.fixture()
        records=validate_manifest(frame)
        self.assertTrue(all(len(r['sha256'])==64 for r in records))
        target=self.data/'a_copy.csv';shutil.copyfile(records[0]['resolved_path'],target)
        copy=frame.iloc[0].copy();copy['path']=str(target);copy['split']='test';copy['repeat']='r09'
        doubled=pd.concat([frame,pd.DataFrame([copy])],ignore_index=True)
        doubled.attrs=frame.attrs.copy()
        with self.assertRaisesRegex(ValueError,'SHA 중복'): validate_manifest(doubled)

    def test_repeat_groups_disjoint_and_same_visit_cannot_cross_splits(self):
        frame=self.fixture()
        with self.assertRaisesRegex(ValueError,'동일 repeat'):
            plan_splits(frame,mode='repeats',train_repeats=['r01'],validation_repeats=['r01'],test_repeats=['r03'])
        frame.loc[0,'split']='validation'
        with self.assertRaisesRegex(ValueError,'session/person/repeat'): validate_manifest(frame)

    def test_relative_manifest_move_preserves_file_meaning_and_summary(self):
        frame=self.fixture()
        copied=save_manifest(frame,self.base/'nested'/'manifest.csv')
        self.assertEqual({r['sha256'] for r in validate_manifest(frame)},
                         {r['sha256'] for r in validate_manifest(copied)})
        self.assertEqual(prepare_summary(copied)['enabled_files'],3*len(CLASSES))
        self.assertEqual(prepare_summary(copied)['empty_files'],3)
        self.assertTrue(prepare_summary(copied)['missing_fields'].empty)

    def test_cross_drive_manifest_paths_fall_back_to_absolute(self):
        from location_data import _manifest_path
        if os.name=='nt':
            self.assertEqual(_manifest_path(Path(r'C:\\source\\capture.csv'),Path(r'D:\\studio')),
                             str(Path(r'C:\\source\\capture.csv').resolve()))
        frame=self.fixture()
        before={r['sha256'] for r in validate_manifest(frame)}
        # Simulate the Windows relpath failure through both public save paths.
        with patch('location_data.os.path.relpath',side_effect=ValueError('different mount')):
            copied=save_manifest(frame,self.base/'cross_drive_manifest.csv')
            inventoried=create_manifest(self.data,self.base/'cross_drive_inventory.csv')
        self.assertTrue(all(Path(p).is_absolute() for p in copied.path))
        self.assertTrue(all(Path(p).is_absolute() for p in inventoried.path))
        self.assertEqual({r['sha256'] for r in validate_manifest(copied)},before)

    def test_training_dataset_does_not_parse_test_and_test_has_distinct_stride(self):
        import location_data
        frame=self.fixture()
        parsed=[];original=location_data._read_record
        def trace(record,config):
            parsed.append(record['split']);return original(record,config)
        with patch('location_data._read_record',side_effect=trace):
            train=load_dataset(frame,DEFAULT_CONFIG)
        self.assertEqual(set(parsed),{'train','validation'})
        self.assertEqual(make_features([s['window'] for s in train['samples']],train['config']).shape[1],955)
        test=load_dataset(frame,{**DEFAULT_CONFIG,'stride_s':.5},splits=('test',))
        self.assertGreater(len(test['samples']),sum(s['split']=='train' for s in train['samples']))
        self.assertEqual(set(test['records'].split),{'test'})
        self.assertTrue((train['records'].accepted_windows+train['records'].rejected_windows==train['records'].candidate_windows).all())

    def test_empty_training_class_without_good_reception_is_rejected(self):
        frame=self.fixture()
        record=next(r for r in validate_manifest(frame) if r['point_id']==EMPTY_LABEL and r['split']=='train')
        path=Path(record['resolved_path'])
        raw=pd.read_csv(path)
        # One early RX4 packet remains, so the file contains all RX IDs but no
        # complete cycle survives the normal 2-second trim. Missing input must
        # not manufacture an empty-room training sample.
        raw=raw[raw.rx_index.ne(4)|raw.trigger_seq.eq(0)]
        raw.to_csv(path,index=False)
        with self.assertRaisesRegex(ValueError,'필터 통과 후 11클래스.*empty'):
            load_dataset(frame,DEFAULT_CONFIG)

    def test_fresh_training_freeze_catalogue_evaluation_and_tamper_guards(self):
        frame=self.fixture()
        raw_before={r['resolved_path']:r['sha256'] for r in validate_manifest(frame)}
        run=train_new_run(frame,self.base/'runs',families=('knn','ridge','mlp'))
        frozen=json.loads((run/'frozen.json').read_text(encoding='utf-8'))
        self.assertNotEqual(frozen['pid'],os.getpid())
        self.assertEqual(frozen['model_count'],3)
        self.assertEqual(set(frozen['parsed_csv_splits']),{'train','validation'})
        self.assertEqual(len(frozen['parsed_csv_paths']),2*len(CLASSES))
        self.assertFalse((run/'evaluation').exists())
        self.assertEqual(len(list((run/'fit/models').glob('*.joblib'))),3)
        self.assertEqual(len(list((run/'fit/models').glob('*.metadata.json'))),3)
        model_hashes={p.name:file_sha256(p) for p in (run/'fit/models').iterdir()}
        report=evaluate_run(run)
        self.assertFalse(report['training_performed'])
        self.assertFalse(report['selection_changed_after_test'])
        self.assertEqual(report['selected_candidate'],frozen['selected_candidate'])
        self.assertEqual(len(report['results']),3)
        self.assertEqual(len(report['parsed_csv_paths']),len(CLASSES))
        self.assertTrue(all('empty_false_positive_rate' in row and 'occupied_miss_rate' in row for row in report['results']))
        self.assertEqual({p.name:file_sha256(p) for p in (run/'fit/models').iterdir()},model_hashes)
        with self.assertRaises(FileExistsError): evaluate_run(run)
        self.assertEqual({p:file_sha256(p) for p in raw_before},raw_before)
        # A distinct fresh run has no cumulative state and gets a unique path.
        second=train_new_run(frame,self.base/'runs',families=('ridge',))
        self.assertNotEqual(second,run)
        with (self.data/'raw_3_0.csv').open('a',encoding='utf-8') as stream: stream.write('\n')
        with self.assertRaisesRegex(RuntimeError,'원본 CSV'):
            evaluate_run(second)

    def test_collector_iq_pairs_and_host_time_match_raw_hex_features(self):
        import location_data
        frame=self.fixture()
        before=load_dataset(frame,DEFAULT_CONFIG)
        before_features=make_features([s['window'] for s in before['samples']],before['config'])
        # Re-encode only temporary synthetic fixtures into the real collector's
        # text representation. Camera columns remain irrelevant to features.
        for record in validate_manifest(frame):
            path=Path(record['resolved_path'])
            data=pd.read_csv(path)
            data['iq_pairs']=[json.dumps(np.frombuffer(bytes.fromhex(v),dtype=np.int8).reshape(-1,2).tolist())
                              for v in data.pop('csi_raw_hex')]
            data['csi_host_time']=(pd.Timestamp('2026-10-02T10:00:00+09:00')+
                                   pd.to_timedelta(data.pop('time_s'),unit='s')).astype(str)
            data['camera_label']='A_DIFFERENT_IRRELEVANT_LABEL'
            data.to_csv(path,index=False,encoding='utf-8-sig')
        after=load_dataset(frame,DEFAULT_CONFIG)
        after_features=make_features([s['window'] for s in after['samples']],after['config'])
        np.testing.assert_allclose(after_features,before_features,atol=1e-12,rtol=0)

    def test_experimental_phase_fits_fresh_train_only_and_evaluates(self):
        from location_model import load_model
        frame=self.fixture()
        run=train_new_run(frame,self.base/'runs',families=('ridge',),variant='amp_phase_rssi')
        bundle=load_model(next((run/'fit/models').glob('*.joblib')))
        self.assertEqual(bundle['feature_count'],2855)
        self.assertEqual(bundle['phase_contract']['fit_split'],'train')
        self.assertEqual(bundle['phase_contract']['input_bin_count'],950)
        self.assertEqual(bundle['phase_contract']['output_feature_count'],1900)
        self.assertEqual(len(bundle['phase_contract']['receivers']),5)
        frozen=json.loads((run/'frozen.json').read_text(encoding='utf-8'))
        self.assertEqual(set(frozen['parsed_csv_splits']),{'train','validation'})
        result=evaluate_run(run)
        self.assertFalse(result['training_performed'])
        self.assertEqual(len(result['results']),1)


if __name__=='__main__':unittest.main(verbosity=2)
