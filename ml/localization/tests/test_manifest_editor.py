import tempfile
from pathlib import Path
import unittest
import pandas as pd
from manifest_editor import apply_changes, save_edited
from location_data import save_manifest, read_manifest, file_sha256


class EditorTests(unittest.TestCase):
    def test_empty_has_no_person_and_can_be_corrected(self):
        frame=pd.DataFrame({'path':['a.csv'], 'point_id':['p01'], 'person':['G']})
        edited=apply_changes(frame,[0],{'point_id':'empty'})
        self.assertEqual(edited.loc[0,'person'],'none')
        self.assertEqual(frame.loc[0,'person'],'G')
        corrected=apply_changes(edited,[0],{'point_id':'p03'})
        self.assertEqual(corrected.loc[0,'person'],'')
        with self.assertRaisesRegex(ValueError,'none'):
            apply_changes(frame,[0],{'point_id':'empty','person':'G'})

    def test_bulk_edit_preserves_original_paths_and_other_rows(self):
        frame=pd.DataFrame({'path':['a.csv','b.csv'], 'point_id':['',''], 'person':['','']})
        frame.attrs['manifest_dir']='unchanged'
        edited=apply_changes(frame,[0],{'point_id':'p01','person':'G'})
        self.assertEqual(edited.loc[0,'person'],'G')
        self.assertEqual(edited.loc[1,'person'],'')
        self.assertEqual(edited.path.tolist(),frame.path.tolist())
        self.assertEqual(frame.loc[0,'person'],'')
        self.assertEqual(edited.attrs,frame.attrs)
        with self.assertRaises(ValueError): apply_changes(frame,[0],{'path':'changed.csv'})
        with self.assertRaises(ValueError): apply_changes(frame,[0],{'point_id':'Q1'})

    def test_backup_and_external_edit_conflict(self):
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp)
            raw=base/'recording.csv';raw.write_text('original CSI',encoding='utf-8')
            path=base/'manifest.csv'
            frame=pd.DataFrame({'path':[str(raw)],'point_id':[''],'person':['']})
            save_manifest(frame,path)
            digest=file_sha256(path);before=path.read_bytes()
            frame=read_manifest(path)
            edited=apply_changes(frame,[0],{'point_id':'p05'})
            after,backup=save_edited(edited,path,digest)
            self.assertEqual(backup.read_bytes(),before)
            self.assertEqual(read_manifest(path).loc[0,'point_id'],'p05')
            self.assertEqual(raw.read_text('utf-8'),'original CSI')
            self.assertNotEqual(after,digest)
            with self.assertRaisesRegex(RuntimeError,'변경'): save_edited(edited,path,digest)


if __name__=='__main__': unittest.main()
