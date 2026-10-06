import SceneKit
import simd

/// Узел 3D-модели теннисной ракетки.
/// Вращение (Rotation) происходит СТРОГО вокруг нижней части рукоятки (Butt Cap / основание кисти).
/// Pivot (0, 0, 0) совпадает с основанием торца ручки.
public final class RacquetModelNode: SCNNode {
    
    public override init() {
        super.init()
        loadOrBuildRacquet()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadOrBuildRacquet()
    }
    
    private func loadOrBuildRacquet() {
        // Пробуем загрузить внешний 3D-файл tennis_racket.obj из бандла приложения
        if let url = Bundle.main.url(forResource: "tennis_racket", withExtension: "obj"),
           let scene = try? SCNScene(url: url, options: nil) {
            
            let container = SCNNode()
            for child in scene.rootNode.childNodes {
                container.addChildNode(child)
            }
            
            // Настройка спортивных материалов для загруженного меша
            let carbonMat = SCNMaterial()
            carbonMat.diffuse.contents = UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1.0)
            carbonMat.metalness.contents = 0.8
            carbonMat.roughness.contents = 0.25
            
            container.enumerateHierarchy { node, _ in
                if let geo = node.geometry {
                    geo.materials = [carbonMat]
                }
            }
            
            // Масштабируем: в OBJ координаты в дециметрах (длина ~6.8 дм = 68 см)
            // Приводим к масштабу видового окна (масштаб 0.65)
            container.scale = SCNVector3(0.65, 0.65, 0.65)
            
            // В нашей модели tennis_racket.obj основание Butt Cap уже лежит строго в (0, 0, 0)
            // Поэтому вращение родительского RacquetModelNode происходит строго вокруг низа руки!
            addChildNode(container)
            print("[RacquetModelNode] Успешно загружен внешний tennis_racket.obj с точкой вращения в основании руки.")
            return
        }
        
