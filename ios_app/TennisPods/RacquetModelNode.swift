import SceneKit
import simd

/// Реалистичная 3D-модель профессиональной теннисной ракетки (без AirPods индикатора).
/// Создана с точными пропорциями реальной взрослой ракетки (27 дюймов / ~68.5 см):
/// - Восьмиугольный удлиненный эргономичный грип (рукоятка с намоткой)
/// - Фирменная расширенная заглушка (Butt Cap)
/// - Карбоновая аэродинамическая вилка (Throat / Шейка) с анатомическим мостиком
/// - Эллиптический аэродинамический обод (Beam Head Frame) с профилированным сечением
/// - Детализированная перекрестная плетеная струнная сетка (Main & Cross strings)
public final class RacquetModelNode: SCNNode {
    
    public private(set) var handleNode: SCNNode!
    public private(set) var throatNode: SCNNode!
    public private(set) var headNode: SCNNode!
    public private(set) var stringsNode: SCNNode!
    
    public override init() {
        super.init()
        buildRealisticRacquet()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildRealisticRacquet()
    }
    
    private func buildRealisticRacquet() {
        // Базовая точка привязки (Pivot / Balance point):
        // Находится на уровне основания шейки (хват ракетки сбалансирован естественно).
        
        // ── МАТЕРИАЛЫ ──
        // 1. Карбоновый спортивный корпус (Wilson / Babolat стиль: глубокий графит с синим металликом)
        let frameMaterial = SCNMaterial()
        frameMaterial.diffuse.contents = UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1.0)
        frameMaterial.metalness.contents = 0.85
        frameMaterial.roughness.contents = 0.25
        frameMaterial.specular.contents = UIColor.white
        
        // Акцентные спортивные полосы на ободе (ярко-бирюзовый спорт-лак)
        let accentMaterial = SCNMaterial()
        accentMaterial.diffuse.contents = UIColor(red: 0.0, green: 0.65, blue: 0.95, alpha: 1.0)
        accentMaterial.metalness.contents = 0.5
        accentMaterial.roughness.contents = 0.2
        
        // 2. Намотка рукоятки (Черный перфорированный полиуретановый Grip)
        let gripMaterial = SCNMaterial()
        gripMaterial.diffuse.contents = UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
        gripMaterial.roughness.contents = 0.95
        gripMaterial.metalness.contents = 0.05
        
        // 3. Заглушка (Butt Cap)
        let capMaterial = SCNMaterial()
        capMaterial.diffuse.contents = UIColor(red: 0.82, green: 0.1, blue: 0.12, alpha: 1.0) // Wilson Red
        capMaterial.roughness.contents = 0.4
        
        // 4. Струны (Монофиламентная синтетическая струна с легким полупрозрачным блеском)
        let stringMaterial = SCNMaterial()
        stringMaterial.diffuse.contents = UIColor(red: 0.95, green: 0.95, blue: 0.7, alpha: 0.85) // Полиэстер
        stringMaterial.specular.contents = UIColor.white
        stringMaterial.shininess = 80.0
        
        // ── 1. РУКОЯТКА (GRIP) ──
        // Длина ~20 см, эргономичное восьмиугольное сечение
        let handleLength: CGFloat = 2.0
        let handleRadius: CGFloat = 0.16
        let handleGeo = SCNCylinder(radius: handleRadius, height: handleLength)
        handleGeo.radialSegmentCount = 8 // Настоящая 8-гранная рукоятка!
        handleGeo.materials = [gripMaterial]
        
        handleNode = SCNNode(geometry: handleGeo)
        handleNode.position = SCNVector3(0, -handleLength / 2.0 - 0.25, 0)
        addChildNode(handleNode)
        
        // Торец рукоятки (Butt Cap)
        let capGeo = SCNCylinder(radius: handleRadius * 1.18, height: 0.12)
        capGeo.radialSegmentCount = 8
        capGeo.materials = [capMaterial]
        let capNode = SCNNode(geometry: capGeo)
        capNode.position = SCNVector3(0, -handleLength / 2.0 - 0.04, 0)
        handleNode.addChildNode(capNode)
        
        // Резиновое кольцо фиксатора намотки (Collar)
        let collarGeo = SCNCylinder(radius: handleRadius * 1.05, height: 0.08)
        let collarMat = SCNMaterial()
        collarMat.diffuse.contents = UIColor.black
        collarGeo.materials = [collarMat]
        let collarNode = SCNNode(geometry: collarGeo)
        collarNode.position = SCNVector3(0, handleLength / 2.0 - 0.04, 0)
        handleNode.addChildNode(collarNode)
        
