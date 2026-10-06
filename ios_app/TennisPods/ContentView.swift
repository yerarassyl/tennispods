import SwiftUI
import SceneKit
import simd

// MARK: - SceneKit UIViewRepresentable
struct RacquetSceneContainerView: UIViewRepresentable {
    @ObservedObject var motionManager: MotionManager
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = true
        scnView.autoenablesDefaultLighting = false
        
        let scene = SCNScene()
        scnView.scene = scene
        
        // 1. Камера
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 100.0
        cameraNode.position = SCNVector3(0, 0.8, 6.2)
        scene.rootNode.addChildNode(cameraNode)
        
        // 2. Освещение
        // Направленный свет (Sun / Key Light)
        let mainLight = SCNNode()
        mainLight.light = SCNLight()
        mainLight.light?.type = .directional
        mainLight.light?.intensity = 1100
        mainLight.light?.castsShadow = true
        mainLight.position = SCNVector3(4, 8, 6)
        mainLight.look(at: SCNVector3(0, 0.5, 0))
        scene.rootNode.addChildNode(mainLight)
        
        // Заполняющий свет (Fill Ambient Light)
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 350
        ambientLight.light?.color = UIColor(red: 0.7, green: 0.8, blue: 0.95, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
        
        // Контровой свет (Rim Light) сзади ракетки
        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .omni
        rimLight.light?.intensity = 600
        rimLight.position = SCNVector3(-3, 3, -4)
        scene.rootNode.addChildNode(rimLight)
        
        // 3. Координатная пространственная сетка пола
        let floorGridNode = createFloorGrid()
        floorGridNode.position = SCNVector3(0, -2.6, 0)
        scene.rootNode.addChildNode(floorGridNode)
        
        // 4. Модель ракетки
        let racquet = RacquetModelNode()
        racquet.name = "racquetNode"
        racquet.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(racquet)
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        if let racquet = uiView.scene?.rootNode.childNode(withName: "racquetNode", recursively: false) as? RacquetModelNode {
            // Мгновенное прямое обновление кватерниона сцены через SIMD
            racquet.updateOrientation(motionManager.currentOrientation)
        }
    }
    
    /// Генерация 3D сетки для пола
    private func createFloorGrid() -> SCNNode {
        let rootGrid = SCNNode()
        let gridSize: Float = 6.0
        let step: Float = 0.6
        let lineRadius: CGFloat = 0.008
        
        let gridMaterial = SCNMaterial()
        gridMaterial.diffuse.contents = UIColor(white: 0.28, alpha: 0.6)
        
        var z = -gridSize / 2
        while z <= gridSize / 2 {
            let lineGeo = SCNCylinder(radius: lineRadius, height: CGFloat(gridSize))
            lineGeo.materials = [gridMaterial]
            let lineNode = SCNNode(geometry: lineGeo)
            lineNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
            lineNode.position = SCNVector3(0, 0, z)
            rootGrid.addChildNode(lineNode)
            z += step
        }
        
        var x = -gridSize / 2
        while x <= gridSize / 2 {
            let lineGeo = SCNCylinder(radius: lineRadius, height: CGFloat(gridSize))
            lineGeo.materials = [gridMaterial]
            let lineNode = SCNNode(geometry: lineGeo)
            lineNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
            lineNode.position = SCNVector3(x, 0, 0)
            rootGrid.addChildNode(lineNode)
            x += step
        }
        
        return rootGrid
    }
}

// MARK: - Главный UI Экран
public struct ContentView: View {
    @StateObject private var motionManager = MotionManager()
    @State private var showCalibrationAlert = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // 3D Рендерер
            RacquetSceneContainerView(motionManager: motionManager)
                .edgesIgnoringSafeArea(.all)
            
            // Верхний HUD (Статус соединения)
            VStack {
                HStack {
                    connectionBadge
                    Spacer()
                    calibrationBadge
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Spacer()
                
                // Обратный отсчет калибровки на экране
                if motionManager.calibrationCountdown > 0 {
                    countdownBanner
                }
                
                // Нижняя панель управления и телеметрии
                controlAndTelemetryDashboard
            }
        }
        .onAppear {
            motionManager.startUpdates()
        }
        .onDisappear {
            motionManager.stopUpdates()
        }
    }
    
    // MARK: - View Components
    
    private var connectionBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(motionManager.isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: motionManager.isConnected ? .green.opacity(0.8) : .red.opacity(0.8), radius: 4)
            
            Text(motionManager.isConnected ? "AirPods Подключены" : "Поиск AirPods...")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
    
    private var calibrationBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: motionManager.isCalibrated ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(motionManager.isCalibrated ? .green : .orange)
            
            Text(motionManager.isCalibrated ? "Откалибровано" : "Не откалибровано")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
    
    private var countdownBanner: some View {
        VStack(spacing: 8) {
            Text("Удерживайте ракетку неподвижно!")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.yellow)
            
            Text("\(motionManager.calibrationCountdown)")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .scaleEffect(1.2)
                .animation(.easeInOut(duration: 0.3), value: motionManager.calibrationCountdown)
            
            Text("Вертикально: обод вверх, струны к экрану")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.yellow.opacity(0.6), lineWidth: 2)
        )
        .padding(.bottom, 20)
    }
    
    private var controlAndTelemetryDashboard: some View {
        VStack(spacing: 16) {
            // Телеметрия углов и угловой скорости
            HStack(spacing: 12) {
                telemetryCard(title: "Pitch", value: String(format: "%+.1f°", motionManager.pitchDeg), icon: "arrow.up.and.down")
                telemetryCard(title: "Roll", value: String(format: "%+.1f°", motionManager.rollDeg), icon: "arrow.left.and.right")
                telemetryCard(title: "Yaw", value: String(format: "%+.1f°", motionManager.yawDeg), icon: "arrow.triangle.2.circlepath")
                telemetryCard(title: "Скорость", value: String(format: "%.1f", motionManager.angularVelocityMagnitude), unit: "рад/с", icon: "speedometer")
            }
            
            // Кнопки калибровки
            HStack(spacing: 14) {
                Button(action: {
                    motionManager.startCalibrationCountdown()
                }) {
                    HStack {
                        Image(systemName: "timer")
                        Text("Калибровка (3 сек)")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(14)
                }
                
                Button(action: {
                    motionManager.instantCalibrate()
                }) {
                    HStack {
                        Image(systemName: "scope")
                        Text("Быстрый Tare")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(14)
                }
                
                Button(action: {
                    motionManager.resetCalibration()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(14)
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
    
    private func telemetryCard(title: String, value: String, unit: String? = nil, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            if let unit = unit {
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
        .cornerRadius(10)
    }
}
