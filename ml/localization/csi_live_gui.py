"""Standalone Tk desktop front end for newly trained Python 3.14 models.

Tk is only touched on the main thread. Environment/model loading and session
actions run on one worker; optional COM discovery uses a separate worker.
Opening the window does not open a COM port, run TX, or start inference.
"""
from pathlib import Path
import argparse
import os
import queue
import sys
import threading
import time
import traceback
from labels import CLASSES, EMPTY_LABEL, POINTS_CM, SEATED_LABELS, display_name

ROOT = Path(__file__).resolve().parent
# Nine representative positions; p10 (p05 seated) shares p05's coordinate and is drawn as a ring.
POINTS = {label: tuple(xy) for label, xy in POINTS_CM.items()}
EMPTY_CHOICE = 'empty · 사람 없음'
TRUTH_CHOICES = {display_name(label): label for label in POINTS}


def prediction_text(prediction):
    if prediction is None:
        return '입력 부족 / 대기'
    point = prediction.get('point_id')
    if point == EMPTY_LABEL:
        return '사람 없음 · empty (좌표 없음)'
    if point in POINTS:
        return f'사람 있음 · {display_name(point)} · {POINTS[point]} cm'
    return '잘못된 예측 · 표시 중지'


def truth_label(choice):
    if choice == EMPTY_CHOICE:
        return EMPTY_LABEL
    return TRUTH_CHOICES.get(choice, choice if choice in CLASSES else '')


def visible_prediction(state, pending, now_ns):
    """Never leave an old highlight visible while a control action is blocked."""
    pred = state.get('prediction')
    serial = state.get('serial', {})
    if (not pred or pending or state.get('stopped') or not state.get('inference_running')
            or not serial.get('connected') or serial.get('last_error')):
        return None
    # Same two-second freshness limit and clock as location_live._InferenceWorker.
    if not 0 <= now_ns - pred['monotonic_ns'] <= 2_000_000_000:
        return None
    return pred


def inspect_run_selection(value, *, catalog_factory=None):
    """Resolve a training output folder or its model without importing pickle on Tk."""
    if not value:
        raise ValueError('학습 결과 폴더를 선택하세요.')
    path = Path(value).expanduser().resolve()
    selected_path = None
    if path.is_file():
        if path.suffix.lower() != '.joblib':
            raise ValueError('모델 파일은 .joblib 이어야 합니다.')
        selected_path = path
        root = next((p for p in path.parents if (p / 'model_catalog.json').is_file()), None)
        if root is None:
            raise ValueError('모델 상위 폴더에 model_catalog.json이 없습니다. 학습 결과 폴더 전체를 옮기세요.')
    else:
        root = path
        if not (root / 'model_catalog.json').is_file() and (root / 'fit' / 'model_catalog.json').is_file():
            root = root / 'fit'
    if catalog_factory is None:
        from live_catalog import ModelCatalog
        catalog_factory = ModelCatalog
    catalog = catalog_factory(root)
    verified = catalog.verify_all()
    default = catalog.data.get('default_id') or next((e['id'] for e in catalog.entries if e.get('selected')), catalog.entries[0]['id'])
    if selected_path is not None:
        entry = next((e for e in catalog.entries if catalog.path(e).resolve() == selected_path), None)
        if entry is None:
            raise ValueError('선택한 파일이 학습 결과 모델 목록에 없습니다.')
        default = entry['id']
    return root, catalog, default, verified


