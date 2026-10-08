"""Edit recording labels in a separate Tk window; never edits a source CSV."""
from pathlib import Path
from datetime import datetime
import argparse
import shutil
import uuid
from labels import CLASSES, EMPTY_LABEL, EMPTY_PERSON

FIELDS = ('point_id', 'person', 'session', 'repeat', 'split', 'enabled')
OPTIONS = {'point_id': CLASSES,
           'split': ('train','validation','test'), 'enabled': ('true','false')}


def apply_changes(frame, indices, updates):
    result = frame.copy()
    if not indices:
        raise ValueError('먼저 목록에서 파일을 선택하세요. Ctrl/Shift로 여러 파일을 선택할 수 있습니다.')
    for key, value in updates.items():
        if key not in FIELDS:
            raise ValueError('편집할 수 없는 열: '+key)
        value = str(value).strip()
        if key in OPTIONS and value not in OPTIONS[key]:
            raise ValueError(f'{key}: {OPTIONS[key]} 중 선택하세요.')
        if value:
            result.loc[list(indices), key] = value
    # Explicit empty selection is also an explicit no-subject label.
    if str(updates.get('point_id', '')).strip() == EMPTY_LABEL:
        if str(updates.get('person', '')).strip() not in ('', EMPTY_PERSON):
            raise ValueError('empty의 person은 none입니다. 사람 이름을 붙이지 마세요.')
        result.loc[list(indices), 'person'] = EMPTY_PERSON
    elif updates.get('point_id') in CLASSES:
        for index in indices:
            if result.loc[index, 'person'] == EMPTY_PERSON:
                result.loc[index, 'person'] = ''  # User must provide the actual subject.
    result.attrs = dict(frame.attrs)
    return result


