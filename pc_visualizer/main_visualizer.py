"""
TennisPods — PC 3D Real-time Visualizer
=========================================
3D-визуализатор ориентации теннисной ракетки на PyQt5 + OpenGL.
- Принимает кватернионы от AirPods по UDP (100 Гц)
- Применяет калибровочное смещение (Tare/Zeroing)
- Плавная интерполяция ориентации через SLERP на частоте 60 FPS
- Отрисовка 3D-модели ракетки, сетки координат и статуса калибровки
"""

import sys
import time
import numpy as np

from PyQt5 import QtCore, QtGui, QtWidgets
from PyQt5.QtWidgets import QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QPushButton, QLabel, QFrame
from OpenGL import GL, GLU

from quaternion_math import Quaternion, apply_calibration
from calibration import CalibrationManager
from udp_receiver import UDPReceiver
from racket_mesh import create_racket_model


class GLRacketWidget(QtWidgets.QOpenGLWidget):
    """Виджет OpenGL для 3D-рендеринга ракетки."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.current_quat = Quaternion(1, 0, 0, 0)
        self.target_quat = Quaternion(1, 0, 0, 0)
        
        # Данные геометрии
        self.tri_verts = None
        self.tri_cols = None
        self.line_verts = None
        self.line_cols = None
        
        # Параметры камеры
        self.cam_distance = 6.8
        self.cam_pitch = 15.0
        self.cam_yaw = -20.0
        
        self.last_mouse_pos = None

    def initializeGL(self):
        GL.glEnable(GL.GL_DEPTH_TEST)
        GL.glDepthFunc(GL.GL_LEQUAL)
        GL.glEnable(GL.GL_CULL_FACE)
        GL.glCullFace(GL.GL_BACK)
        
        # Сглаживание линий и полигонов
        GL.glEnable(GL.GL_BLEND)
        GL.glBlendFunc(GL.GL_SRC_ALPHA, GL.GL_ONE_MINUS_SRC_ALPHA)
        GL.glEnable(GL.GL_LINE_SMOOTH)
        GL.glHint(GL.GL_LINE_SMOOTH_HINT, GL.GL_NICEST)
        
        # Освещение
        GL.glEnable(GL.GL_LIGHTING)
        GL.glEnable(GL.GL_LIGHT0)
        GL.glEnable(GL.GL_COLOR_MATERIAL)
        GL.glColorMaterial(GL.GL_FRONT_AND_BACK, GL.GL_AMBIENT_AND_DIFFUSE)
        
        GL.glLightfv(GL.GL_LIGHT0, GL.GL_POSITION, [5.0, 10.0, 7.0, 1.0])
        GL.glLightfv(GL.GL_LIGHT0, GL.GL_DIFFUSE, [0.9, 0.9, 0.95, 1.0])
        GL.glLightfv(GL.GL_LIGHT0, GL.GL_AMBIENT, [0.25, 0.25, 0.3, 1.0])

        GL.glClearColor(0.08, 0.09, 0.12, 1.0)
        
        # Создание полигональной модели
        self.tri_verts, self.tri_cols, self.line_verts, self.line_cols = create_racket_model()

    def resizeGL(self, w, h):
        if h == 0:
            h = 1
        GL.glViewport(0, 0, w, h)
        GL.glMatrixMode(GL.GL_PROJECTION)
        GL.glLoadIdentity()
        GLU.gluPerspective(45.0, w / float(h), 0.1, 100.0)
        GL.glMatrixMode(GL.GL_MODELVIEW)

    def paintGL(self):
        GL.glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT)
        GL.glLoadIdentity()

        # Камера: приподнята и направлена на ракетку, закрепленную снизу в y=0
        GL.glTranslatef(0.0, -1.8, -self.cam_distance)
        GL.glRotatef(self.cam_pitch, 1.0, 0.0, 0.0)
        GL.glRotatef(self.cam_yaw, 0.0, 1.0, 0.0)

        # 1. Сетка пола и оси координат
        self._draw_floor_grid()

        # 2. Рендеринг ракетки с вращением вокруг основания рукоятки (0, 0, 0)
        GL.glPushMatrix()
        
        # Преобразование кватерниона в матрицу вращения OpenGL
        rot_mat = self.current_quat.to_rotation_matrix()
        GL.glMultMatrixf(rot_mat.T.flatten())

        self._draw_racket()
        GL.glPopMatrix()

    def _draw_floor_grid(self):
        GL.glDisable(GL.GL_LIGHTING)
        GL.glLineWidth(1.0)
        GL.glBegin(GL.GL_LINES)
        
        size = 5.0
        step = 0.5
        y_floor = 0.0  # Сетка пола ровно под основанием рукоятки!
        GL.glColor4f(0.2, 0.25, 0.3, 0.5)
        
        x = -size
        while x <= size:
            GL.glVertex3f(x, y_floor, -size)
            GL.glVertex3f(x, y_floor, size)
            x += step
            
        z = -size
        while z <= size:
            GL.glVertex3f(-size, y_floor, z)
            GL.glVertex3f(size, y_floor, z)
            z += step
            
        GL.glEnd()
        GL.glEnable(GL.GL_LIGHTING)

    def _draw_racket(self):
        if self.tri_verts is None:
            return

        # Треугольники ракетки (корпус, ручка, шейка, AirPods)
        GL.glEnable(GL.GL_LIGHTING)
        GL.glBegin(GL.GL_TRIANGLES)
        for i in range(len(self.tri_verts)):
            GL.glColor3fv(self.tri_cols[i])
            GL.glVertex3fv(self.tri_verts[i])
        GL.glEnd()

        # Струны (линии)
        GL.glDisable(GL.GL_LIGHTING)
        GL.glLineWidth(1.2)
        GL.glBegin(GL.GL_LINES)
        for i in range(len(self.line_verts)):
            GL.glColor3fv(self.line_cols[i])
            GL.glVertex3fv(self.line_verts[i])
        GL.glEnd()
        GL.glEnable(GL.GL_LIGHTING)

    def set_target_orientation(self, quat: Quaternion):
        self.target_quat = quat

    def update_slerp(self, factor=0.35):
        """Интерполяция ориентации для абсолютно плавного 60 FPS движения."""
        self.current_quat = self.current_quat.slerp(self.target_quat, factor)
        self.update()

    # Управление камерой мышью
    def mousePressEvent(self, event):
        self.last_mouse_pos = event.pos()

    def mouseMoveEvent(self, event):
        if self.last_mouse_pos is not None:
            dx = event.x() - self.last_mouse_pos.x()
            dy = event.y() - self.last_mouse_pos.y()
            if event.buttons() & QtCore.Qt.LeftButton:
                self.cam_yaw += dx * 0.4
                self.cam_pitch += dy * 0.4
                self.update()
        self.last_mouse_pos = event.pos()

    def wheelEvent(self, event):
        delta = event.angleDelta().y() / 120.0
        self.cam_distance = np.clip(self.cam_distance - delta * 0.5, 2.0, 15.0)
        self.update()


class MainWindow(QMainWindow):
    """Главное окно приложения TennisPods 3D Visualizer."""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("TennisPods — 3D Racket Motion Tracker (AirPods IMU)")
        self.resize(1050, 720)

        # Компоненты системы
        self.receiver = UDPReceiver(port=5005)
        self.calibration = CalibrationManager(on_done=self._on_calibration_done)
        
        self.q_display = Quaternion(1, 0, 0, 0)

        self._setup_ui()
        self._start_timers()
        self.receiver.start()

    def _setup_ui(self):
        central_widget = QWidget(self)
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        # 3D виджет сцены
        self.gl_widget = GLRacketWidget(self)
        main_layout.addWidget(self.gl_widget, stretch=1)

        # Нижняя панель управления и телеметрии
        panel = QFrame(self)
        panel.setStyleSheet("""
            QFrame {
                background-color: #12141A;
                border-top: 1px solid #252836;
            }
            QLabel {
                color: #FFFFFF;
                font-family: 'Segoe UI', Arial, sans-serif;
            }
            QPushButton {
                background-color: #0A84FF;
                color: white;
                font-weight: bold;
                border-radius: 8px;
                padding: 10px 18px;
                font-size: 13px;
            }
            QPushButton:hover {
                background-color: #0070E0;
            }
            QPushButton#btnTare {
                background-color: #2C2C2E;
            }
            QPushButton#btnTare:hover {
                background-color: #3A3A3C;
            }
        """)
        panel_layout = QHBoxLayout(panel)
        panel_layout.setContentsMargins(20, 12, 20, 12)

        # Статус соединения
        self.lbl_status = QLabel("🟢 Слушаю UDP :5005")
        self.lbl_status.setStyleSheet("font-size: 14px; font-weight: bold;")
        panel_layout.addWidget(self.lbl_status)

        panel_layout.addSpacing(25)

        # Телеметрия
        self.lbl_telemetry = QLabel("Roll: 0.0° | Pitch: 0.0° | Yaw: 0.0° | Частота: 0 Гц")
        self.lbl_telemetry.setStyleSheet("color: #98989D; font-size: 13px; font-family: monospace;")
        panel_layout.addWidget(self.lbl_telemetry)

        panel_layout.addStretch()

        # Кнопки калибровки
        self.btn_calib = QPushButton("🎯 Откалибровать (3 сек)")
        self.btn_calib.clicked.connect(self._start_calibration)
        panel_layout.addWidget(self.btn_calib)

        self.btn_tare = QPushButton("⚡ Быстрый Tare")
        self.btn_tare.setObjectName("btnTare")
        self.btn_tare.clicked.connect(self._instant_tare)
        panel_layout.addWidget(self.btn_tare)

        self.btn_reset = QPushButton("↺ Сброс")
        self.btn_reset.setObjectName("btnTare")
        self.btn_reset.clicked.connect(self._reset_calibration)
        panel_layout.addWidget(self.btn_reset)

        main_layout.addWidget(panel)

    def _start_timers(self):
        # Таймер приема данных и SLERP-рендеринга на 60 FPS (16 мс)
        self.render_timer = QtCore.QTimer(self)
        self.render_timer.timeout.connect(self._on_update)
        self.render_timer.start(16)

    def _on_update(self):
        # Забираем последний UDP-пакет
        pkt = self.receiver.get_latest()
        
        if pkt is not None:
            q_raw = Quaternion(pkt.qw, pkt.qx, pkt.qy, pkt.qz).normalized()
            
            # Подаем в калибровщик (если запущен сбор)
            self.calibration.feed(q_raw)
            
            # Если откалибровано — применяем обратный кватернион
            if self.calibration.is_calibrated and self.calibration.q_calib_inv:
                self.q_display = apply_calibration(q_raw, self.calibration.q_calib_inv)
            else:
                self.q_display = q_raw
                
            self.gl_widget.set_target_orientation(self.q_display)

            # Обновление текста телеметрии
            roll, pitch, yaw = self.q_display.to_euler_degrees()
            hz = self.receiver.effective_hz
            self.lbl_telemetry.setText(
                f"Roll: {roll:+5.1f}° | Pitch: {pitch:+5.1f}° | Yaw: {yaw:+5.1f}° | Поток: {hz:4.0f} Гц"
            )

        # Статус соединения
        if self.receiver.is_connected:
            self.lbl_status.setText("🟢 AirPods онлайн")
            self.lbl_status.setStyleSheet("color: #30D158; font-size: 14px; font-weight: bold;")
        else:
            self.lbl_status.setText("🟡 Ожидание пакетов UDP...")
            self.lbl_status.setStyleSheet("color: #FF9F0A; font-size: 14px; font-weight: bold;")

        # Если идет калибровка — индикация
        if self.calibration.is_collecting:
            prog = int(self.calibration.progress * 100)
            self.btn_calib.setText(f"Запись... {prog}%")
        else:
            self.btn_calib.setText("🎯 Откалибровать (3 сек)")

        # Плавный шаг интерполяции
        self.gl_widget.update_slerp(factor=0.35)

    def _start_calibration(self):
        self.calibration.start()

    def _instant_tare(self):
        pkt = self.receiver.get_latest()
        if pkt:
            q_raw = Quaternion(pkt.qw, pkt.qx, pkt.qy, pkt.qz).normalized()
            self.calibration.q_calib = q_raw
            self.calibration.q_calib_inv = q_raw.conjugate()
            self.calibration._done = True
            print("[CALIB] Мгновенное тарирование выполнено!")

    def _reset_calibration(self):
        self.calibration.reset()

    def _on_calibration_done(self, q_calib_inv):
        print("[CALIB] Калибровка успешно завершена!")

    def closeEvent(self, event):
        self.receiver.stop()
        event.accept()


def main():
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
