import Foundation
import CoreMotion
import Combine
import simd

/// Менеджер отслеживания движения AirPods и калибровки ориентации ракетки.
public final class MotionManager: NSObject, ObservableObject {
    
    // MARK: - Published States
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var isAvailable: Bool = false
    @Published public private(set) var currentOrientation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    
    // Метрики для UI оверлея
    @Published public private(set) var pitchDeg: Float = 0.0
    @Published public private(set) var rollDeg: Float = 0.0
    @Published public private(set) var yawDeg: Float = 0.0
    @Published public private(set) var angularVelocityMagnitude: Float = 0.0 // рад/с
    
    // Состояние калибровки
    @Published public private(set) var isCalibrated: Bool = false
    @Published public private(set) var calibrationCountdown: Int = 0
    
    // MARK: - CoreMotion Components
    private let headphoneMotionManager = CMHeadphoneMotionManager()
    private let queue = OperationQueue()
    
    // Кватернион калибровки (Zeroing / Tare)
    private var referenceQuaternion: simd_quatf? = nil
    
    // Буфер для усреднения во время калибровки
    private var calibrationBuffer: [simd_quatf] = []
    private var isBufferingCalibration: Bool = false
    
    public override init() {
        super.init()
        queue.name = "com.tennispods.motionQueue"
        queue.qualityOfService = .userInteractive
        checkAvailability()
    }
    
    deinit {
        stopUpdates()
    }
    
    // MARK: - Public Control Methods
    
    /// Проверка доступности CoreMotion для наушников
    public func checkAvailability() {
        DispatchQueue.main.async {
            self.isAvailable = self.headphoneMotionManager.isDeviceMotionAvailable
        }
    }
    
    /// Запуск стриминга данных с частотой 60 Гц
    public func startUpdates() {
        // Удержание AirPods в активном состоянии без датчика уха
        AudioKeepAliveService.shared.start()
        
        guard headphoneMotionManager.isDeviceMotionAvailable else {
            DispatchQueue.main.async {
                self.isAvailable = false
                self.isConnected = false
            }
            return
        }
        
        headphoneMotionManager.delegate = self
        
        // Запуск потока обновлений
        headphoneMotionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else {
                return
            }
            // Запись в активную тренировку
            WorkoutRecorder.shared.recordSample(motion: motion)
            self.processMotion(motion)
        }
        
