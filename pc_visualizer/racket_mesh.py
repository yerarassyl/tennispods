"""
TennisPods — 3D Tennis Racket Geometry Generator
=================================================
Создает вершины и цвета для схематичной 3D-модели ракетки:
- Ручка (handle): восьмиугольная или цилиндрическая призма вдоль оси Y (снизу от начала координат)
- Шейка / вилка (throat): V-образные лучи, соединяющие ручку и обод
- Обод (head/rim): эллиптический обод в плоскости XY
- Струны (strings): сетка отрезков в плоскости XY внутри обода
- Маркер AirPods: маленький куб/бокс на шее ракетки
"""

import numpy as np

def create_cylinder(radius=0.15, height=1.6, segments=16, y_offset=-1.6):
    """Цилиндрическая ручка вдоль оси Y."""
    vertices = []
    angles = np.linspace(0, 2 * np.pi, segments, endpoint=False)
    
    # Боковая поверхность
    for i in range(segments):
        a1 = angles[i]
        a2 = angles[(i + 1) % segments]
        
        x1, z1 = radius * np.cos(a1), radius * np.sin(a1)
        x2, z2 = radius * np.cos(a2), radius * np.sin(a2)
        
        y_bot = y_offset
        y_top = y_offset + height
        
        # 2 треугольника (quad)
        vertices.extend([
            [x1, y_bot, z1], [x2, y_bot, z2], [x2, y_top, z2],
            [x1, y_bot, z1], [x2, y_top, z2], [x1, y_top, z1]
        ])
    return np.array(vertices, dtype=np.float32)

