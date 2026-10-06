import SceneKit
import simd

/// Узел SceneKit, процедурно собирающий 3D-модель теннисной ракетки с установленными AirPods.
public final class RacquetModelNode: SCNNode {
    
    // Ссылки на дочерние элементы для возможной кастомизации
    public private(set) var handleNode: SCNNode!
    public private(set) var throatNode: SCNNode!
    public private(set) var headNode: SCNNode!
    public private(set) var stringsNode: SCNNode!
    public private(set) var airpodsNode: SCNNode!
    
    public override init() {
        super.init()
        setupRacquetGeometry()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupRacquetGeometry()
    }
    
    private func setupRacquetGeometry() {
        // Базовая точка отсчета (Pivot): центр вилки/шейки ракетки (y = 0)
        // Геометрические параметры (в условных дециметрах / масштабе сцены):
        // 1 единица SceneKit ≈ 10 см
        
        // 1. Рукоятка ракетки (Handle)
        // Длина ~ 1.9 единицы (19 см), радиус ~ 0.16 (1.6 см)
        let handleLength: CGFloat = 1.9
        let handleRadius: CGFloat = 0.16
        let handleGeo = SCNCylinder(radius: handleRadius, height: handleLength)
        
        let handleMaterial = SCNMaterial()
        handleMaterial.diffuse.contents = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        handleMaterial.roughness.contents = 0.8
        handleGeo.materials = [handleMaterial]
        
        handleNode = SCNNode(geometry: handleGeo)
        // Смещаем рукоятку вниз вдоль оси -Y
        handleNode.position = SCNVector3(0, -handleLength / 2.0 - 0.2, 0)
        addChildNode(handleNode)
        
        // Заглушка рукоятки (Butt Cap)
        let capGeo = SCNCylinder(radius: handleRadius * 1.15, height: 0.1)
        let capMaterial = SCNMaterial()
        capMaterial.diffuse.contents = UIColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1.0) // Фирменный красный торец
        capGeo.materials = [capMaterial]
        let capNode = SCNNode(geometry: capGeo)
        capNode.position = SCNVector3(0, -handleLength / 2.0, 0)
        handleNode.addChildNode(capNode)
        
        // 2. Шейка (Throat / Вилка)
        throatNode = SCNNode()
        let throatBranchLength: CGFloat = 0.8
        let throatBranchRadius: CGFloat = 0.08
        let branchGeo = SCNCylinder(radius: throatBranchRadius, height: throatBranchLength)
        
        let frameMaterial = SCNMaterial()
        frameMaterial.diffuse.contents = UIColor(red: 0.05, green: 0.45, blue: 0.9, alpha: 1.0) // Спортивный ярко-синий карбон
        frameMaterial.metalness.contents = 0.4
        frameMaterial.roughness.contents = 0.3
        branchGeo.materials = [frameMaterial]
        
        // Левый луч вилки
        let leftBranch = SCNNode(geometry: branchGeo)
        leftBranch.position = SCNVector3(-0.25, 0.15, 0)
        leftBranch.eulerAngles = SCNVector3(0, 0, 0.32) // легкий наклон наружу
        throatNode.addChildNode(leftBranch)
        
        // Правый луч вилки
        let rightBranch = SCNNode(geometry: branchGeo)
        rightBranch.position = SCNVector3(0.25, 0.15, 0)
        rightBranch.eulerAngles = SCNVector3(0, 0, -0.32)
        throatNode.addChildNode(rightBranch)
        
        // Перемычка вилки (Bridge)
        let bridgeGeo = SCNBox(width: 0.65, height: 0.1, length: 0.12, chamferRadius: 0.04)
        bridgeGeo.materials = [frameMaterial]
        let bridgeNode = SCNNode(geometry: bridgeGeo)
        bridgeNode.position = SCNVector3(0, 0.48, 0)
        throatNode.addChildNode(bridgeNode)
        
        addChildNode(throatNode)
        
        // 3. AirPods (Датчик IMU), жестко закрепленный на шее ракетки
        let podWidth: CGFloat = 0.18
        let podHeight: CGFloat = 0.28
        let podDepth: CGFloat = 0.16
        let podGeo = SCNBox(width: podWidth, height: podHeight, length: podDepth, chamferRadius: 0.05)
        let podMaterial = SCNMaterial()
        podMaterial.diffuse.contents = UIColor(white: 0.96, alpha: 1.0) // Глянцевый белый пластик
        podMaterial.roughness.contents = 0.1
        podGeo.materials = [podMaterial]
        
        airpodsNode = SCNNode(geometry: podGeo)
        // Закреплен прямо по центру вилки на оси Z (лицевая сторона)
        airpodsNode.position = SCNVector3(0, 0.15, Float(podDepth / 2.0 + 0.04))
        
        // Индикатор светодиода AirPods
        let ledGeo = SCNSphere(radius: 0.015)
        let ledMat = SCNMaterial()
        ledMat.diffuse.contents = UIColor.green
        ledMat.emission.contents = UIColor.green
        ledGeo.materials = [ledMat]
        let ledNode = SCNNode(geometry: ledGeo)
        ledNode.position = SCNVector3(0, 0.06, Float(podDepth / 2.0 + 0.005))
        airpodsNode.addChildNode(ledNode)
        
        addChildNode(airpodsNode)
        
        // 4. Обод ракетки (Head / Rim)
        headNode = SCNNode()
        let ringRadius: CGFloat = 1.15   // Радиус кольца
        let pipeRadius: CGFloat = 0.075  // Толщина обода
        let rimGeo = SCNTorus(ringRadius: ringRadius, pipeRadius: pipeRadius)
        rimGeo.materials = [frameMaterial]
        
        let rimNode = SCNNode(geometry: rimGeo)
        // В SceneKit SCNTorus лежит в плоскости XZ. Поворачиваем его в плоскость XY ракетки
        rimNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        
        // Слегка сплющиваем по ширине X для овальной формы теннисной ракетки
        rimNode.scale = SCNVector3(0.9, 1.25, 1.0)
        rimNode.position = SCNVector3(0, 1.7, 0)
        headNode.addChildNode(rimNode)
        addChildNode(headNode)
        
        // 5. Струнная поверхность (Strings Mesh)
        // Тонкий диск с полупрозрачной текстурой струн
        let stringBedGeo = SCNCylinder(radius: ringRadius * 0.9, height: 0.01)
        let stringBedMat = SCNMaterial()
        stringBedMat.diffuse.contents = UIColor(white: 0.95, alpha: 0.35)
        stringBedMat.roughness.contents = 0.9
        stringBedMat.isDoubleSided = true
        stringBedGeo.materials = [stringBedMat]
        
        stringsNode = SCNNode(geometry: stringBedGeo)
        stringsNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        stringsNode.scale = SCNVector3(0.9, 1.0, 1.25)
        stringsNode.position = SCNVector3(0, 1.7, 0)
        addChildNode(stringsNode)
    }
    
    /// Быстрое применение ориентации от калибровочного кватерниона
    public func updateOrientation(_ quaternion: simd_quatf) {
        self.simdOrientation = quaternion
    }
}
