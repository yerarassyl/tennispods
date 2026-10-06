"""
TennisPods — iOS AirPods Motion Collector
==========================================
Запуск: Pythonista 3 (iOS) или любая среда с доступом к CoreMotion.

Требования (Pythonista):
    pip install не нужен — CoreMotion встроен в Pythonista через objc_util.

Протокол:
    UDP пакет, 36 байт:
    [8 байт double: timestamp] [8 байт double: qw] [8 байт double: qx]
    [8 байт double: qy]        [8 байт double: qz]

    Также поддерживается WebSocket (asyncio + websockets), раскомментируй секцию.
"""

import struct
import socket
import time
import threading

# ──────────────────────────────────────────────
# НАСТРОЙКИ — измени перед запуском
# ──────────────────────────────────────────────
PC_IP   = "192.168.1.100"   # IP-адрес ПК в локальной сети
PC_PORT = 5005              # UDP-порт (должен совпадать с PC-визуализатором)
TARGET_HZ = 100             # Желаемая частота обновления (50 или 100 Гц)

PACKET_FORMAT = "!ddddd"    # Network byte order: timestamp + qw + qx + qy + qz
PACKET_SIZE   = struct.calcsize(PACKET_FORMAT)  # = 40 байт


# ──────────────────────────────────────────────
# CoreMotion через objc_util (Pythonista / PyObjC)
# ──────────────────────────────────────────────
def run_with_coremotion():
    """
    Основной поток сбора данных через CMHeadphoneMotionManager.
    Работает в Pythonista 3 на iOS.
    """
    from objc_util import ObjCClass, ObjCInstance, on_main_thread
    import ctypes

    CMHeadphoneMotionManager = ObjCClass("CMHeadphoneMotionManager")
    manager = CMHeadphoneMotionManager.new()

    if not manager.isDeviceMotionAvailable():
        print("[ERROR] CMHeadphoneMotionManager недоступен. "
              "Убедитесь, что AirPods подключены и разрешения выданы.")
        return

    # Интервал обновления в секундах
    interval = 1.0 / TARGET_HZ
    manager.setDeviceMotionUpdateInterval_(interval)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 65536)

    stop_event = threading.Event()
    packet_count = 0
    start_time   = time.time()

    def send_loop():
        nonlocal packet_count
        manager.startDeviceMotionUpdates()
        print(f"[INFO] Отправка на {PC_IP}:{PC_PORT} @ {TARGET_HZ} Гц")

        while not stop_event.is_set():
            motion = manager.deviceMotion()
            if motion is not None:
                att  = motion.attitude()
                quat = att.quaternion()      # CMQuaternion: w, x, y, z

                ts = time.time()
                qw = float(quat.w)
                qx = float(quat.x)
                qy = float(quat.y)
                qz = float(quat.z)

                payload = struct.pack(PACKET_FORMAT, ts, qw, qx, qy, qz)
                try:
                    sock.sendto(payload, (PC_IP, PC_PORT))
                    packet_count += 1
                except OSError as e:
                    print(f"[WARN] Ошибка отправки: {e}")

            time.sleep(interval)

        manager.stopDeviceMotionUpdates()
        sock.close()
        elapsed = time.time() - start_time
        print(f"[INFO] Завершено. Отправлено {packet_count} пакетов "
              f"за {elapsed:.1f}с ({packet_count/elapsed:.1f} Гц ср.)")

    t = threading.Thread(target=send_loop, daemon=True)
    t.start()

    try:
        print("[INFO] Работаю... Нажмите Ctrl+C для остановки.")
        while True:
            time.sleep(1.0)
            elapsed = time.time() - start_time
            if elapsed > 0:
                print(f"  → {packet_count} пакетов, "
                      f"{packet_count/elapsed:.1f} Гц ср.")
    except KeyboardInterrupt:
        print("[INFO] Остановка...")
        stop_event.set()
        t.join(timeout=2.0)


# ──────────────────────────────────────────────
# Симулятор (для тестирования без AirPods)
# ──────────────────────────────────────────────
def run_simulator():
    """
    Генерирует синтетические кватернионы для отладки ПК-клиента
    без реального устройства.
    """
    import math

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    interval = 1.0 / TARGET_HZ
    print(f"[SIM] Симуляция → {PC_IP}:{PC_PORT} @ {TARGET_HZ} Гц")

    t = 0.0
    try:
        while True:
            # Медленное вращение вокруг оси Z
            half_angle = 0.3 * math.sin(t * 0.5)
            qw = math.cos(half_angle)
            qx = 0.1 * math.sin(t * 0.3)
            qy = math.sin(half_angle)
            qz = 0.05 * math.cos(t * 0.7)

            # Нормализация
            norm = math.sqrt(qw**2 + qx**2 + qy**2 + qz**2)
            qw, qx, qy, qz = qw/norm, qx/norm, qy/norm, qz/norm

            payload = struct.pack(PACKET_FORMAT, time.time(), qw, qx, qy, qz)
            sock.sendto(payload, (PC_IP, PC_PORT))

            t += interval
            time.sleep(interval)
    except KeyboardInterrupt:
        print("[SIM] Остановлен.")
    finally:
        sock.close()


# ──────────────────────────────────────────────
# Точка входа
# ──────────────────────────────────────────────
if __name__ == "__main__":
    import sys

    mode = sys.argv[1] if len(sys.argv) > 1 else "coremotion"

    if mode == "sim":
        run_simulator()
    else:
        try:
            run_with_coremotion()
        except ImportError:
            print("[WARN] objc_util недоступен. Запускаю симулятор...")
            run_simulator()
