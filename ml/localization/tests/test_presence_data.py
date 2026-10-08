"""Presence-label and split isolation tests using disposable synthetic files only."""
from pathlib import Path
import sys
import tempfile
import unittest

import pandas as pd

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from labels import CLASSES, EMPTY_LABEL, EMPTY_PERSON, LOCATION_CLASSES
from location_data import create_manifest, plan_splits, validate_manifest


class PresenceManifestChecks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name)

    def records(self,people=('A','B','C'),repeats=range(1,6),sessions=('b01',)):
        rows=[]
        for session in sessions:
            for repeat in repeats:
                for person,labels in [(p,LOCATION_CLASSES) for p in people]+[(EMPTY_PERSON,(EMPTY_LABEL,))]:
                    for label in labels:
                        path=self.base/f'{session}_{person}_{repeat}_{label}.csv'
                        path.write_text('identity\n'+path.name,encoding='utf-8')
                        rows.append(dict(path=str(path),point_id=label,person=person,session=session,
                                         repeat=f'r{repeat:02d}',split='',enabled=True))
        return pd.DataFrame(rows)

    def test_empty_filename_conventions_need_review_and_set_no_person(self):
        names=('20261002_l02_b01_none_r01_empty.csv','20261002_l02_b02_r02_empty.csv',
               '1002_10시_empty3.csv','20261002_11시_사람없음_r04.csv','1002_12시_빈공간5.csv')
        for name in names: (self.base/name).write_text(name,encoding='utf-8')
        result=create_manifest(self.base,self.base/'manifest.csv')
        self.assertEqual(set(result.point_id),{EMPTY_LABEL})
        self.assertEqual(set(result.person),{EMPTY_PERSON})
        self.assertEqual(set(result['repeat']),{'r01','r02','r03','r04','r05'})
        self.assertFalse(result.enabled.any())

    def test_ninepoint_and_seated_p10_filenames_are_inferred_but_p11_is_not(self):
        for name in ('1004_15시_p02E1.csv','1004_15시_p08A2.csv','1004_15시_p10D1.csv','1004_15시_p11D1.csv'):
            (self.base/name).write_text(name,encoding='utf-8')
        result=create_manifest(self.base,self.base/'manifest.csv').set_index('path')
        labels={Path(k).name:v for k,v in result['point_id'].items()}
        self.assertEqual(labels['1004_15시_p02E1.csv'],'p02')
        self.assertEqual(labels['1004_15시_p08A2.csv'],'p08')
        self.assertEqual(labels['1004_15시_p10D1.csv'],'p10')
        self.assertEqual(labels['1004_15시_p11D1.csv'] if isinstance(labels['1004_15시_p11D1.csv'],str) else '','')
        self.assertFalse(result.enabled.any())

    def test_half_hour_session_names_are_inferred(self):
        for name in ('1004_19시반_p02C1.csv','1004_19시반_빈공간2.csv'):
            (self.base/name).write_text(name,encoding='utf-8')
        result=create_manifest(self.base,self.base/'manifest.csv')
        rows={Path(r.path).name:r for r in result.itertuples()}
        self.assertEqual(rows['1004_19시반_p02C1.csv'].point_id,'p02')
        self.assertTrue(rows['1004_19시반_p02C1.csv'].session.endswith('/1004_19시반'))
        self.assertEqual(rows['1004_19시반_빈공간2.csv'].point_id,EMPTY_LABEL)
        self.assertEqual(rows['1004_19시반_빈공간2.csv'].repeat,'r02')

    def test_people_split_empty_allocated_once_by_independent_repeats(self):
        frame=self.records()
        result=plan_splits(frame,mode='people',train_people=['A'],validation_people=['B'],test_people=['C'])
        occupied=result[result.point_id.ne(EMPTY_LABEL)]
        self.assertEqual(set(occupied[occupied.split.eq('train')].person),{'A'})
        self.assertEqual(set(occupied[occupied.split.eq('validation')].person),{'B'})
        self.assertEqual(set(occupied[occupied.split.eq('test')].person),{'C'})
        empty=result[result.point_id.eq(EMPTY_LABEL)]
        self.assertEqual(len(empty),5)
        self.assertEqual(empty.groupby('split').size().to_dict(),{'train':3,'validation':1,'test':1})
        self.assertEqual(len(result.path.unique()),len(frame))

    def test_heldout_people_keeps_person_out_and_empty_separately(self):
        frame=self.records()
        result=plan_splits(frame,mode='heldout_people',fit_people=['A','B'],heldout_people=['C'])
        occupied=result[result.point_id.ne(EMPTY_LABEL)]
        self.assertEqual(len(occupied[occupied.split.eq('train')]),8*len(LOCATION_CLASSES))
        self.assertEqual(len(occupied[occupied.split.eq('validation')]),2*len(LOCATION_CLASSES))
        self.assertEqual(len(occupied[occupied.split.eq('test')]),5*len(LOCATION_CLASSES))
        self.assertEqual(set(occupied[occupied.split.eq('test')].person),{'C'})
        self.assertEqual(result[result.point_id.eq(EMPTY_LABEL)].groupby('split').size().to_dict(),
                         {'train':3,'validation':1,'test':1})
        with self.assertRaisesRegex(ValueError,'동일 person'):
            plan_splits(frame,mode='heldout_people',fit_people=['A','B'],heldout_people=['B'])
        with self.assertRaisesRegex(ValueError,'동일 fit repeat'):
            plan_splits(frame,mode='heldout_people',fit_people=['A','B'],heldout_people=['C'],
                        fit_validation_repeats=['r04','r05'])

    def test_people_split_can_hold_out_empty_time_blocks(self):
        frame=self.records(repeats=(1,),sessions=('morning','midday','afternoon'))
        result=plan_splits(frame,mode='people',train_people=['A'],validation_people=['B'],test_people=['C'],
                           empty_mode='sessions',empty_train_sessions=['morning'],
                           empty_validation_sessions=['midday'],empty_test_sessions=['afternoon'])
        empty=result[result.point_id.eq(EMPTY_LABEL)]
        self.assertEqual(dict(zip(empty.session,empty.split)),
                         {'morning':'train','midday':'validation','afternoon':'test'})
        with self.assertRaisesRegex(ValueError,'동일 empty session'):
            plan_splits(frame,mode='people',train_people=['A'],validation_people=['B'],test_people=['C'],
                        empty_mode='sessions',empty_train_sessions=['morning'],
                        empty_validation_sessions=['morning'],empty_test_sessions=['afternoon'])

    def test_main_session_plan_also_applies_to_empty(self):
        frame=self.records(repeats=(1,),sessions=('b01','b02','b03'))
        result=plan_splits(frame,mode='sessions',train_sessions=['b01'],
                           validation_sessions=['b02'],test_sessions=['b03'])
        for split in ('train','validation','test'):
            self.assertEqual(set(result[result.split.eq(split)].point_id),set(CLASSES))

    def test_semantic_and_missing_empty_guards(self):
        frame=self.records(people=('A',))
        result=plan_splits(frame)
        wrong=result.copy()
        wrong.loc[wrong.point_id.eq(EMPTY_LABEL),'person']='A'
        with self.assertRaisesRegex(ValueError,'empty의 person은 none'):
            validate_manifest(wrong)
        wrong=result.copy();wrong.loc[wrong.point_id.eq('p01'),'person']=EMPTY_PERSON
        with self.assertRaisesRegex(ValueError,'사람이 있는 지점'):
            validate_manifest(wrong)
        wrong=result[~(result.point_id.eq(EMPTY_LABEL)&result.split.eq('test'))]
        with self.assertRaisesRegex(ValueError,'11클래스.*empty'):
            validate_manifest(wrong)

    def test_missing_empty_split_and_fake_none_person_fail(self):
        frame=self.records(repeats=(1,2))
        with self.assertRaisesRegex(ValueError,'11클래스.*empty'):
            plan_splits(frame,mode='people',train_people=['A'],validation_people=['B'],test_people=['C'],
                        empty_train_repeats=['r01'],empty_validation_repeats=['r02'],empty_test_repeats=['r03'])
        with self.assertRaisesRegex(ValueError,'none은 사람이 아닙니다'):
            plan_splits(frame,mode='people',train_people=['A',EMPTY_PERSON],validation_people=['B'],test_people=['C'])


if __name__=='__main__': unittest.main(verbosity=2)
