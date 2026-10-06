"""
TennisPods — Calibration Manager
==================================
Реализует статическую калибровку ориентации AirPods → Ракетка.

Процедура:
  1. Игрок держит ракетку вертикально (обод вверх, струны смотрят вперёд).
  2. Система накапливает N кватернионов за CALIB_DURATION секунд.
  3. Вычисляется "средний" кватернион (eigen-метод: первый вектор SVD).
  4. q_calib_inv = conjugate(q_calib) сохраняется в файл.
  5. В рантайме: q_corrected = q_calib_inv * q_raw
"""

import json
import time
import numpy as np
from pathlib import Path
from typing import List, Optional, Callable

from quaternion_math import Quaternion

CALIB_DURATION = 3.0   # секунды записи
CALIB_MIN_SAMPLES = 50  # минимум пакетов для надёжной калибровки
CALIB_FILE = Path(__file__).parent / "calibration.json"


class CalibrationManager:
    """
    Состояния:
        IDLE      → COLLECTING (после вызова start())
        COLLECTING → DONE      (после накопления CALIB_DURATION секунд данных)
        DONE      → IDLE       (после сброса reset())
    """

    def __init__(self, on_done: Optional[Callable] = None):
        """
        Args:
            on_done: Колбэк вызывается по завершении калибровки.
                     Принимает аргумент q_calib_inv: Quaternion.
        """
        self._samples: List[np.ndarray] = []
        self._start_time: float = 0.0
        self._collecting: bool = False
        self._done: bool = False

        self.q_calib: Optional[Quaternion] = None      # усреднённый кватернион
        self.q_calib_inv: Optional[Quaternion] = None  # обратный (для коррекции)
        self.on_done = on_done

        # Загружаем сохранённую калибровку при старте
        self._try_load()

    # ──────────────────────────────────────────────────────
    # Публичный API
    # ──────────────────────────────────────────────────────
    def start(self):
        """Начать сбор калибровочных данных."""
        self._samples.clear()
        self._start_time = time.time()
        self._collecting = True
        self._done = False
        print(f"[CALIB] Сбор данных ({CALIB_DURATION:.0f} сек)... "
              "Держите ракетку неподвижно и вертикально (обод вверх).")

    def reset(self):
        """Сбросить калибровку."""
        self._samples.clear()
        self._collecting = False
        self._done = False
        self.q_calib = None
        self.q_calib_inv = None
        print("[CALIB] Калибровка сброшена.")

    def feed(self, q: Quaternion) -> bool:
        """
        Подать новый кватернион в калибратор.

        Returns:
            True если калибровка только что завершилась.
        """
        if not self._collecting or self._done:
            return False

        elapsed = time.time() - self._start_time
        # Контроль неподвижности: отбрасываем пакеты при резких движениях
        sample = np.array([q.w, q.x, q.y, q.z])
        if self._samples:
            dot = abs(np.dot(self._samples[-1], sample))
            if dot < 0.999:   # ~2.5° отклонение — предупреждение
                if dot < 0.99:  # >8° — игнорируем сэмпл
                    return False

        self._samples.append(sample)

        if elapsed >= CALIB_DURATION and len(self._samples) >= CALIB_MIN_SAMPLES:
            self._finalize()
            return True

        # Прогресс
        if len(self._samples) % 50 == 0:
            pct = min(100, int(elapsed / CALIB_DURATION * 100))
            print(f"[CALIB] {pct}% ({len(self._samples)} сэмплов)...")

        return False

    @property
    def is_collecting(self) -> bool:
        return self._collecting and not self._done

    @property
    def is_calibrated(self) -> bool:
        return self._done and self.q_calib_inv is not None

    @property
    def progress(self) -> float:
        """Прогресс [0.0 … 1.0]."""
        if not self._collecting:
            return 0.0
        return min(1.0, (time.time() - self._start_time) / CALIB_DURATION)

    # ──────────────────────────────────────────────────────
    # Внутренняя логика
    # ──────────────────────────────────────────────────────
    def _finalize(self):
        """Вычисляет q_calib как усреднённый кватернион (Markley eigen-метод)."""
        M = np.array(self._samples)  # shape: (N, 4)

        # Убеждаемся, что все кватернионы находятся в одном полушарии
        # (dot с первым образцом должен быть > 0)
        ref = M[0]
        for i in range(1, len(M)):
            if np.dot(M[i], ref) < 0:
                M[i] = -M[i]

        # Метод: собственный вектор матрицы M^T M, соответствующий
        # максимальному собственному значению — это и есть "средний" кватернион.
        A = M.T @ M
        eigenvalues, eigenvectors = np.linalg.eigh(A)
        # eigh возвращает в порядке возрастания → берём последний
        q_mean = eigenvectors[:, -1]

        self.q_calib = Quaternion(*q_mean).normalized()
        self.q_calib_inv = self.q_calib.conjugate()
        self._collecting = False
        self._done = True

        roll, pitch, yaw = self.q_calib.to_euler_degrees()
        print(f"[CALIB] ✓ Готово! Кватернион: {self.q_calib}")
        print(f"[CALIB]   Эйлер: roll={roll:.1f}°, pitch={pitch:.1f}°, yaw={yaw:.1f}°")
        print(f"[CALIB]   Сэмплов: {len(self._samples)}")

        self._save()

        if self.on_done:
            self.on_done(self.q_calib_inv)

    def _save(self):
        """Сохранить калибровку в JSON."""
        if not self.q_calib:
            return
        data = {
            "q_calib":     [self.q_calib.w, self.q_calib.x,
                            self.q_calib.y, self.q_calib.z],
            "q_calib_inv": [self.q_calib_inv.w, self.q_calib_inv.x,
                            self.q_calib_inv.y, self.q_calib_inv.z],
            "timestamp": time.time(),
            "samples_count": len(self._samples),
        }
        CALIB_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")
        print(f"[CALIB] Сохранено в {CALIB_FILE}")

    def _try_load(self):
        """Загрузить калибровку из JSON (если существует)."""
        if not CALIB_FILE.exists():
            return
        try:
            data = json.loads(CALIB_FILE.read_text(encoding="utf-8"))
            self.q_calib     = Quaternion(*data["q_calib"])
            self.q_calib_inv = Quaternion(*data["q_calib_inv"])
            self._done = True
            print(f"[CALIB] Загружена сохранённая калибровка "
                  f"({data.get('samples_count', '?')} сэмплов, "
                  f"ts={data.get('timestamp', 0):.0f})")
        except Exception as e:
            print(f"[CALIB] Не удалось загрузить калибровку: {e}")
