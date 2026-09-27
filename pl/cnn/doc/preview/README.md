# 도면 배치 미리보기

2026-09-24 검수 보완 후 현재 `../pose_cnn_ctrl_fsm.drawio`에서 `layout_p1.png`부터 `layout_p4.png`까지 다시 생성했다. FC 상태 박스의 `fc_sel` 표기 제거와 INFER 페이지 하단의 샘플링 조건 설명을 반영했다.

이 PNG는 XML 좌표를 Python/Pillow로 그린 배치 점검용 미리보기다. 실제 draw.io 앱의 렌더링이나 스크린샷이 아니며 글꼴·줄바꿈·점선 표현이 다를 수 있다. 편집 원본은 `.drawio` 파일이다.

프로젝트 루트에서 재생성:

```powershell
python cnn_rtl/doc/render_layout_preview.py
```

Python 환경에 Pillow가 필요하다.