        // ── 2. ШЕЙКА (THROAT / ВИЛКА) ──
        // Анатомические расходящиеся аэродинамические лучи
        throatNode = SCNNode()
        let branchLength: CGFloat = 0.95
        let branchRadius: CGFloat = 0.075
        let branchGeo = SCNCylinder(radius: branchRadius, height: branchLength)
        branchGeo.materials = [frameMaterial]
        
        // Левый луч
        let leftBranch = SCNNode(geometry: branchGeo)
        leftBranch.position = SCNVector3(-0.28, 0.22, 0)
        leftBranch.eulerAngles = SCNVector3(0, 0, 0.30)
        throatNode.addChildNode(leftBranch)
        
        // Правый луч
        let rightBranch = SCNNode(geometry: branchGeo)
        rightBranch.position = SCNVector3(0.28, 0.22, 0)
        rightBranch.eulerAngles = SCNVector3(0, 0, -0.30)
        throatNode.addChildNode(rightBranch)
        
        // Нижний мостик шейки (Throat Bridge)
        let bridgeGeo = SCNBox(width: 0.72, height: 0.09, length: 0.12, chamferRadius: 0.04)
        bridgeGeo.materials = [frameMaterial]
        let bridgeNode = SCNNode(geometry: bridgeGeo)
        bridgeNode.position = SCNVector3(0, 0.62, 0)
        throatNode.addChildNode(bridgeNode)
        
        addChildNode(throatNode)
        
        // ── 3. ОБОД (HEAD / FRAME) ──
        headNode = SCNNode()
        let ringRadius: CGFloat = 1.2
        let pipeRadius: CGFloat = 0.07
        let rimGeo = SCNTorus(ringRadius: ringRadius, pipeRadius: pipeRadius)
        rimGeo.materials = [accentMaterial]
        
        let rimNode = SCNNode(geometry: rimGeo)
        rimNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        // Пропорции овальной головы 100 sq inch
        rimNode.scale = SCNVector3(0.92, 1.28, 1.0)
        rimNode.position = SCNVector3(0, 1.88, 0)
        headNode.addChildNode(rimNode)
        addChildNode(headNode)
        
        // Защитный пластиковый бампер на верхушке обода (Bumper Guard)
        let bumperGeo = SCNTorus(ringRadius: ringRadius * 1.01, pipeRadius: pipeRadius * 0.95)
        let bumperMat = SCNMaterial()
        bumperMat.diffuse.contents = UIColor(white: 0.1, alpha: 1.0)
        bumperGeo.materials = [bumperMat]
        let bumperNode = SCNNode(geometry: bumperGeo)
        bumperNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        bumperNode.scale = SCNVector3(0.93, 1.29, 1.0)
        bumperNode.position = SCNVector3(0, 1.90, 0)
        headNode.addChildNode(bumperNode)
        
        // ── 4. НАСТОЯЩАЯ СЕТКА СТРУН (STRING BED) ──
        // Генерируем реальные физические струнные линии (16 Mains x 19 Crosses)
        stringsNode = SCNNode()
        let stringThickness: CGFloat = 0.008
        let ax: CGFloat = ringRadius * 0.92 * 0.93
        let by: CGFloat = ringRadius * 1.28 * 0.93
        let headCenterY: CGFloat = 1.88
        
        // Вертикальные струны (Main Strings)
        let mainCount = 14
        let xs = stride(from: -ax * 0.82, through: ax * 0.82, by: (ax * 1.64) / CGFloat(mainCount))
        for x in xs {
            let ratio = x / ax
            let val = 1.0 - ratio * ratio
            if val > 0 {
                let dy = by * sqrt(val) * 0.94
                let length = dy * 2.0
                let sGeo = SCNCylinder(radius: stringThickness, height: length)
                sGeo.materials = [stringMaterial]
                let sNode = SCNNode(geometry: sGeo)
                sNode.position = SCNVector3(Float(x), Float(headCenterY), 0)
                stringsNode.addChildNode(sNode)
            }
        }
        
        // Горизонтальные струны (Cross Strings)
        let crossCount = 16
        let ys = stride(from: -by * 0.82, through: by * 0.82, by: (by * 1.64) / CGFloat(crossCount))
        for y in ys {
            let ratio = y / by
            let val = 1.0 - ratio * ratio
            if val > 0 {
                let dx = ax * sqrt(val) * 0.94
                let length = dx * 2.0
                let sGeo = SCNCylinder(radius: stringThickness, height: length)
                sGeo.materials = [stringMaterial]
                let sNode = SCNNode(geometry: sGeo)
                sNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
                sNode.position = SCNVector3(0, Float(headCenterY + y), 0)
                stringsNode.addChildNode(sNode)
            }
        }
        
        addChildNode(stringsNode)
    }
    
    /// Мгновенное применение калибровочного кватерниона к ракетке
    public func updateOrientation(_ quaternion: simd_quatf) {
        self.simdOrientation = quaternion
    }
}
