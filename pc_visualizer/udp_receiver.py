"""
TennisPods — UDP Receiver
==========================
Принимает UDP-пакеты от iOS-коллектора в отдельном потоке.
Потокобезопасная очередь передаёт данные в главный поток.
"""

import struct
import socket
import threading
import time
from collections import deque
from typing import Optional, NamedTuple

PACKET_FORMAT = "!ddddd"   # timestamp + qw + qx + qy + qz
PACKET_SIZE   = struct.calcsize(PACKET_FORMAT)  # 40 байт
MAX_QUEUE_SIZE = 256


class MotionPacket(NamedTuple):
    timestamp: float
    qw: float
    qx: float
    qy: float
    qz: float


class UDPReceiver:
    """
    Неблокирующий UDP-приёмник.

    Использование:
        rx = UDPReceiver(port=5005)
        rx.start()
        ...
        pkt = rx.get_latest()  # None если нет новых данных
        ...
        rx.stop()
    """

    def __init__(self, host: str = "0.0.0.0", port: int = 5005):
        self.host = host
        self.port = port
        self._sock: Optional[socket.socket] = None
        self._thread: Optional[threading.Thread] = None
        self._running = False

        # Очередь — берём только последний пакет для минимальной задержки
        self._queue: deque = deque(maxlen=MAX_QUEUE_SIZE)
        self._lock = threading.Lock()

        # Статистика
        self.packets_received = 0
        self.packets_dropped = 0
        self._last_packet_time = 0.0

    def start(self):
        """Запустить фоновый поток приёма."""
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 262144)
        self._sock.settimeout(1.0)
        self._sock.bind((self.host, self.port))
        self._running = True
        self._thread = threading.Thread(
            target=self._recv_loop, daemon=True, name="UDPReceiver"
        )
        self._thread.start()
        print(f"[UDP] Слушаю {self.host}:{self.port} ...")

    def stop(self):
        """Остановить приём."""
        self._running = False
        if self._sock:
            self._sock.close()
        if self._thread:
            self._thread.join(timeout=2.0)
        print(f"[UDP] Остановлен. Принято: {self.packets_received}, "
              f"пропущено: {self.packets_dropped}")

    def get_latest(self) -> Optional[MotionPacket]:
        """Получить последний пакет (без блокировки). None если очередь пуста."""
        with self._lock:
            if not self._queue:
                return None
            return self._queue[-1]

    def drain_all(self):
        """Получить все накопленные пакеты и очистить очередь."""
        with self._lock:
            packets = list(self._queue)
            self._queue.clear()
        return packets

    @property
    def is_connected(self) -> bool:
        """True если пакет получен менее 2 секунд назад."""
        return (time.time() - self._last_packet_time) < 2.0

    @property
    def effective_hz(self) -> float:
        """Примерная эффективная частота за последние 256 пакетов."""
        with self._lock:
            if len(self._queue) < 2:
                return 0.0
            first = self._queue[0].timestamp
            last  = self._queue[-1].timestamp
            dt = last - first
            if dt < 1e-6:
                return 0.0
            return (len(self._queue) - 1) / dt

    # ─── Внутренний поток ───────────────────────────────────
    def _recv_loop(self):
        while self._running:
            try:
                data, _ = self._sock.recvfrom(PACKET_SIZE * 2)
            except socket.timeout:
                continue
            except OSError:
                break

            if len(data) != PACKET_SIZE:
                self.packets_dropped += 1
                continue

            try:
                values = struct.unpack(PACKET_FORMAT, data)
                pkt = MotionPacket(*values)
                with self._lock:
                    self._queue.append(pkt)
                self.packets_received += 1
                self._last_packet_time = time.time()
            except struct.error:
                self.packets_dropped += 1