def save_edited(frame, path, expected_hash):
    from location_data import file_sha256, save_manifest
    path = Path(path)
    if file_sha256(path) != expected_hash:
        raise RuntimeError('편집 중 다른 작업에서 목록이 변경됐습니다. 창을 닫고 다시 여세요.')
    backup = path.with_name(path.stem+'.backup_'+datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:6]+'.csv')
    shutil.copy2(path, backup)
    save_manifest(frame, path, overwrite=True)
    return file_sha256(path), backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    from location_data import read_manifest, file_sha256
    import tkinter as tk
    from tkinter import ttk, messagebox
    path = args.manifest.resolve()
    frame = read_manifest(path)
    loaded_hash = file_sha256(path)
    dirty = False
    root = tk.Tk()
    root.title('CSI 학습 파일 라벨 편집')
    root.geometry('1260x730')
    root.minsize(940,560)
    body = ttk.Frame(root,padding=14)
    body.pack(fill='both',expand=True)
    ttk.Label(body,text='1 파일 선택 → 2 바꿀 항목 입력 → 3 선택 파일에 적용 → 4 저장',
              font=('맑은 고딕',14,'bold')).pack(anchor='w')
    ttk.Label(body,text='원본 CSI 파일은 변경하지 않습니다. 빈 입력은 기존 값 유지. 같은 session·person·repeat는 같은 split에 배정합니다.',
              wraplength=1180).pack(anchor='w',pady=6)
    top = ttk.Frame(body); top.pack(fill='x',pady=5)
    ttk.Label(top,text='파일명 검색').pack(side='left')
    query = tk.StringVar(); search = ttk.Entry(top,textvariable=query,width=45);search.pack(side='left',padx=8)
    status = tk.StringVar(value='파일을 선택하세요. 자동 해석된 라벨도 확인한 뒤 enabled=true로 바꿉니다.')
    table_frame = ttk.Frame(body);table_frame.pack(fill='both',expand=True)
    columns = ('path',)+FIELDS
    tree = ttk.Treeview(table_frame,columns=columns,show='headings',selectmode='extended')
    for name in columns:
        tree.heading(name,text=name)
        tree.column(name,width=490 if name=='path' else 95,minwidth=60,stretch=name=='path')
    vertical = ttk.Scrollbar(table_frame,orient='vertical',command=tree.yview)
    horizontal = ttk.Scrollbar(table_frame,orient='horizontal',command=tree.xview)
    tree.configure(yscrollcommand=vertical.set,xscrollcommand=horizontal.set)
    tree.grid(row=0,column=0,sticky='nsew');vertical.grid(row=0,column=1,sticky='ns');horizontal.grid(row=1,column=0,sticky='ew')
    table_frame.rowconfigure(0,weight=1);table_frame.columnconfigure(0,weight=1)
    fields_row = ttk.Frame(body);fields_row.pack(fill='x',pady=12)
    variables = {}
    for i,name in enumerate(FIELDS):
        group=ttk.Frame(fields_row);group.grid(row=0,column=i,padx=4,sticky='w')
        ttk.Label(group,text=name).pack(anchor='w')
        var=tk.StringVar(); variables[name]=var
        if name in OPTIONS:
            widget=ttk.Combobox(group,textvariable=var,values=('',)+OPTIONS[name],width=13,state='readonly')
        else:
            widget=ttk.Entry(group,textvariable=var,width=18)
        widget.pack()
    ttk.Label(body,text='사람 있음: point_id=p01, person=G. p10 = p05 의자에 앉음. 사람 없음: point_id=empty → person=none 자동 지정. session·repeat는 실제 수집 시간대·회차입니다.',
              wraplength=1160).pack(anchor='w')

    def refresh(*_):
        selected = set(tree.selection())
        tree.delete(*tree.get_children())
        for index,row in frame.iterrows():
            if query.get().lower() in str(row['path']).lower():
                tree.insert('', 'end', iid=str(index), values=tuple(str(row.get(c,'')) for c in columns))
        tree.selection_set([key for key in selected if tree.exists(key)])
        status.set(f'전체 {len(frame)}파일 · 표시 {len(tree.get_children())}파일 · 저장 전 변경 있음' if dirty else f'전체 {len(frame)}파일 · 표시 {len(tree.get_children())}파일')

    def apply():
        nonlocal frame,dirty
        try:
            updates={key:var.get() for key,var in variables.items() if var.get().strip()}
            if not updates: raise ValueError('바꿀 항목을 하나 이상 입력하세요.')
            frame=apply_changes(frame,[int(key) for key in tree.selection()],updates)
            dirty=True;refresh()
        except Exception as exc: messagebox.showerror('적용하지 못했습니다',str(exc),parent=root)

    def save():
        nonlocal loaded_hash,dirty
        try:
            if not dirty: status.set('새 변경 사항이 없습니다.');return
            loaded_hash,backup=save_edited(frame,path,loaded_hash)
            dirty=False;status.set('저장 완료. 노트북에서 목록을 다시 읽으세요. 이전 목록 백업: '+backup.name)
        except Exception as exc: messagebox.showerror('저장하지 못했습니다',str(exc),parent=root)

    def close():
        if not dirty or messagebox.askyesno('저장 전 변경','저장하지 않은 변경을 버리고 닫을까요?',parent=root): root.destroy()

    ttk.Button(top,text='표시 파일 전체 선택',command=lambda:tree.selection_set(tree.get_children())).pack(side='left',padx=5)
    actions=ttk.Frame(body);actions.pack(fill='x',pady=12)
    ttk.Button(actions,text='선택 파일에 적용',command=apply).pack(side='left',padx=5)
    ttk.Button(actions,text='편집값 비우기',command=lambda:[var.set('') for var in variables.values()]).pack(side='left',padx=5)
    ttk.Button(actions,text='목록 저장',command=save).pack(side='left',padx=5)
    ttk.Button(actions,text='닫기',command=close).pack(side='right',padx=5)
    ttk.Label(body,textvariable=status,wraplength=1180).pack(anchor='w')
    query.trace_add('write',refresh)
    root.protocol('WM_DELETE_WINDOW',close)
    refresh();root.mainloop()


if __name__=='__main__': main()
