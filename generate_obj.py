"""
Генератор реалистичной 3D-модели теннисной ракетки в формате Wavefront OBJ.
Модель имеет точку опоры (Pivot / Origin) СТРОГО в основании рукоятки (Butt Cap):
  y = 0.0 — торец ручки (место хвата кисти)
  y = 0.0 .. 2.0 — восьмигранная рукоятка (Grip) с намоткой и фасками
  y = 2.0 .. 3.2 — карбоновая шейка (Throat / Вилка) с анатомическим мостиком
  y = 3.2 .. 6.85 — аэродинамический обод 100 кв. дюймов (Head / Rim) с бампером
  Внутри обода — реальная сетка струн (Main & Cross strings).
"""

import math
import os

def generate_racket_obj(output_path):
    vertices = []
    normals = []
    faces = []

    def add_vertex(x, y, z):
        vertices.append((x, y, z))
        return len(vertices)

    def add_quad(v1, v2, v3, v4):
        # 1-based indexing for OBJ
        faces.append((v1, v2, v3))
        faces.append((v1, v3, v4))

    def add_tri(v1, v2, v3):
        faces.append((v1, v2, v3))

    def add_cylinder_segment(r_bottom, r_top, y_bot, y_top, sides=8):
        angles = [i * 2.0 * math.pi / sides for i in range(sides)]
        bot_indices = []
        top_indices = []
        for a in angles:
            xb = r_bottom * math.cos(a)
            zb = r_bottom * math.sin(a)
            xt = r_top * math.cos(a)
            zt = r_top * math.sin(a)
            bot_indices.append(add_vertex(xb, y_bot, zb))
            top_indices.append(add_vertex(xt, y_top, zt))

        for i in range(sides):
            nxt = (i + 1) % sides
            b1 = bot_indices[i]
            b2 = bot_indices[nxt]
            t1 = top_indices[i]
            t2 = top_indices[nxt]
            add_quad(b1, b2, t2, t1)
        return bot_indices, top_indices

    # 1. Заглушка рукоятки (Butt Cap) в самом низу (y = 0.0 .. 0.12)
    # Нижнее основание заглушки
    cap_sides = 8
    angles = [i * 2.0 * math.pi / cap_sides for i in range(cap_sides)]
    center_bot = add_vertex(0.0, 0.0, 0.0)
    bot_ring = [add_vertex(0.185 * math.cos(a), 0.0, 0.185 * math.sin(a)) for a in angles]
    for i in range(cap_sides):
        nxt = (i + 1) % cap_sides
        add_tri(center_bot, bot_ring[nxt], bot_ring[i])

    # Стенка Butt Cap
    add_cylinder_segment(0.185, 0.175, 0.0, 0.12, sides=8)

    # 2. Рукоятка ракетки (Handle / Grip) с y = 0.12 до y = 2.05 (длина ~19.3 см)
    # Классическое восьмигранное сечение рукоятки теннисной ракетки
    add_cylinder_segment(0.165, 0.155, 0.12, 2.05, sides=8)

    # Резиновое кольцо манжеты намотки (Collar) на стыке ручки и шейки
    add_cylinder_segment(0.168, 0.168, 2.00, 2.12, sides=12)

    # 3. Шейка ракетки (Throat / V-образная вилка) с y = 2.12 до основания обода y = 3.30
    def add_beam_tube(p1, p2, radius=0.07, segments=8):
        x1, y1, z1 = p1
        x2, y2, z2 = p2
        dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
        length = math.sqrt(dx*dx + dy*dy + dz*dz)
        if length < 1e-5:
            return
        ux, uy, uz = dx/length, dy/length, dz/length
        
        # Векторы перпендикуляров
        px, py, pz = 0.0, 0.0, 1.0
        # cross(u, p)
        cx = uy*pz - uz*py
        cy = uz*px - ux*pz
        cz = ux*py - uy*px
        c_len = math.sqrt(cx*cx + cy*cy + cz*cz)
        if c_len < 1e-5:
            px, py, pz = 1.0, 0.0, 0.0
            cx = uy*pz - uz*py
            cy = uz*px - ux*pz
            cz = ux*py - uy*px
            c_len = math.sqrt(cx*cx + cy*cy + cz*cz)
        cx, cy, cz = cx/c_len, cy/c_len, cz/c_len
        
        # второй перпендикуляр
        qx = uy*cz - uz*cy
        qy = uz*cx - ux*cz
        qz = ux*cy - uy*cx

        b_verts = []
        t_verts = []
        for i in range(segments):
            ang = i * 2.0 * math.pi / segments
            cosa = math.cos(ang) * radius
            sina = math.sin(ang) * radius
            vx = cosa * cx + sina * qx
            vy = cosa * cy + sina * qy
            vz = cosa * cz + sina * qz
            b_verts.append(add_vertex(x1 + vx, y1 + vy, z1 + vz))
            t_verts.append(add_vertex(x2 + vx, y2 + vy, z2 + vz))

        for i in range(segments):
            nxt = (i + 1) % segments
            add_quad(b_verts[i], b_verts[nxt], t_verts[nxt], t_verts[i])

    # Левый луч вилки
    add_beam_tube((-0.08, 2.12, 0.0), (-0.42, 3.25, 0.0), radius=0.065, segments=8)
    # Правый луч вилки
    add_beam_tube((0.08, 2.12, 0.0), (0.42, 3.25, 0.0), radius=0.065, segments=8)
    # Поперечный мостик вилки (Throat Bridge)
    add_beam_tube((-0.42, 3.25, 0.0), (0.42, 3.25, 0.0), radius=0.060, segments=8)

    # 4. Обод ракетки (Head / Rim) с y = 3.25 до y = 6.85
    # Центр эллипса обода:
    head_cy = 5.05
    # Полуоси: по ширине rx = 1.25, по высоте ry = 1.75 (высота обода = 3.50)
    rx = 1.22
    ry = 1.72
    rim_pipe_r = 0.068
    num_rim_points = 40
    
    rim_ring = []
    for i in range(num_rim_points):
        ang = i * 2.0 * math.pi / num_rim_points
        px = rx * math.cos(ang)
        py = head_cy + ry * math.sin(ang)
        rim_ring.append((px, py, 0.0))

    for i in range(num_rim_points):
        nxt = (i + 1) % num_rim_points
        add_beam_tube(rim_ring[i], rim_ring[nxt], radius=rim_pipe_r, segments=8)

    # Бампер защиты верха обода (Bumper Guard) на 10..2 часах
    for i in range(int(num_rim_points * 0.15), int(num_rim_points * 0.35)):
        nxt = i + 1
        add_beam_tube(rim_ring[i], rim_ring[nxt], radius=rim_pipe_r * 1.15, segments=6)

    # 5. Сетка струн (Strings Bed)
    string_r = 0.009
    # Вертикальные струны (Mains)
    main_count = 16
    for i in range(main_count):
        frac = (i + 0.5) / main_count * 2.0 - 1.0  # -1.0 .. +1.0
        x_val = frac * rx * 0.86
        val = 1.0 - (x_val / rx)**2
        if val > 0:
            dy_val = ry * math.sqrt(val) * 0.94
            p_bot = (x_val, head_cy - dy_val, 0.0)
            p_top = (x_val, head_cy + dy_val, 0.0)
            add_beam_tube(p_bot, p_top, radius=string_r, segments=4)

    # Горизонтальные струны (Crosses)
    cross_count = 19
    for i in range(cross_count):
        frac = (i + 0.5) / cross_count * 2.0 - 1.0
        y_val = head_cy + frac * ry * 0.88
        norm_y = (y_val - head_cy) / ry
        val = 1.0 - norm_y**2
        if val > 0:
            dx_val = rx * math.sqrt(val) * 0.94
            p_left = (-dx_val, y_val, 0.0)
            p_right = (dx_val, y_val, 0.0)
            add_beam_tube(p_left, p_right, radius=string_r, segments=4)

    # Запись Wavefront OBJ файла
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("# TennisPods Realistic Tennis Racquet 3D Model\n")
        f.write("# Pivot point is at Butt Cap bottom: (0, 0, 0)\n")
        f.write(f"# Vertices: {len(vertices)}, Faces: {len(faces)}\n")
        f.write("o TennisRacquet\n\n")
        
        for v in vertices:
            f.write(f"v {v[0]:.5f} {v[1]:.5f} {v[2]:.5f}\n")
            
        f.write("\ns 1\n")
        for face in faces:
            f.write(f"f {face[0]} {face[1]} {face[2]}\n")

    print(f"Model created successfully: {output_path}")
    print(f"Vertices: {len(vertices)}, Faces: {len(faces)}")

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "tennis_racket.obj")
    generate_racket_obj(out)
