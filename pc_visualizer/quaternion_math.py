"""
TennisPods — Quaternion Math Utilities
========================================
Чистая Python реализация кватернионных операций.
Не требует внешних зависимостей — только numpy.
"""

import numpy as np
from dataclasses import dataclass
from typing import Tuple


@dataclass
class Quaternion:
    """Кватернион: w + xi + yj + zk (unit-quaternion, |q| = 1)."""
    w: float = 1.0
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0

    # ── Нормализация ──────────────────────────────────────
    def normalized(self) -> "Quaternion":
        n = np.sqrt(self.w**2 + self.x**2 + self.y**2 + self.z**2)
        if n < 1e-9:
            return Quaternion(1, 0, 0, 0)
        return Quaternion(self.w/n, self.x/n, self.y/n, self.z/n)

    # ── Сопряжённый (= обратный для единичного кватерниона) ──
    def conjugate(self) -> "Quaternion":
        return Quaternion(self.w, -self.x, -self.y, -self.z)

    inverse = conjugate  # alias

    # ── Умножение кватернионов (Hamilton product) ──────────
    def __mul__(self, other: "Quaternion") -> "Quaternion":
        w1, x1, y1, z1 = self.w, self.x, self.y, self.z
        w2, x2, y2, z2 = other.w, other.x, other.y, other.z
        return Quaternion(
            w1*w2 - x1*x2 - y1*y2 - z1*z2,
            w1*x2 + x1*w2 + y1*z2 - z1*y2,
            w1*y2 - x1*z2 + y1*w2 + z1*x2,
            w1*z2 + x1*y2 - y1*x2 + z1*w2,
        )

    # ── Сферическая линейная интерполяция (SLERP) ─────────
    def slerp(self, other: "Quaternion", t: float) -> "Quaternion":
        """
        Интерполяция между self и other при параметре t ∈ [0, 1].
        Обеспечивает плавную анимацию при FPS > частоты датчика.
        """
        q1 = np.array([self.w, self.x, self.y, self.z])
        q2 = np.array([other.w, other.x, other.y, other.z])

        dot = np.dot(q1, q2)
        # Берём кратчайший путь
        if dot < 0.0:
            q2 = -q2
            dot = -dot
        dot = np.clip(dot, -1.0, 1.0)

        # При малом угле → линейная интерполяция
        if dot > 0.9995:
            result = q1 + t * (q2 - q1)
            result /= np.linalg.norm(result)
            return Quaternion(*result)

        theta_0 = np.arccos(dot)
        theta   = theta_0 * t
        sin_theta   = np.sin(theta)
        sin_theta_0 = np.sin(theta_0)

        s1 = np.cos(theta) - dot * sin_theta / sin_theta_0
        s2 = sin_theta / sin_theta_0
        result = s1 * q1 + s2 * q2
        return Quaternion(*result)

    # ── Матрица вращения 4×4 (OpenGL column-major) ────────
    def to_rotation_matrix(self) -> np.ndarray:
        """
        Возвращает матрицу вращения 4×4 (float32), готовую к передаче
        в glUniformMatrix4fv / moderngl.
        """
        q = self.normalized()
        w, x, y, z = q.w, q.x, q.y, q.z

        mat = np.array([
            [1 - 2*(y*y + z*z),     2*(x*y - w*z),     2*(x*z + w*y), 0],
            [    2*(x*y + w*z), 1 - 2*(x*x + z*z),     2*(y*z - w*x), 0],
            [    2*(x*z - w*y),     2*(y*z + w*x), 1 - 2*(x*x + y*y), 0],
            [               0,                  0,                  0, 1],
        ], dtype=np.float32)
        return mat

    # ── Эйлеровы углы (roll, pitch, yaw) в градусах ───────
    def to_euler_degrees(self) -> Tuple[float, float, float]:
        q = self.normalized()
        w, x, y, z = q.w, q.x, q.y, q.z

        # Roll (X)
        sinr_cosp = 2 * (w*x + y*z)
        cosr_cosp = 1 - 2 * (x*x + y*y)
        roll = np.degrees(np.arctan2(sinr_cosp, cosr_cosp))

        # Pitch (Y)
        sinp = 2 * (w*y - z*x)
        sinp = np.clip(sinp, -1.0, 1.0)
        pitch = np.degrees(np.arcsin(sinp))

        # Yaw (Z)
        siny_cosp = 2 * (w*z + x*y)
        cosy_cosp = 1 - 2 * (y*y + z*z)
        yaw = np.degrees(np.arctan2(siny_cosp, cosy_cosp))

        return roll, pitch, yaw

    def __repr__(self) -> str:
        return f"Quaternion(w={self.w:.4f}, x={self.x:.4f}, y={self.y:.4f}, z={self.z:.4f})"


# ── Вспомогательные функции ────────────────────────────────────────

def quaternion_from_raw(qw: float, qx: float, qy: float, qz: float) -> Quaternion:
    """Создаёт нормализованный кватернион из сырых компонент."""
    return Quaternion(qw, qx, qy, qz).normalized()


def apply_calibration(q_raw: Quaternion, q_calib_inv: Quaternion) -> Quaternion:
    """
    Применяет калибровочное смещение:
        q_realtime = q_calib_inv * q_raw

    Args:
        q_raw:       Входящий кватернион с датчика.
        q_calib_inv: Обратный кватернион калибровки (вычисляется один раз).

    Returns:
        Кватернион в системе координат ракетки.
    """
    return (q_calib_inv * q_raw).normalized()
