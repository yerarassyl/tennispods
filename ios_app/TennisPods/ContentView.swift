import SwiftUI
import SceneKit
import simd

// MARK: - SceneKit Container
struct RacquetSceneContainerView: UIViewRepresentable {
    @ObservedObject var motionManager: MotionManager
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1.0)
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = true
        scnView.autoenablesDefaultLighting = false
        
        let scene = SCNScene()
        scnView.scene = scene
        
        // Камера: отдалена и сфокусирована так, чтобы видеть вращение ракетки от основания руки вверх
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 100.0
        cameraNode.position = SCNVector3(0, 1.6, 7.6)
        scene.rootNode.addChildNode(cameraNode)
        
        // Освещение (Студийный свет для реалистичного карбона и струн)
        let mainLight = SCNNode()
        mainLight.light = SCNLight()
        mainLight.light?.type = .directional
        mainLight.light?.intensity = 1200
        mainLight.light?.castsShadow = true
        mainLight.position = SCNVector3(4, 9, 7)
        mainLight.look(at: SCNVector3(0, 1.8, 0))
        scene.rootNode.addChildNode(mainLight)
        
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 400
        ambientLight.light?.color = UIColor(red: 0.75, green: 0.82, blue: 0.95, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
        
        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .omni
        rimLight.light?.intensity = 700
        rimLight.position = SCNVector3(-3.5, 3.5, -4.5)
        scene.rootNode.addChildNode(rimLight)
        
        // 3D сетка пола (находится ровно под нижней точкой рукоятки y = 0)
        let floorGridNode = createFloorGrid()
        floorGridNode.position = SCNVector3(0, -0.05, 0)
        scene.rootNode.addChildNode(floorGridNode)
        
        // Реалистичная ракетка (точка опоры y=0 в основании рукоятки)
        let racquet = RacquetModelNode()
        racquet.name = "racquetNode"
        racquet.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(racquet)
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        if let racquet = uiView.scene?.rootNode.childNode(withName: "racquetNode", recursively: false) as? RacquetModelNode {
            racquet.updateOrientation(motionManager.currentOrientation)
        }
    }
    
    private func createFloorGrid() -> SCNNode {
        let rootGrid = SCNNode()
        let gridSize: Float = 6.4
        let step: Float = 0.64
        let lineRadius: CGFloat = 0.007
        
        let gridMaterial = SCNMaterial()
        gridMaterial.diffuse.contents = UIColor(white: 0.28, alpha: 0.5)
        
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

// MARK: - Главный Экран SwiftUI
public struct ContentView: View {
    @StateObject private var motionManager = MotionManager()
    @ObservedObject private var recorder = WorkoutRecorder.shared
    
    @State private var showSettings: Bool = false
    @State private var githubToken: String = GitHubUploader.shared.personalAccessToken
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // 3D SceneKit Canvas
            RacquetSceneContainerView(motionManager: motionManager)
                .edgesIgnoringSafeArea(.all)
            
            // Верхний статус-бар и настройки
            VStack {
                HStack(spacing: 10) {
                    connectionBadge
                    Spacer()
                    recordingBadge
                    settingsButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                
                // Статус последней выгрузки (если есть)
                if let status = recorder.lastUploadStatus {
                    Text(status)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(12)
                        .padding(.top, 6)
                        .transition(.opacity)
                }
                
                Spacer()
                
                // Обратный отсчет калибровки
                if motionManager.calibrationCountdown > 0 {
                    countdownBanner
                }
                
                // Нижняя панель тренировки и управления
                dashboardPanel
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Тренировка"), message: Text(alertMessage ?? ""), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            motionManager.startUpdates()
        }
        .onDisappear {
            motionManager.stopUpdates()
        }
    }
    
    // MARK: - Компоненты UI
    
    private var connectionBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(motionManager.isConnected ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
                .shadow(color: motionManager.isConnected ? .green : .orange, radius: 4)
            
            Text(motionManager.isConnected ? "AirPods Активны" : "Поиск AirPods...")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
    
    private var recordingBadge: some View {
        Group {
            if recorder.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(timeString(from: recorder.recordingDuration))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.red.opacity(0.25))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.red, lineWidth: 1))
            }
        }
    }
    
    private var settingsButton: some View {
        Button(action: { showSettings.toggle() }) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.85))
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
    
    private var countdownBanner: some View {
        VStack(spacing: 6) {
            Text("Калибровка нейтрали")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.yellow)
            
            Text("\(motionManager.calibrationCountdown)")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundColor(.white)
            
            Text("Держите ракетку вертикально струнами к экрану")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.yellow.opacity(0.5), lineWidth: 1.5))
        .padding(.bottom, 16)
    }
    
    private var dashboardPanel: some View {
        VStack(spacing: 12) {
            // Телеметрия углов и угловой скорости
            HStack(spacing: 8) {
                metricCell(title: "Pitch", value: String(format: "%+.1f°", motionManager.pitchDeg))
                metricCell(title: "Roll", value: String(format: "%+.1f°", motionManager.rollDeg))
                metricCell(title: "Yaw", value: String(format: "%+.1f°", motionManager.yawDeg))
                metricCell(title: "Сэмплы", value: "\(recorder.recordedSampleCount)")
            }
            
            // Главная кнопка Записи Тренировки
            Button(action: {
                toggleRecording()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 20))
                    Text(recorder.isRecording ? "Завершить и выгрузить на GitHub" : "Начать запись тренировки")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(recorder.isRecording ? Color.red : Color.green)
                .cornerRadius(14)
            }
            
            // Кнопки калибровки
            HStack(spacing: 10) {
                Button(action: { motionManager.startCalibrationCountdown() }) {
                    HStack {
                        Image(systemName: "timer")
                        Text("Калибровка (3 сек)")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.blue)
                    .cornerRadius(11)
                }
                
                Button(action: { motionManager.instantCalibrate() }) {
                    Text("Быстрый Tare")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.18))
                        .cornerRadius(11)
                }
                
                Button(action: { motionManager.resetCalibration() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(11)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(22)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
    
    private func metricCell(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.35))
        .cornerRadius(9)
    }
    
    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stopRecording(uploadToGitHub: true) { result in
                switch result {
                case .success(let link):
                    alertMessage = "Тренировка успешно сохранена и отправлена на GitHub в папку records/!\n\(link)"
                    showAlert = true
                case .failure(let err):
                    alertMessage = "Файл сохранен локально. Ошибка выгрузки на GitHub: \(err.localizedDescription)\nПроверьте GitHub Token в настройках."
                    showAlert = true
                }
            }
        } else {
            recorder.startRecording()
        }
    }
    
    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Выгрузка на GitHub (records/)")) {
                    Text("Репозиторий: yerarassyl/tennispods")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    SecureField("GitHub Personal Access Token (PAT)", text: $githubToken)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Button("Сохранить токен") {
                        GitHubUploader.shared.personalAccessToken = githubToken
                        showSettings = false
                    }
                    .font(.system(size: 14, weight: .bold))
                }
                
                Section(header: Text("AirPods Сенсор (Вне ушей)")) {
                    Text("• Функция AudioKeepAlive активирована автоматически.\n• В настройках iOS отключите: «Автообнаружение уха» (Automatic Ear Detection) в меню Bluetooth -> AirPods.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarItems(trailing: Button("Готово") { showSettings = false })
        }
    }
    
    private func timeString(from duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
