# 기존 RX5 보드 시험 벡터

이 디렉터리는 과거 통합 시험의 blob·입력·기대 출력입니다. 최종 학습 모델로 표시하지 않습니다.

| 파일 | 크기 | 용도 |
|---|---:|---|
| `blob_rx5_test.bin` | 685,136 bytes | RX5 v2 시험 가중치/LUT/scale |
| `input_rx5_test.bin` | 19,200 bytes | 한 윈도우의 INT8 입력 |
| `pose_expected.bin` | 24 bytes | 과거 RTL/반올림 기준 기대 출력 |
| [pose_expected.txt](pose_expected.txt) | 텍스트 | 과거 기대 출력과 scale 설명 |

## 최신 반올림과의 차이

PR #29에서 정수 규칙을 nearest, halfway away from zero로 통일했습니다. 같은 blob/입력으로 새 팀 Python과 전체 RTL을 비교한 결과, 기존 `pose_expected.bin`과 **15/24 bytes가 다릅니다**. 예를 들어 첫 좌표는 과거 83, 새 기준 84입니다. 따라서 이 기대 출력으로 최신 RTL의 bit-exact 통과를 판단하면 안 됩니다.

기존 파일은 기록으로 보존합니다. 새 반올림/최종 가중치에는 [Colab v5 및 INT8 계약](../../ml/pose/INT8.md)으로 golden을 다시 생성하고 같은 모델·input/output scale·새 bitstream의 보드 결과와 비교하세요.

## PetaLinux에 함께 설치

기본 `install_app.sh PROJECT`는 recipe의 바이너리 설치를 활성화하지 않습니다. 해당 하드웨어/규칙에서 검증한 세 파일을 함께 넣은 디렉터리가 있을 때만 다음 형식으로 명시합니다. `ps/`에서 실행합니다.

```bash
bash petalinux/install_app.sh /path/to/petalinux-project /path/to/verified-vectors
```

recipe가 요구하는 이름은 `blob_rx5_test.bin`, `input_rx5_test.bin`, `pose_expected.bin`입니다. v5 golden 파일은 이름이 다르므로 원본 export를 보존한 채 검증용 디렉터리에서 해당 이름으로 준비해야 합니다. `pose_cnn_rx5_board_test`는 기존 scale `0x3BD997A8`을 별도로 검사하므로 임의 최종 모델에 그대로 사용하지 않습니다. 최종 모델 배포는 [PS README](../README.md)와 [통합 실행](../../docs/bringup.md)을 참고하세요.
