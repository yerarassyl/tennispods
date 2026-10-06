"""
TennisPods — Racket Mesh with Hand Pivot (Butt Cap Origin)
============================================================
Генерирует геометрию ракетки с точкой опоры СТРОГО в основании рукоятки (y = 0.0).
Все элементы (ручка, вилка, обод, струны) расположены выше y = 0.
Вращение ракетки в OpenGL происходит строго вокруг нижнего конца ручки (кисти руки).
"""

import numpy as np

def create_octagonal_prism(r_bot=0.17, r_top=0.16, y_bot=0.0, y_top=2.0):
    """Восьмигранная рукоятка (Tennis Grip)."""
    vertices = []
    sides = 8
    angles = np.linspace(0, 2 * np.pi, sides, endpoint=False)
    
    for i in range(sides):
        a1 = angles[i]
        a2 = angles[(i + 1) % sides]
        
        x1_b, z1_b = r_bot * np.cos(a1), r_bot * np.sin(a1)
        x2_b, z2_b = r_bot * np.cos(a2), r_bot * np.sin(a2)
        x1_t, z1_t = r_top * np.cos(a1), r_top * np.sin(a1)
        x2_t, z2_t = r_top * np.cos(a2), r_top * np.sin(a2)
        
        # 2 треугольника на каждую грань
        vertices.extend([
            [x1_b, y_bot, z1_b], [x2_b, y_bot, z2_b], [x2_t, y_top, z2_t],
            [x1_b, y_bot, z1_b], [x2_t, y_top, z2_t], [x1_t, y_top, z1_t]
        ])
    return np.array(vertices, dtype=np.float32)

def create_racket_model():
    """
    Генерирует вершины для ракетки.
    Точка привязки (Origin 0, 0, 0):
      - Нижняя часть рукоятки (Butt Cap / основание руки) = y: 0.0
      - Ручка: y = 0.0 .. 2.0
      - Шейка (вилка): y = 2.0 .. 3.2
      - Обод со струнами: y = 3.2 .. 6.6
    """
    triangles = []
    tri_colors = []
    
    lines = []
    line_colors = []

    # 1. Заглушка рукоятки (Butt Cap) в самом низу (y = 0.0 .. 0.12)
    cap_tris = create_octagonal_prism(r_bot=0.19, r_top=0.18, y_bot=0.0, y_top=0.12)
    triangles.append(cap_tris)
    tri_colors.append(np.tile([0.82, 0.1, 0.12], (len(cap_tris), 1))) # Красный Wilson торец

    # 2. Рукоятка (Grip) от y = 0.12 до y = 2.05 (длина ~19.3 см)
    handle_tris = create_octagonal_prism(r_bot=0.165, r_top=0.155, y_bot=0.12, y_top=2.05)
    triangles.append(handle_tris)
    tri_colors.append(np.tile([0.14, 0.14, 0.16], (len(handle_tris), 1))) # Черная полиуретановая намотка

    # Манжета намотки (Collar)
    collar_tris = create_octagonal_prism(r_bot=0.17, r_top=0.17, y_bot=2.00, y_top=2.12)
    triangles.append(collar_tris)
    tri_colors.append(np.tile([0.05, 0.05, 0.05], (len(collar_tris), 1)))

    # Вспомогательная функция для аэродинамических трубок/лучей
    def add_beam(p1, p2, radius=0.07, color=(0.06, 0.45, 0.88), segments=8):
        v = p2 - p1
        length = np.linalg.norm(v)
        if length < 1e-4:
            return
        dir_v = v / length
        up = np.array([0, 0, 1], dtype=np.float32)
        side = np.cross(dir_v, up)
        if np.linalg.norm(side) < 1e-4:
            up = np.array([1, 0, 0], dtype=np.float32)
            side = np.cross(dir_v, up)
        side /= np.linalg.norm(side)
        up = np.cross(side, dir_v)
        
        verts = []
        angles = np.linspace(0, 2 * np.pi, segments, endpoint=False)
        for i in range(segments):
            a1 = angles[i]
            a2 = angles[(i + 1) % segments]
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

    # 3. Шейка (Throat / Вилка) с y = 2.12 до y = 3.25
    p_base_l = np.array([-0.08, 2.12, 0.0], dtype=np.float32)
    p_base_r = np.array([0.08, 2.12, 0.0], dtype=np.float32)
    p_left   = np.array([-0.45, 3.25, 0.0], dtype=np.float32)
    p_right  = np.array([0.45, 3.25, 0.0], dtype=np.float32)
    
    add_beam(p_base_l, p_left, 0.07, (0.08, 0.12, 0.18))
    add_beam(p_base_r, p_right, 0.07, (0.08, 0.12, 0.18))
    add_beam(p_left, p_right, 0.065, (0.08, 0.12, 0.18)) # Мостик вилки

    # 4. Обод ракетки (Head Frame) с y = 3.25 до y = 6.85 (центр y = 5.05)
    head_cy = 5.05
    ax, by = 1.22, 1.72
    rim_pipe_r = 0.068
    num_rim_pts = 44
    theta = np.linspace(0, 2 * np.pi, num_rim_pts, endpoint=False)
    
    rim_ring_pts = []
    for t in theta:
        rx = ax * np.cos(t)
        ry = head_cy + by * np.sin(t)
        rim_ring_pts.append(np.array([rx, ry, 0.0], dtype=np.float32))

    for i in range(num_rim_pts):
        p1 = rim_ring_pts[i]
        p2 = rim_ring_pts[(i + 1) % num_rim_pts]
        # Карбоновый металлик с бирюзовым акцентом
        add_beam(p1, p2, rim_pipe_r, (0.0, 0.65, 0.95))

    # 5. Струны (Strings)
    num_mains = 16
    xs = np.linspace(-ax * 0.84, ax * 0.84, num_mains)
    for x in xs:
        val = 1.0 - (x / ax)**2
        if val > 0:
            dy_val = by * np.sqrt(val) * 0.94
            lines.extend([
                [x, head_cy - dy_val, 0.0],
                [x, head_cy + dy_val, 0.0]
            ])
            line_colors.extend([[0.95, 0.95, 0.7], [0.95, 0.95, 0.7]])

    num_cross = 18
    ys = np.linspace(head_cy - by * 0.84, head_cy + by * 0.84, num_cross)
    for y in ys:
        val = 1.0 - ((y - head_cy) / by)**2
        if val > 0:
            dx_val = ax * np.sqrt(val) * 0.94
            lines.extend([
                [-dx_val, y, 0.0],
                [dx_val, y, 0.0]
            ])
            line_colors.extend([[0.95, 0.95, 0.7], [0.95, 0.95, 0.7]])

    # Сборка финальных массивов
    tri_verts_all = np.vstack(triangles).astype(np.float32)
    tri_cols_all  = np.vstack(tri_colors).astype(np.float32)
    
    line_verts_all = np.array(lines, dtype=np.float32)
    line_cols_all  = np.array(line_colors, dtype=np.float32)

    return (tri_verts_all, tri_cols_all, line_verts_all, line_cols_all)