        // Резервный процедурный рендеринг высокой четкости
        buildProceduralRacketWithHandPivot()
    }
    
    /// Создание процедурной ракетки, у которой опорная точка (Pivot)
    /// находится СТРОГО в самом низу рукоятки (y = 0).
    private func buildProceduralRacketWithHandPivot() {
        // ── МАТЕРИАЛЫ ──
        let frameMaterial = SCNMaterial()
        frameMaterial.diffuse.contents = UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1.0)
        frameMaterial.metalness.contents = 0.85
        frameMaterial.roughness.contents = 0.25
        
        let gripMaterial = SCNMaterial()
        gripMaterial.diffuse.contents = UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
        gripMaterial.roughness.contents = 0.95
        
        let capMaterial = SCNMaterial()
        capMaterial.diffuse.contents = UIColor(red: 0.82, green: 0.1, blue: 0.12, alpha: 1.0) // Wilson Red
        
        let accentMaterial = SCNMaterial()
        accentMaterial.diffuse.contents = UIColor(red: 0.0, green: 0.65, blue: 0.95, alpha: 1.0) // Cyan Sport
        accentMaterial.metalness.contents = 0.5
        
        let stringMaterial = SCNMaterial()
        stringMaterial.diffuse.contents = UIColor(red: 0.95, green: 0.95, blue: 0.7, alpha: 0.85)
        stringMaterial.specular.contents = UIColor.white
        
        // ── 1. ОСНОВАНИЕ РУКОЯТКИ (BUTT CAP) ──
        // Располагаем прямо в y = 0.05 (нижний край на y = 0)
        let capHeight: CGFloat = 0.12
        let capGeo = SCNCylinder(radius: 0.185, height: capHeight)
        capGeo.radialSegmentCount = 8
        capGeo.materials = [capMaterial]
        let capNode = SCNNode(geometry: capGeo)
        capNode.position = SCNVector3(0, Float(capHeight / 2.0), 0)
        addChildNode(capNode)
        
        // ── 2. РУКОЯТКА (GRIP) ──
        // Идет вверх от торца: y = 0.12 .. 2.05 (длина 1.93)
        let handleLength: CGFloat = 1.95
        let handleRadius: CGFloat = 0.16
        let handleGeo = SCNCylinder(radius: handleRadius, height: handleLength)
        handleGeo.radialSegmentCount = 8
        handleGeo.materials = [gripMaterial]
        let handleNode = SCNNode(geometry: handleGeo)
        // Центр цилиндра: y = capHeight + handleLength/2
        handleNode.position = SCNVector3(0, Float(capHeight + handleLength / 2.0), 0)
        addChildNode(handleNode)
        
        // Кольцо манжеты (Collar)
        let collarGeo = SCNCylinder(radius: handleRadius * 1.06, height: 0.08)
        let collarMat = SCNMaterial()
        collarMat.diffuse.contents = UIColor.black
        collarGeo.materials = [collarMat]
        let collarNode = SCNNode(geometry: collarGeo)
        collarNode.position = SCNVector3(0, Float(capHeight + handleLength), 0)
        addChildNode(collarNode)
        
        // ── 3. ШЕЙКА (THROAT / ВИЛКА) ──
        let throatStartY = capHeight + handleLength
        let throatLength: CGFloat = 0.95
        let branchGeo = SCNCylinder(radius: 0.07, height: throatLength)
        branchGeo.materials = [frameMaterial]
        
        let leftBranch = SCNNode(geometry: branchGeo)
        leftBranch.position = SCNVector3(-0.25, Float(throatStartY + throatLength / 2.0), 0)
        leftBranch.eulerAngles = SCNVector3(0, 0, 0.28)
        addChildNode(leftBranch)
        
        let rightBranch = SCNNode(geometry: branchGeo)
        rightBranch.position = SCNVector3(0.25, Float(throatStartY + throatLength / 2.0), 0)
        rightBranch.eulerAngles = SCNVector3(0, 0, -0.28)
        addChildNode(rightBranch)
        
        // Мостик шейки
        let bridgeGeo = SCNBox(width: 0.68, height: 0.08, length: 0.11, chamferRadius: 0.03)
        bridgeGeo.materials = [frameMaterial]
        let bridgeNode = SCNNode(geometry: bridgeGeo)
        bridgeNode.position = SCNVector3(0, Float(throatStartY + throatLength - 0.05), 0)
        addChildNode(bridgeNode)
        
        // ── 4. ОБОД (HEAD FRAME) ──
        let headCenterY: Float = Float(throatStartY + throatLength + 1.25)
        let ringRadius: CGFloat = 1.22
        let rimGeo = SCNTorus(ringRadius: ringRadius, pipeRadius: 0.068)
        rimGeo.materials = [accentMaterial]
        
        let rimNode = SCNNode(geometry: rimGeo)
        rimNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        rimNode.scale = SCNVector3(0.92, 1.28, 1.0)
        rimNode.position = SCNVector3(0, headCenterY, 0)
        addChildNode(rimNode)
        
        // Бампер защиты верха обода
        let bumperGeo = SCNTorus(ringRadius: ringRadius * 1.01, pipeRadius: 0.065)
        let bumperMat = SCNMaterial()
        bumperMat.diffuse.contents = UIColor(white: 0.12, alpha: 1.0)
        bumperGeo.materials = [bumperMat]
        let bumperNode = SCNNode(geometry: bumperGeo)
        bumperNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        bumperNode.scale = SCNVector3(0.93, 1.29, 1.0)
        bumperNode.position = SCNVector3(0, headCenterY + 0.02, 0)
        addChildNode(bumperNode)
        
        // ── 5. СТРУННАЯ СЕТКА (STRING BED) ──
        let stringsNode = SCNNode()
        let stringThickness: CGFloat = 0.008
        let ax: CGFloat = ringRadius * 0.92 * 0.92
        let by: CGFloat = ringRadius * 1.28 * 0.92
        
        let mainCount = 14
        let xs = stride(from: -ax * 0.82, through: ax * 0.82, by: (ax * 1.64) / CGFloat(mainCount))
        for x in xs {
            let ratio = x / ax
            let val = 1.0 - ratio * ratio
            if val > 0 {
                let dy = by * sqrt(val) * 0.94
                let sGeo = SCNCylinder(radius: stringThickness, height: dy * 2.0)
                sGeo.materials = [stringMaterial]
                let sNode = SCNNode(geometry: sGeo)
                sNode.position = SCNVector3(Float(x), headCenterY, 0)
                stringsNode.addChildNode(sNode)
            }
        }
        
        let crossCount = 16
        let ys = stride(from: -by * 0.82, through: by * 0.82, by: (by * 1.64) / CGFloat(crossCount))
        for y in ys {
            let ratio = y / by
            let val = 1.0 - ratio * ratio
            if val > 0 {
                let dx = ax * sqrt(val) * 0.94
                let sGeo = SCNCylinder(radius: stringThickness, height: dx * 2.0)
                sGeo.materials = [stringMaterial]
                let sNode = SCNNode(geometry: sGeo)
                sNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
                sNode.position = SCNVector3(0, Float(CGFloat(headCenterY) + y), 0)
                stringsNode.addChildNode(sNode)
            }
        }
        
        addChildNode(stringsNode)
    }
    
    /// Обновление ориентации ракетки от кватерниона.
    /// Вращение узла `RacquetModelNode` автоматически вращает всю конструкцию вокруг точки (0, 0, 0) —
    /// то есть вокруг основания ладони/рукоятки!
    public func updateOrientation(_ quaternion: simd_quatf) {
        self.simdOrientation = quaternion
    }
}