def create_racket_model():
    """
    Генерирует вершины для отрисовки триангулированной и каркасной ракетки.
    Целевая система координат:
      - Продольная ось: Y (ручка внизу -Y, голова ракетки вверху +Y)
      - Плоскость струн: XY (нормаль струн = Z)
      - Ширина ракетки: вдоль X
    """
    triangles = []
    tri_colors = []
    
    lines = []
    line_colors = []

    # 1. Ручка (Грип)
    handle_r = 0.16
    handle_h = 1.8
    handle_y_bot = -2.2
    handle_tris = create_cylinder(radius=handle_r, height=handle_h, segments=12, y_offset=handle_y_bot)
    triangles.append(handle_tris)
    # Цвет ручки: темный полиуретан / намотка
    tri_colors.append(np.tile([0.15, 0.15, 0.18], (len(handle_tris), 1)))

    # Заглушка (butt cap)
    cap_tris = create_cylinder(radius=handle_r * 1.1, height=0.15, segments=12, y_offset=handle_y_bot - 0.1)
    triangles.append(cap_tris)
    tri_colors.append(np.tile([0.8, 0.1, 0.1], (len(cap_tris), 1)))

    # 2. Шейка (Throat / V-образная вилка)
    # Два луча от ручки (y=-0.4) к основанию обода (y=0.2, x=±0.6)
    throat_segs = 8
    def add_beam(p1, p2, radius=0.1, color=(0.85, 0.85, 0.9)):
        v = p2 - p1
        length = np.linalg.norm(v)
        dir_v = v / length
        # ортогональные векторы
        up = np.array([0, 0, 1], dtype=np.float32)
        side = np.cross(dir_v, up)
        if np.linalg.norm(side) < 1e-4:
            up = np.array([1, 0, 0], dtype=np.float32)
            side = np.cross(dir_v, up)
        side /= np.linalg.norm(side)
        up = np.cross(side, dir_v)
        
        verts = []
        angles = np.linspace(0, 2*np.pi, 8, endpoint=False)
        for i in range(8):
            a1 = angles[i]
            a2 = angles[(i + 1) % 8]
            r1 = (side * np.cos(a1) + up * np.sin(a1)) * radius
            r2 = (side * np.cos(a2) + up * np.sin(a2)) * radius
            
            b1 = p1 + r1
            b2 = p1 + r2
            t1 = p2 + r1
            t2 = p2 + r2
            verts.extend([b1, b2, t2, b1, t2, t1])
        verts = np.array(verts, dtype=np.float32)
        triangles.append(verts)
        tri_colors.append(np.tile(color, (len(verts), 1)))

    p_base = np.array([0.0, -0.4, 0.0], dtype=np.float32)
    p_left = np.array([-0.65, 0.3, 0.0], dtype=np.float32)
    p_right = np.array([0.65, 0.3, 0.0], dtype=np.float32)
    p_bridge = np.array([0.0, 0.3, 0.0], dtype=np.float32)
    
    add_beam(p_base, p_left, 0.11, (0.1, 0.45, 0.85))
    add_beam(p_base, p_right, 0.11, (0.1, 0.45, 0.85))
    add_beam(p_left, p_right, 0.09, (0.1, 0.45, 0.85)) # мостик шеи

    # 3. Маркер AirPods на шее (белая коробочка по центру шеи)
    pod_w, pod_h, pod_d = 0.22, 0.3, 0.16
    pod_center = np.array([0.0, -0.1, 0.12], dtype=np.float32)
    dx, dy, dz = pod_w/2, pod_h/2, pod_d/2
    c_verts = []
    # 6 граней куба
    faces = [
        # +Z
        [[-dx, -dy, dz], [dx, -dy, dz], [dx, dy, dz], [-dx, -dy, dz], [dx, dy, dz], [-dx, dy, dz]],
        # -Z
        [[-dx, -dy, -dz], [-dx, dy, -dz], [dx, dy, -dz], [-dx, -dy, -dz], [dx, dy, -dz], [dx, -dy, -dz]],
        # +X
        [[dx, -dy, -dz], [dx, dy, -dz], [dx, dy, dz], [dx, -dy, -dz], [dx, dy, dz], [dx, -dy, dz]],
        # -X
        [[-dx, -dy, -dz], [-dx, -dy, dz], [-dx, dy, dz], [-dx, -dy, -dz], [-dx, dy, dz], [-dx, dy, -dz]],
        # +Y
        [[-dx, dy, -dz], [-dx, dy, dz], [dx, dy, dz], [-dx, dy, -dz], [dx, dy, dz], [dx, dy, -dz]],
        # -Y
        [[-dx, -dy, -dz], [dx, -dy, -dz], [dx, -dy, dz], [-dx, -dy, -dz], [dx, -dy, dz], [-dx, -dy, -dz]],
    ]
    for face in faces:
        for pt in face:
            c_verts.append(pod_center + np.array(pt, dtype=np.float32))
    c_verts = np.array(c_verts, dtype=np.float32)
    triangles.append(c_verts)
    tri_colors.append(np.tile([0.98, 0.98, 0.98], (len(c_verts), 1))) # белый AirPods корпус

    # 4. Обод ракетки (Эллиптический тор)
    # Центр обода y=1.65, полу-оси a_x=1.1, b_y=1.45
    head_cy = 1.65
    ax, by = 1.1, 1.45
    rim_radius = 0.08
    num_rim_pts = 48
    theta = np.linspace(0, 2*np.pi, num_rim_pts, endpoint=False)
    
    rim_ring_pts = []
    for t in theta:
        rx = ax * np.cos(t)
        ry = head_cy + by * np.sin(t)
        rim_ring_pts.append(np.array([rx, ry, 0.0], dtype=np.float32))

    for i in range(num_rim_pts):
        p1 = rim_ring_pts[i]
        p2 = rim_ring_pts[(i + 1) % num_rim_pts]
        add_beam(p1, p2, rim_radius, (0.08, 0.52, 0.92))

    # 5. Струны (Линии в плоскости XY внутри эллипса)
    # Вертикальные струны (Main)
    num_mains = 16
    xs = np.linspace(-ax * 0.9, ax * 0.9, num_mains)
    for x in xs:
        # Граница эллипса: (x/ax)^2 + ((y - cy)/by)^2 = 1
        val = 1.0 - (x / ax)**2
        if val > 0:
            dy_val = by * np.sqrt(val)
            lines.extend([
                [x, head_cy - dy_val, 0.0],
                [x, head_cy + dy_val, 0.0]
            ])
            line_colors.extend([[0.95, 0.95, 0.3], [0.95, 0.95, 0.3]])

    # Горизонтальные струны (Cross)
    num_cross = 19
    ys = np.linspace(head_cy - by * 0.88, head_cy + by * 0.88, num_cross)
    for y in ys:
        val = 1.0 - ((y - head_cy) / by)**2
        if val > 0:
            dx_val = ax * np.sqrt(val)
            lines.extend([
                [-dx_val, y, 0.0],
                [dx_val, y, 0.0]
            ])
            line_colors.extend([[0.95, 0.95, 0.3], [0.95, 0.95, 0.3]])

    # Сборка финальных массивов
    tri_verts_all = np.vstack(triangles).astype(np.float32)
    tri_cols_all  = np.vstack(tri_colors).astype(np.float32)
    
    line_verts_all = np.array(lines, dtype=np.float32)
    line_cols_all  = np.array(line_colors, dtype=np.float32)

    return (tri_verts_all, tri_cols_all, line_verts_all, line_cols_all)
