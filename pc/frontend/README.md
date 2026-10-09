# WiSensing PC Frontend

Three.js/Vite 기반 위치·12관절 시각화 UI입니다. 실제 PS/FPGA 통신과 위치 추론은 PC Backend에서 수행합니다.

## 실행

저장소 루트에서 Windows PowerShell:

```powershell
cd pc\frontend
npm ci
npm run dev
```

브라우저:
- 시연: http://localhost:5173/
- 실제 연결 상태 및 RX 확인: http://localhost:5173/integration.html

별도 터미널에서 Backend를 실행합니다. 둘 중 한 모드만 선택합니다:

```powershell
# UI 테스트 전용 (실제 하드웨어/위치 정확도 검증 아님)
python pc\backend\run_backend.py --fake

# 실제 Zybo: 주소는 보드의 실제 IP로 변경
.\scripts\start_backend_real.ps1 -PsIp 192.168.10.2
```

Frontend는 기본적으로 같은 호스트의 Backend HTTP 8000과 WebSocket /ws를 이용합니다.
Vite WebSocket 연결 주소는 VITE_BACKEND_WS_URL 환경 변수로 설정할 수 있습니다(변경 후 Vite 재시작).
진단 페이지는 다음처럼 다른 Backend 주소를 지정할 수 있습니다:

```text
http://localhost:5173/integration.html?backend=http%3A%2F%2F192.168.10.100%3A8080
```

## 로컬 3D 캐릭터 파일

UI는 /public/models/Male01.gltf, Male02.gltf, Female01.gltf, Female02.gltf를 로드합니다.
해당 모델 및 텍스처는 배포 라이선스가 확인되지 않아 GitHub 저장소에 포함되지 않습니다.
사용 권한이 있는 모델과 그 종속 텍스처를 직접 pc/frontend/public/models/에 배치해야 캐릭터가 표시됩니다.

## 실제 RX 배치 확인

1. Zybo의 pose_cnn_rx5_live가 TCP 5000(CSI/STATUS), 5001(Pose)를 제공해야 합니다.
2. integration.html에서 RX0~RX4의 MAC, 슬롯, saved order, 실제 물리 배치가 학습 당시와 맞는지 직접 확인합니다.
3. 체크 후 추론 시작을 누르면 화면에 표시된 RX 구성 서명(rx_signature)을 서버로 전송합니다.
4. Backend는 TCP 연결, 10초 이내 STATUS, RUN/RX5 connected/live/saved, 모델의 MAC/무선 설정, 확인 서명 일치를 검사합니다.
5. 이후 위치 엔진이 다음 STATUS를 재검증하여 추론을 시작합니다. 연결/배치가 바뀌면 다시 확인해야 합니다.

수동 API 사용 시 현재 서명을 조회한 다음 직접 대조하고 전달합니다:

```powershell
$layout = Invoke-RestMethod http://127.0.0.1:8000/api/rx-layout
$layout
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/api/confirm-rx-layout -ContentType 'application/json' -Body (@{rx_signature=$layout.rx_signature} | ConvertTo-Json)
```

## 기록 및 재생

```powershell
python pc\backend\tools\verify_wise_live.py --seconds 30 --require-pose --require-location --record recordings\live.jsonl
```

시연 페이지 오른쪽 상단의 **⚙ 설정 · 테스트** 버튼으로 위치·12관절 그림·3D 모션을 각각 독립적으로 제어할 수 있습니다.

| 설정 | LIVE | TEST / OFF |
|---|---|---|
| 위치 | Backend의 실제 P01~P10 분류 | P01~P09 수동 지정, P10 수동 앉기 |
| 12관절 그림 | FPGA의 실제 12관절 | 서기/팔 올리기/팔 벌리기/스쿼트/다리 들기 샘플 또는 숨김 |
| 3D 모션 | FPGA 관절을 캐릭터 리그에 반영 | 동일 샘플 모션 또는 기본 서기·앉기 |

- **P05와 P10은 같은 중앙 Zone 5**입니다. P05=서기, P10=앉기이며 양쪽 모두 12관절 표시·모션을 선택할 수 있습니다.
- P10은 모델에 Sitting/Sit/Chair 애니메이션이 있으면 이를 사용합니다. 없으면 제한적인 본 기반 앉기 포즈와 의자로 대체합니다. 모델마다 자연스러움·리깅 차이가 있어 화면 검증이 필요합니다.
- 실제 팔 추종 기본 ON / 실제 다리 추종 기본 OFF(2D에서 깊이를 정확히 알 수 없고 IK가 실험적). 설정창에서 켜거나 끕니다.
- 수동 위치 및 샘플 관절/모션은 프론트 화면만 바꾸며, FPGA/Backend 추론 데이터나 RX 확인 상태를 변경하지 않습니다.
- 모든 항목을 실제 추론으로 되돌릴 때는 **전체 LIVE** 버튼을 누릅니다.
- 저장한 JSON/JSONL 재생은 키보드 **O**, 실시간 복귀는 **B**, 관절 좌우 보정 모드는 **M**으로 유지됩니다.
실제 CNN 좌표는 INT8 × output_scale 결과인 model_output 좌표이므로 정규화된 0..1 좌표로 가정하지 않습니다.
p10은 중앙 앉기 위치 클래스로, 전용 앉기 3D 애니메이션은 아직 구현되지 않았습니다.

추가 자료: [통합 실행 순서](../../docs/bringup.md), [PS README](../../ps/README.md), [Backend README](../backend/README.md).
