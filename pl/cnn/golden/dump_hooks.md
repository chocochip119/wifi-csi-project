# G-01 관측 지점과 덤프 계약

원본: `wifi-csi-pose-main/HLS/pl_accel_v6/full_pose.cpp`.
아래 행 번호는 G-01 시작 시 SHA-256 `c2c45b9db1d32fde9be53a48a150a77725a042ed13bca0bd13c9f2ffa2f2da1c` 기준이다.
`src/original/`은 byte 동일 사본, `src/full_pose_instrumented.cpp`는 관측 사본이다.
[instrumentation.diff](src/instrumentation.diff)는 추가한 호출을 전부 보여 준다.

## Hook 위치

| 원본 위치 | 관측 시점 | 출력 |
|---|---|---|
| 666: encode_all_receivers_direct 직후 | 세 receiver Pool/flatten 완료, FC1 시작 전 | encoder_flat_i8.hex |
| 559: FC1 bias + acc0..3 직후 | requant 전에 signed int32 결과 보관 | fc1_acc_i32.hex |
| 315: linear_requant bias + acc0..1 직후 | OUT_DIM 128=FC2 / 24=FC3 | fc2/3_acc_i32.hex |
| 668: fc1_requant 직후 | GELU 전 | fc1_requant_i8.hex |
| 669: apply_head_gelu1 직후 | FC1 단계 완료 | fc1_gelu_i8.hex |
| 670: fc2_requant 직후 | GELU 전 | fc2_requant_i8.hex |
| 671: apply_head_gelu2 직후 | FC2 단계 완료 | fc2_gelu_i8.hex |
| 672: fc3_requant 직후 | 최종 INT8, float 변환 전 | fc3_i8.hex |
| 673: write_final_pose 직후 | 보관한 FC 누산 배열 출력 | 세 acc 파일 |
| golden_runner.cpp: full_pose_accel 반환 후 | 최종 float 배열 | pose_f32.txt / .hex |

hook은 값의 복사·출력만 한다. 텐서·weight·bias·scale·계산식에 쓰지 않는다.
각 누산값은 한번만 포착돼야 하며 누락/중복이면 실패한다. 현재 linear_requant 호출 두 종류에 맞춘 분기다.
네트워크 구조가 바뀌면 이 분기도 다시 검토해야 한다.
관측 사본은 프로세스당 INFER 1회 사용한다. 스크립트 반복 실행은 새 프로세스라 상태가 공유되지 않는다.

## 파일 형식

ASCII 소문자 hex, 접두사 `0x`/주소/header/주석 없이 한 요소당 한 줄, LF 줄바꿈.
INT8은 signed 값의 2의 보수 비트다. 예: `f8`은 −8이다.
int32는 8자리 2의 보수 비트이며 누산값은 **bias 포함, requant 전**이다.

| 파일 | 요소 수 × 폭 | 의미상 크기 | 텍스트 크기 | 순서 |
|---|---:|---:|---:|---|
| input_i8.bin | 11,520 × 8 | 11,520 B | binary 11,520 B | `[channel][h][w]` |
| input_i8.hex | 11,520 × 8 | 11,520 B | 34,560 B | bin과 동일 |
| encoder_flat_i8.hex | 3,072 × 8 | 3,072 B | 9,216 B | `[rx][oc][oh][ow]` |
| encoder_flat_u64.hex | 384 × 64 | 3,072 B | 6,528 B | 낮은 byte 주소가 word 하위 8 bit |
| fc1_requant_i8.hex | 128 × 8 | 128 B | 384 B | 출력 neuron 0..127 |
| fc1_gelu_i8.hex | 128 × 8 | 128 B | 384 B | 같은 neuron 순서 |
| fc2_requant_i8.hex | 128 × 8 | 128 B | 384 B | 출력 neuron 0..127 |
| fc2_gelu_i8.hex | 128 × 8 | 128 B | 384 B | 같은 neuron 순서 |
| fc3_i8.hex | 24 × 8 | 24 B | 72 B | 출력 0..23, RTL pose byte 순서 |
| fc1_acc_i32.hex | 128 × 32 | 512 B | 1,152 B | 출력 neuron 0..127 |
| fc2_acc_i32.hex | 128 × 32 | 512 B | 1,152 B | 출력 neuron 0..127 |
| fc3_acc_i32.hex | 24 × 32 | 96 B | 216 B | 출력 0..23 |
| pose_f32.hex | 24 × 32 | 96 B | 216 B | IEEE754 float32 비트 8자리 |
| pose_f32.txt | float32 24개 | 96 B 상당 | 가변, manifest 참조 | 순서 동일, 9자리 유효 숫자 |

`.hex`는 각각 맞는 폭의 배열에 `$readmemh`로 읽을 수 있다. INT8 파일을 64-bit 배열로 직접 읽으면 패킹이 되지 않는다.
Encoder 64-bit 포트 대조에는 `encoder_flat_u64.hex`를 사용한다.
입력 64-bit 공급은 `word[k] = Σ input_byte[8k+b] << (8b)`로 묶는다.
float 텍스트보다 `.hex`가 비트 정확 대조에 적합하다. RTL의 DDR 출력은 float 96 B가 아닌 **INT8 24 B**다.

## Flatten 배치 근거

원본 C++ 470행:

```cpp
int index = (c * POOL_H + oh) * POOL_W + ow;
flatten_segment[index] = sat_int8(pooled);
```

세 bank는 `flatten_banks[rx][index]`, read_banked_flatten(534~536행)은 전역 index를 1,024로 나눠 rx를 선택한다.
따라서 전체 byte 주소는 다음과 같다:

```text
n = ((rx * 32 + oc) * 8 + oh) * 4 + ow
word = n / 8 = rx * 128 + oc * 4 + floor(oh / 2)
lane = n % 8 = (oh % 2) * 4 + ow
word_data[8*lane +: 8] = byte[n]
```

명세 07_Flatten r12와 일치한다. Pool.v 135행의
`{st_rx, st_pass, idx_r4[5:2], st_oh, idx_r4[1:0]}`는 `{rx, oc[4:0], oh, ow}`이므로 같은 byte 주소다.
146행은 `res_mem[wr_addr[11:3]][8*k +: 8]`에 쓰므로 byte lane도 같다.
최종 유효 word는 0..383이고 384..511은 생성하지 않는다.
스크립트는 모든 `(rx,oc,oh,ow)` 3,072개에 대해 위 식을 다시 계산해 패킹을 검증한다.

## 증거의 범위

현재 샘플에서 원본 기대값과 float32 24개가 정확히 같다. 지정 blob/input마다 비관측 C++와 관측 C++를 다시 비교한다.
이것은 실행한 사례에서 관측 추가가 최종 결과를 바꾸지 않았다는 근거다. 모든 가능한 모델의 형식적 등가성 증명은 아니다.
또한 이 파일들이 생성됐다는 사실만으로 RTL의 Encoder/FC 계산이 맞는다고 결론내리지 않는다. 그 대조는 G-02/F 단계다.