class DesktopApp:
    def __init__(self, window, initial_port='', initial_run_dir=''):
        import tkinter as tk
        from tkinter import ttk
        self.tk, self.ttk, self.window = tk, ttk, window
        self.jobs, self.events = queue.Queue(), queue.Queue()
        self.closing = threading.Event()
        self.state_lock = threading.Lock()
        self.latest = None
        self.ready = self.pending = self.environment_ready = False
        self.failed = False
        self.entries, self.cases, self.model_entries = [], [], []
        self.studies = []
        self.run_root = None
        self.initial_run_dir = initial_run_dir
        self.buttons = []
        self.rates, self.rate_counts = [0.] * 5, {}
        self.rate_stamp = time.perf_counter()
        self.last_point = None
        window.title('CSI 사람 없음 + 9지점 + p05 앉기 실시간 추론')
        window.geometry('1080x840')
        window.minsize(960, 650)
        window.protocol('WM_DELETE_WINDOW', self.close)
        outer = ttk.Frame(window)
        outer.pack(fill='both', expand=True)
        scroll = tk.Canvas(outer, highlightthickness=0)
        bar = ttk.Scrollbar(outer, orient='vertical', command=scroll.yview)
        scroll.configure(yscrollcommand=bar.set)
        bar.pack(side='right', fill='y')
        scroll.pack(side='left', fill='both', expand=True)
        body = ttk.Frame(scroll, padding=16)
        content = scroll.create_window((0, 0), window=body, anchor='nw')
        body.bind('<Configure>', lambda _: scroll.configure(scrollregion=scroll.bbox('all')))
        scroll.bind('<Configure>', lambda ev: scroll.itemconfigure(content, width=ev.width))
        window.bind('<MouseWheel>', lambda ev: scroll.yview_scroll(-int(ev.delta / 120), 'units'))
        ttk.Label(body, text='CSI 사람 없음 + 9지점 + p05 앉기(p10) · 실시간 모델 비교', font=('맑은 고딕', 18, 'bold')).pack(anchor='w')
        ttk.Label(body, text='2초 입력 · 0.5초마다 추론 · 저장 모델 사용', padding=(0, 4)).pack(anchor='w')
        self.environment = tk.StringVar(value='Python 3.14 실행 환경 확인 중…')
        ttk.Label(body, textvariable=self.environment, wraplength=990).pack(anchor='w', pady=(0, 10))

        run_row = ttk.Frame(body)
        run_row.pack(fill='x', pady=5)
        ttk.Label(run_row, text='학습 결과 폴더 / 모델 파일').pack(side='left')
        self.run_path = ttk.Entry(run_row, width=60)
        self.run_path.insert(0, initial_run_dir)
        self.run_path.pack(side='left', fill='x', expand=True, padx=6)
        self.folder_button = ttk.Button(run_row, text='폴더 선택', command=self.choose_run, state='disabled')
        self.folder_button.pack(side='left')
        self.file_button = ttk.Button(run_row, text='모델 선택', command=self.choose_model_file, state='disabled')
        self.file_button.pack(side='left', padx=4)
        self.load_button = ttk.Button(run_row, text='불러오기', command=self.load_run, state='disabled')
        self.load_button.pack(side='left')

        model_row = ttk.Frame(body)
        model_row.pack(fill='x')
        self.study = self.combo(model_row, '학습 묶음', 20)
        self.case = self.combo(model_row, '학습 사람', 27)
        self.family = self.combo(model_row, '분류기', 22)
        self.study.bind('<<ComboboxSelected>>', self.populate_cases)
        self.case.bind('<<ComboboxSelected>>', self.populate_models)
        self.family.bind('<<ComboboxSelected>>', self.selection_changed)
        self.selection = tk.StringVar(value='모델 확인 대기')
        ttk.Label(body, textvariable=self.selection, wraplength=990).pack(anchor='w', pady=5)
        ttk.Label(body, text='★는 원래 검증에서 선정한 모델입니다. 목록 변경 후 선택 모델 적용을 누르세요.').pack(anchor='w')

        port_row = ttk.Frame(body)
        port_row.pack(fill='x', pady=(12, 4))
        ttk.Label(port_row, text='TX COM').pack(side='left')
        self.port = ttk.Combobox(port_row, width=12)
        self.port.set(initial_port)
        self.port.pack(side='left', padx=(6, 16))
        ttk.Label(port_row, text='baud').pack(side='left')
        self.baud = ttk.Entry(port_row, width=9)
        self.baud.insert(0, '115200')
        self.baud.pack(side='left', padx=6)
        self.scan_button = ttk.Button(port_row, text='COM 검색', command=self.scan_ports, state='disabled')
        self.scan_button.pack(side='left', padx=3)
        self.button(port_row, '연결', self.connect)
        self.button(port_row, '연결 해제', lambda: self.submit('disconnect'))
        commands = ttk.Frame(body)
        commands.pack(fill='x', pady=3)
        for label, cmd in [('Status', 'status'), ('TX Run', 'mode run'), ('TX Wait', 'mode wait')]:
            self.button(commands, label, lambda c=cmd: self.submit('command', command=c))
        self.confirm = tk.BooleanVar(value=False)
        ttk.Checkbutton(body, variable=self.confirm,
                        text='학습 당시 배치·RX 번호 순서·HT40 설정을 확인했습니다').pack(anchor='w', pady=6)
        actions = ttk.Frame(body)
        actions.pack(fill='x')
        self.button(actions, '선택 모델 적용', self.apply_model)
        self.button(actions, '추론 시작', lambda: self.submit(
            'start_inference', model_id=self.selected_id(), confirmed=self.confirm.get()))
        self.button(actions, '추론 정지', lambda: self.submit('stop_inference'))
        ttk.Label(body, text='처음에는 모델 선택 → 연결. 선택 모델 적용은 연결 후 모델을 바꿀 때 사용합니다.').pack(anchor='w', pady=4)
        self.message = tk.StringVar(value='환경 준비 중. COM 검색은 필요할 때만 누르세요.')
        self.message_label = ttk.Label(body, textvariable=self.message, wraplength=990, foreground='#17614d')
        self.message_label.pack(anchor='w', pady=8)
        self.status = tk.StringVar(value='연결 전')
        ttk.Label(body, textvariable=self.status, wraplength=990, justify='left').pack(anchor='w')

        results = ttk.Frame(body)
        results.pack(fill='x', pady=8)
        left, right = ttk.Frame(results), ttk.Frame(results)
        left.pack(side='left', anchor='n')
        right.pack(side='left', fill='both', expand=True, padx=(20, 0))
        self.prediction = tk.StringVar(value='입력 부족 / 대기')
        ttk.Label(left, textvariable=self.prediction, font=('맑은 고딕', 15, 'bold'),
                  wraplength=330, justify='left').pack(anchor='w')
        self.map = tk.Canvas(left, width=330, height=310, background='white', highlightthickness=0)
        self.map.pack()
        self.draw_map(None)
        self.radio = tk.StringVar(value='TX: 상태 대기')
        ttk.Label(right, textvariable=self.radio, wraplength=590).pack(anchor='w', pady=10)
        cols = ('rx', 'mac', 'live', 'rate', 'length')
        self.nodes = ttk.Treeview(right, columns=cols, show='headings', height=5)
        for name, title, width in zip(cols, ('RX', 'MAC', 'Live', '수신 행/초', 'CSI 바이트'), (40, 170, 50, 90, 90)):
            self.nodes.heading(name, text=title)
            self.nodes.column(name, width=width, anchor='center', stretch=(name == 'mac'))
        self.nodes.pack(fill='x')
        ttk.Label(right, text='CSI는 RX당 384바이트가 필요합니다.\n학습 당시 RX 번호와 실물 위치는 현장에서 확인하세요.',
                  wraplength=590, justify='left').pack(anchor='w', pady=10)

        trial = ttk.LabelFrame(body, text='사람 없음 / 한 지점 시험 기록', padding=10)
        trial.pack(fill='x', pady=(0, 8))
        inputs = ttk.Frame(trial)
        inputs.pack(fill='x')
        self.truth = self.combo(inputs, '실제 상태', 20)
        self.truth.configure(values=['미지정 / 관찰만'] + list(TRUTH_CHOICES) + [EMPTY_CHOICE])
        self.truth.current(0)
        ttk.Label(inputs, text='시험자').pack(side='left', padx=(10, 4))
        self.subject = ttk.Entry(inputs, width=18)
        self.subject.pack(side='left')
        ttk.Label(inputs, text='기록 초').pack(side='left', padx=(10, 4))
        self.seconds = ttk.Entry(inputs, width=7)
        self.seconds.insert(0, '30')
        self.seconds.pack(side='left')
        row = ttk.Frame(trial)
        row.pack(fill='x', pady=7)
        self.raw = tk.BooleanVar(value=False)
        self.raw_check = ttk.Checkbutton(row, text='원본 CSI도 저장', variable=self.raw)
        self.raw_check.pack(side='left', padx=(0, 12))
        self.button(row, '시험 기록 시작', self.start_trial)
        self.button(row, '시험 기록 종료', lambda: self.submit('finish_trial'))
        self.button(row, '저장 폴더 열기', self.open_results)
        self.trial_status = tk.StringVar(value='기록 대기 · 학습 때와 같은 수집 조건으로 시험하세요')
        ttk.Label(trial, textvariable=self.trial_status, wraplength=950, justify='left').pack(anchor='w')
        ttk.Label(body, text='empty는 유효한 CSI를 모델이 사람 없음으로 분류한 결과입니다. 수신 중단은 입력 부족/대기로 표시합니다.\n좌표는 수집 지점의 대표값이며, 학습하지 않은 위치·환경에서는 오분류할 수 있습니다.',
                  wraplength=990).pack(anchor='w')
        self.worker = threading.Thread(target=self.work, name='csi-desktop-control', daemon=True)
        self.worker.start()
        window.after(100, self.poll)

    def combo(self, parent, label, width):
        self.ttk.Label(parent, text=label).pack(side='left', padx=(0, 5))
        widget = self.ttk.Combobox(parent, width=width, state='readonly')
        widget.pack(side='left', padx=(0, 12))
        return widget

    def button(self, parent, label, action):
        widget = self.ttk.Button(parent, text=label, command=lambda: self.invoke(action), state='disabled')
        widget.pack(side='left', padx=(0, 6))
        self.buttons.append(widget)
        return widget

    def invoke(self, action):
        try:
            action()
        except Exception as exc:
            self.show_message(str(exc), error=True)

    def show_message(self, text, error=False):
        self.message.set(text)
        self.message_label.configure(foreground='#b91c1c' if error else '#17614d')

    def enable_actions(self):
        state = 'normal' if self.ready and not self.pending and not self.closing.is_set() else 'disabled'
        for button in self.buttons:
            button.configure(state=state)
        can_load = 'normal' if self.environment_ready and not self.pending and not self.closing.is_set() else 'disabled'
        for button in (self.folder_button, self.file_button, self.load_button):
            button.configure(state=can_load)
        for widget in (self.study, self.case, self.family):
            widget.configure(state='readonly' if state == 'normal' else 'disabled')

    def choose_run(self):
        from tkinter import filedialog
        path = filedialog.askdirectory(title='노트북에서 만든 학습 결과 폴더 선택')
        if path:
            self.run_path.delete(0, 'end')
            self.run_path.insert(0, path)
            self.load_run()

    def choose_model_file(self):
        from tkinter import filedialog
        path = filedialog.askopenfilename(title='학습 결과의 모델 선택', filetypes=[('학습 모델', '*.joblib')])
        if path:
            self.run_path.delete(0, 'end')
            self.run_path.insert(0, path)
            self.load_run()

    def load_run(self):
        if not self.environment_ready or self.pending or self.closing.is_set():
            return
        self.pending = True
        self.enable_actions()
        self.show_message('학습 결과와 모델 해시 확인 중…')
        self.jobs.put(('load_run', {'path': self.run_path.get().strip()}))

    def populate_cases(self, event=None, preferred=None):
        if not self.entries or self.study.current() < 0:
            return
        study = self.studies[self.study.current()]
        self.cases = list(dict.fromkeys(e.get('case', 'custom') for e in self.entries if e.get('study', 'local_training') == study))
        self.case.configure(values=[next((e.get('case_label', key) for e in self.entries
            if e.get('study', 'local_training') == study and e.get('case', 'custom') == key), key) for key in self.cases])
        if self.cases:
            self.case.current(self.cases.index(preferred) if preferred in self.cases else 0)
        self.populate_models()

    def populate_models(self, event=None):
        if not self.entries or self.study.current() < 0 or self.case.current() < 0:
            return
        study = self.studies[self.study.current()]
        case = self.cases[self.case.current()]
        self.model_entries = [e for e in self.entries if e.get('study', 'local_training') == study and e.get('case', 'custom') == case]
        self.family.configure(values=[e['family'].upper() + ' / ' + e.get('variant', 'amp_rssi') + (' ★ 검증 선정' if e.get('selected') else '') for e in self.model_entries])
        if self.model_entries:
            self.family.current(next((i for i, e in enumerate(self.model_entries) if e.get('selected')), 0))
            self.selection_changed()

    def selected_id(self):
        if not self.model_entries or self.family.current() < 0:
            raise RuntimeError('모델 확인이 끝날 때까지 기다려주세요.')
        return self.model_entries[self.family.current()]['id']

    def selection_changed(self, event=None):
        entry = self.model_entries[self.family.current()]
        path = self.run_root / entry['path'] if self.run_root else entry['path']
        self.selection.set('선택: ' + self.selected_id() + '\n' + str(path))

    def submit(self, action, **kwargs):
        if not self.ready or self.pending or self.closing.is_set():
            return
        self.pending = True
        self.enable_actions()
        self.show_message('요청 처리 중…')
        self.jobs.put((action, kwargs))

    def connect(self):
        self.rates, self.rate_counts = [0.] * 5, {}
        self.rate_stamp = time.perf_counter()
        self.submit('connect', model_id=self.selected_id(), port=self.port.get(), baudrate=int(self.baud.get()))

    def apply_model(self):
        self.confirm.set(False)
        self.submit('apply_model', model_id=self.selected_id())

    def start_trial(self):
        truth = truth_label(self.truth.get())
        self.submit('start_trial', model_id=self.selected_id(), confirmed=self.confirm.get(),
                    truth=truth, seconds=float(self.seconds.get()), subject=self.subject.get(), raw=self.raw.get())

    def open_results(self):
        folder = self.run_root / 'live_results' if self.run_root else ROOT / 'live_results'
        if not folder.is_dir():
            raise RuntimeError('아직 저장된 시험 기록이 없습니다.')
        os.startfile(str(folder))

    def draw_map(self, point):
        self.map.delete('all')
        self.map.create_text(165, 18, text='RX 벽 쪽', font=('맑은 고딕', 11))
        self.map.create_rectangle(45, 35, 285, 275, fill='#f3f7fb', outline='#bd4769', width=2)
        for name, (x, y) in POINTS.items():
            cx, cy = 45 + x * 240 / 180, 35 + y * 240 / 180
            colour = '#008594' if name == point else '#7190b0'
            if name in SEATED_LABELS:
                # Seated class shares a standing point's coordinate: outer ring + caption.
                ring = colour if name == point else '#c5d2df'
                self.map.create_oval(cx - 30, cy - 30, cx + 30, cy + 30, fill='', outline=ring, width=4)
                self.map.create_text(cx, cy + 40, text=f'{name} 앉기', fill=ring, font=('맑은 고딕', 9, 'bold'))
                continue
            self.map.create_oval(cx - 22, cy - 22, cx + 22, cy + 22, fill=colour, outline=colour)
            self.map.create_text(cx, cy, text=name, fill='white', font=('맑은 고딕', 11, 'bold'))
        self.map.create_text(165, 296, text='TX / 카메라 쪽', font=('맑은 고딕', 11))

    def scan_ports(self):
        self.scan_button.configure(state='disabled')
        self.show_message('COM 목록 검색 중. 이미 아는 포트는 검색 완료를 기다리지 않고 직접 입력할 수 있습니다.')
        def scan():
            try:
                from serial_input import list_ports
                self.events.put(('ports', list_ports()))
            except Exception as exc:
                self.events.put(('port_error', str(exc)))
        threading.Thread(target=scan, name='csi-port-discovery', daemon=True).start()

    def work(self):
        controller = None
        try:
            from live_catalog import check_environment
            environment = check_environment()
            self.events.put(('environment_ready', environment))
            while not self.closing.is_set():
                try:
                    action, kwargs = self.jobs.get(timeout=.2)
                except queue.Empty:
                    action = None
                if self.closing.is_set():
                    break
                outcome = None
                if action is not None:
                    try:
                        if action == 'load_run':
                            root, catalog, chosen, verified = inspect_run_selection(kwargs['path'])
                            from desktop_controller import DesktopController
                            candidate = DesktopController(root, catalog=catalog)
                            if controller is not None:
                                controller.close()
                            controller = candidate
                            with self.state_lock:
                                self.latest = None
                            self.events.put(('ready', dict(entries=catalog.entries, default=chosen,
                                environment=environment, verified=verified, run_root=str(root))))
                            outcome = ('학습 결과 준비 완료. TX 데이터 COM 번호를 입력하고 연결하세요.', False)
                        else:
                            if controller is None:
                                raise RuntimeError('학습 결과 폴더를 먼저 불러오세요.')
                            outcome = (getattr(controller, action)(**kwargs), False)
                    except Exception as exc:
                        traceback.print_exc()
                        outcome = (str(exc), True)
                if controller is not None:
                    try:
                        snapshot = controller.snapshot()
                        with self.state_lock:
                            self.latest = snapshot
                    except Exception as exc:
                        traceback.print_exc()
                        self.events.put(('error', '상태/기록 갱신 오류: ' + str(exc)))
                        controller.disconnect()
                if outcome is not None:
                    self.events.put(('done', outcome))
        except Exception as exc:
            traceback.print_exc()
            self.events.put(('fatal', '준비 오류: ' + str(exc) + '\n이 폴더의 run_live_gui.cmd로 실행했는지 확인하세요.'))
        finally:
            if controller is not None:
                try:
                    controller.close()
                except Exception as exc:
                    traceback.print_exc()
                    self.events.put(('shutdown_error', '종료 중 기록/연결 오류: ' + str(exc)))

    def poll(self):
        try:
            self.drain_events()
            if self.closing.is_set():
                if not self.worker.is_alive():
                    self.window.destroy()
                    return
            else:
                with self.state_lock:
                    snapshot = self.latest
                if snapshot is not None:
                    self.render(snapshot)
        except Exception as exc:
            traceback.print_exc()
            self.show_message('화면 갱신 오류: ' + str(exc), error=True)
        self.window.after(100, self.poll)

    def drain_events(self):
        while True:
            try:
                kind, value = self.events.get_nowait()
            except queue.Empty:
                return
            if kind == 'shutdown_error':
                self.failed = True
                self.show_message(value, error=True)
                continue
            if self.closing.is_set():
                continue
            if kind == 'environment_ready':
                self.environment_ready = True
                self.environment.set(f'Python {value["python"].split()[0]} · {value["executable"]}')
                self.enable_actions()
                self.scan_button.configure(state='normal')
                self.show_message('학습 노트북에서 만든 결과 폴더 또는 그 안의 모델 파일을 선택하세요.')
                if self.initial_run_dir:
                    self.load_run()
            elif kind == 'ready':
                self.entries = value['entries']
                self.run_root = Path(value['run_root'])
                self.run_path.delete(0, 'end')
                self.run_path.insert(0, str(self.run_root))
                default = next(e for e in self.entries if e['id'] == value['default'])
                self.studies = list(dict.fromkeys(e.get('study', 'local_training') for e in self.entries))
                self.study.configure(values=[next((e.get('study_label', key) for e in self.entries
                    if e.get('study', 'local_training') == key), key) for key in self.studies])
                self.study.current(self.studies.index(default.get('study', 'local_training')))
                self.populate_cases(preferred=default.get('case', 'custom'))
                self.family.current(next(i for i, e in enumerate(self.model_entries) if e['id'] == default['id']))
                self.selection_changed()
                self.confirm.set(False)
                self.rates, self.rate_counts = [0.] * 5, {}
                self.rate_stamp = time.perf_counter()
                env = value['environment']
                self.environment.set(f'Python {env["python"].split()[0]} · 모델 {len(self.entries)}개 해시 확인 완료\n{env["executable"]}')
                self.ready = True
                self.scan_button.configure(state='normal')
                self.enable_actions()
            elif kind == 'done':
                self.pending = False
                self.enable_actions()
                self.show_message(value[0], error=value[1])
            elif kind in ('ports', 'port_error'):
                self.scan_button.configure(state='normal' if self.environment_ready else 'disabled')
                if kind == 'ports':
                    self.port.configure(values=value)
                    self.show_message('검색된 COM: ' + (', '.join(value) if value else '없음. 포트 번호를 직접 입력할 수도 있습니다.'))
                else:
                    self.show_message('COM 검색 오류: ' + value, error=True)
            elif kind == 'fatal':
                self.failed = True
                self.ready = self.environment_ready = False
                with self.state_lock:
                    self.latest = None
                self.draw_map(None)
                self.last_point = None
                self.prediction.set('입력 대기')
                self.status.set('연결/추론 중지. 오류 메시지를 확인하세요.')
                self.enable_actions()
                self.scan_button.configure(state='disabled')
                self.environment.set('준비 실패 — 오류 메시지를 확인하세요.')
                self.show_message(value, error=True)
            elif kind == 'error':
                self.show_message(value, error=True)

    def render(self, snapshot):
        state, rec = snapshot['state'], snapshot['recording']
        serial = state.get('serial', {})
        counts = state.get('counts', {})
        active = snapshot['active_model']
        self.status.set(
            '적용 모델: ' + (active['id'] if active else '없음') + '\n'
            '상태: ' + state.get('reason', '') + '\n'
            f'유효 주기 {counts.get("valid_cycles", 0)} · 거부 주기 {counts.get("rejected_cycles", 0)}'
            f' · 부족 창 {counts.get("short_windows", 0)} · 추론 {counts.get("predictions", 0)}\n'
            f'시각/순서 거부 {counts.get("discontinuities", 0)} · 처리량 초과 {counts.get("queue_overflows", 0)}'
            f' · 추론 오류 {counts.get("inference_errors", 0)} · 기록 오류 {sum(state.get("callback_errors", {}).values())}\n'
            '거부 사유: ' + str(state.get('reject_reasons', {})))
        pred = visible_prediction(state, self.pending, time.perf_counter_ns())
        point = pred['point_id'] if pred else None
        if point != self.last_point:
            self.draw_map(point)
            self.last_point = point
        self.prediction.set(prediction_text(pred))
        received = serial.get('received_rows_by_rx', {})
        now = time.perf_counter()
        if now - self.rate_stamp >= 1:
            self.rates = [max(0, received.get(i, 0) - self.rate_counts.get(i, 0)) / (now - self.rate_stamp) for i in range(5)]
            self.rate_counts = dict(received)
            self.rate_stamp = now
        status = serial.get('status') or {}
        self.radio.set(f'TX: {status.get("mode", "대기")} · 채널 {status.get("wifi_channel", "?")} / {status.get("second_channel", "?")}')
        mapped = {n.get('saved_order') if n.get('saved') else n.get('slot_index'): n for n in status.get('nodes', [])}
        lengths = serial.get('csi_len_by_rx', {})
        for i in range(5):
            node = mapped.get(i, {})
            values = (i, node.get('mac', '대기'), node.get('live', '대기'), f'{self.rates[i]:.1f}', lengths.get(i, '대기'))
            if self.nodes.exists(str(i)):
                self.nodes.item(str(i), values=values)
            else:
                self.nodes.insert('', 'end', iid=str(i), values=values)
        if rec['active']:
            self.trial_status.set(f'기록 중 · {rec["remaining_s"]:.1f}초 남음 · 저장 예측 {rec["predictions"]}개\n{rec["folder"]}')
        elif snapshot['result']:
            result = snapshot['result']
            score = f'{result["point_recall"]:.1%}' if result['point_recall'] is not None else '정답 또는 예측 없음'
            outcome = '기록 실패' if result.get('error') else '기록 종료'
            self.trial_status.set(f'{outcome} · 해당 클래스 재현율 {score} · 예측 {result["predictions"]}개\n'
                                  f'{result["folder"]}\n{result.get("error") or "0.5초 간격 예측은 서로 겹칩니다. 전체 11클래스 정확도와 구분하세요."}')
        self.truth.configure(state='disabled' if rec['active'] else 'readonly')
        for widget in (self.subject, self.seconds, self.raw_check):
            widget.configure(state='disabled' if rec['active'] else 'normal')

    def close(self):
        if self.closing.is_set():
            return
        self.closing.set()
        self.enable_actions()
        self.scan_button.configure(state='disabled')
        self.show_message('기록 파일과 USB 연결을 정리하는 중입니다…')


def main():
    parser = argparse.ArgumentParser(description='CSI live desktop GUI (Python 3.14)' )
    parser.add_argument('--port', default='', help='Pre-fill the known TX COM port; does not connect automatically')
    parser.add_argument('--run-dir', default='', help='Training run folder or catalogued joblib; no automatic COM connection')
    args = parser.parse_args()
    print('Python:', sys.executable, flush=True)
    print('Project:', ROOT, flush=True)
    try:
        import tkinter as tk
        window = tk.Tk()
        app = DesktopApp(window, initial_port=args.port, initial_run_dir=args.run_dir)
        try:
            window.mainloop()
        finally:
            app.closing.set()
            app.worker.join(timeout=5)
        return 1 if app.failed else 0
    except Exception:
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