        DispatchQueue.main.async {
            self.isAvailable = true
            self.isConnected = self.headphoneMotionManager.isDeviceMotionActive
        }
    }
    
    /// Остановка стриминга
    public func stopUpdates() {
        if headphoneMotionManager.isDeviceMotionActive {
            headphoneMotionManager.stopDeviceMotionUpdates()
        }
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
    
    /// Запуск процедуры калибровки с обратным отсчетом (3 секунды)
    public func startCalibrationCountdown() {
        guard !isBufferingCalibration else { return }
        
        DispatchQueue.main.async {
            self.calibrationCountdown = 3
        }
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            DispatchQueue.main.async {
                if self.calibrationCountdown > 1 {
                    self.calibrationCountdown -= 1
                } else {
                    timer.invalidate()
                    self.calibrationCountdown = 0
                    self.captureCalibrationSamples()
                }
            }
        }
    }
    
    /// Мгновенное тарирование (Fast Zeroing)
    public func instantCalibrate() {
        calibrationBuffer.removeAll()
        isBufferingCalibration = true
        
        // Собираем данные в течение 0.3 секунды для фильтрации микровибраций
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.finishCalibration()
        }
    }
    
    /// Сброс калибровки в сырой вид
    public func resetCalibration() {
        referenceQuaternion = nil
        DispatchQueue.main.async {
            self.isCalibrated = false
        }
    }
    
    // MARK: - Private Pipeline
    
    private func captureCalibrationSamples() {
        calibrationBuffer.removeAll()
        isBufferingCalibration = true
        
        // Запись 0.5 сек для надежного сглаживания
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.finishCalibration()
        }
    }
    
    private func finishCalibration() {
        isBufferingCalibration = false
        guard !calibrationBuffer.isEmpty else { return }
        
        // Вычисление среднего кватерниона
        let averaged = averageQuaternions(calibrationBuffer)
        self.referenceQuaternion = averaged
        
        DispatchQueue.main.async {
            self.isCalibrated = true
        }
    }
    
    private func processMotion(_ motion: CMDeviceMotion) {
        let q = motion.attitude.quaternion
        
        // 1. Преобразование кватерниона CoreMotion в SIMD
        // CoreMotion: x - вправо, y - вверх/вперед, z - наружу
        let rawQuat = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
        
        // Накопление сэмплов для калибровки
        if isBufferingCalibration {
            calibrationBuffer.append(rawQuat)
        }
        
        // 2. Калибровочное смещение (Tare/Zeroing)
        // q_rel = q_ref^-1 * q_current
        var calibratedQuat: simd_quatf
        if let ref = referenceQuaternion {
            let refInv = simd_inverse(ref)
            calibratedQuat = simd_mul(refInv, rawQuat)
        } else {
            calibratedQuat = rawQuat
        }
        
        // 3. Согласование систем координат CoreMotion -> SceneKit
        // В CoreMotion нейтральная ориентация может иметь ось Y вдоль тела наушника.
        // Для SceneKit: ось +Y направлена вертикально вверх (вдоль шейки и ручки ракетки),
        // ось +Z направлена к камере (нормаль струн), ось +X — вправо.
        // Вращение системы координат на 90 градусов вокруг X, чтобы ось ракетки стояла ровно.
        let coordinateFix = simd_quatf(angle: -.pi / 2, axis: simd_float3(1, 0, 0))
        let finalSceneKitQuat = simd_mul(calibratedQuat, coordinateFix)
        
        // 4. Расчет угловой скорости
        let rotRate = motion.rotationRate
        let omega = sqrt(Float(rotRate.x * rotRate.x + rotRate.y * rotRate.y + rotRate.z * rotRate.z))
        
        // 5. Вычисление углов Эйлера (в градусах) для телеметрии
        let euler = toEulerAngles(finalSceneKitQuat)
        
        DispatchQueue.main.async {
            self.isConnected = true
            self.currentOrientation = finalSceneKitQuat
            self.angularVelocityMagnitude = omega
            self.pitchDeg = euler.pitch * (180.0 / .pi)
            self.rollDeg = euler.roll * (180.0 / .pi)
            self.yawDeg = euler.yaw * (180.0 / .pi)
        }
    }
    
    // MARK: - Математика кватернионов
    
    /// Усреднение массива кватернионов с учетом полусферы (dot product)
    private func averageQuaternions(_ quats: [simd_quatf]) -> simd_quatf {
        guard let first = quats.first else { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
        var sumVector = simd_float4(first.vector)
        
        for i in 1..<quats.count {
            var v = simd_float4(quats[i].vector)
            // Проверка знака скалярного произведения, чтобы оставаться на одной полусфере
            if simd_dot(v, sumVector) < 0 {
                v = -v
            }
            sumVector += v
        }
        
        let norm = simd_length(sumVector)
        if norm > 1e-6 {
            sumVector /= norm
            return simd_quatf(vector: sumVector)
        }
        return first
    }
    
    /// Перевод кватерниона в углы Эйлера (Roll, Pitch, Yaw)
    private func toEulerAngles(_ q: simd_quatf) -> (roll: Float, pitch: Float, yaw: Float) {
        let w = q.real
        let x = q.imag.x
        let y = q.imag.y
        let z = q.imag.z
        
        // Roll (вокруг оси X)
        let sinr_cosp = 2 * (w * x + y * z)
        let cosr_cosp = 1 - 2 * (x * x + y * y)
        let roll = atan2(sinr_cosp, cosr_cosp)
        
        // Pitch (вокруг оси Y)
        let sinp = 2 * (w * y - z * x)
        let pitch: Float
        if abs(sinp) >= 1 {
            pitch = copysign(.pi / 2, sinp)
        } else {
            pitch = asin(sinp)
        }
        
        // Yaw (вокруг оси Z)
        let siny_cosp = 2 * (w * z + x * y)
        let cosy_cosp = 1 - 2 * (y * y + z * z)
        let yaw = atan2(siny_cosp, cosy_cosp)
        
        return (roll, pitch, yaw)
    }
}

// MARK: - CMHeadphoneMotionManagerDelegate
extension MotionManager: CMHeadphoneMotionManagerDelegate {
    public func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async {
            self.isConnected = true
        }
    }
    
    public func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}
