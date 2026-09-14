import serial
import time

ser = serial.Serial("COM5", 921600, timeout=1)

# 포트 열면서 ESP32가 리셋될 수 있으니 잠깐 기다림
time.sleep(2)

print("COM5 수신 시작")

try:
    while True:
        data = ser.readline()

        if data:
            print(data.decode("utf-8", errors="ignore").strip())

except KeyboardInterrupt:
    pass

finally:
    ser.close()