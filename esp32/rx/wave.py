import serial
import re
import numpy as np
import matplotlib.pyplot as plt

# =========================
# 설정
# =========================
PORT = "COM5"
BAUD = 921600

# =========================
# Serial 연결
# =========================
ser = serial.Serial(PORT, BAUD, timeout=1)

print(f"{PORT} 연결 완료")
print("CSI 데이터 수신 대기 중...")

# =========================
# 그래프 설정
# =========================
plt.ion()

fig, ax = plt.subplots(figsize=(12, 5))
graph, = ax.plot([], [])

ax.set_title("Real-Time CSI Amplitude")
ax.set_xlabel("CSI Index")
ax.set_ylabel("Amplitude")
ax.grid(True)

plt.show(block=False)
plt.pause(0.1)

try:
    while True:

        line = ser.readline().decode(
            "utf-8",
            errors="ignore"
        ).strip()

        # GUI 계속 갱신
        plt.pause(0.01)

        if "CSI_DATA" not in line:
            continue

        print("CSI 수신!")

        # "[ ... ]" 부분 추출
        match = re.search(r'"\[(.*?)\]"', line)

        if not match:
            print("CSI 배열 추출 실패")
            continue

        csi = np.fromstring(
            match.group(1),
            sep=",",
            dtype=np.int16
        )

        if len(csi) < 2:
            continue

        # [Imag, Real, Imag, Real, ...]
        imag = csi[0::2]
        real = csi[1::2]

        amplitude = np.sqrt(
            real.astype(float) ** 2 +
            imag.astype(float) ** 2
        )

        x = np.arange(len(amplitude))

        graph.set_data(x, amplitude)

        ax.set_xlim(0, len(amplitude) - 1)
        ax.set_ylim(0, 100) 

        fig.canvas.draw_idle()
        fig.canvas.flush_events()

except KeyboardInterrupt:
    print("\n종료")

finally:
    ser.close()