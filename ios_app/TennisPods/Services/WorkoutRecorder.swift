import Foundation
import CoreMotion
import Combine

/// Сервис записи всех показателей телеметрии с AirPods в единый CSV файл.
public final class WorkoutRecorder: ObservableObject {
    public static let shared = WorkoutRecorder()
    
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var recordedSampleCount: Int = 0
    @Published public private(set) var recordingDuration: TimeInterval = 0.0
    @Published public private(set) var lastUploadStatus: String? = nil
    
    private var recordBuffer: [String] = []
    private var startTime: Date?
    private var timer: Timer?
    
    // Заголовки всех возможных данных с IMU AirPods
    private let csvHeader = """
    timestamp,elapsed_sec,qw,qx,qy,qz,roll_rad,pitch_rad,yaw_rad,rot_x_rad_s,rot_y_rad_s,rot_z_rad_s,user_accel_x,user_accel_y,user_accel_z,gravity_x,gravity_y,gravity_z
    """
    
    private init() {}
    
    /// Начать запись сессии
    public func startRecording() {
        guard !isRecording else { return }
        
        recordBuffer.removeAll()
        recordBuffer.append(csvHeader)
        
        let now = Date()
        self.startTime = now
        self.isRecording = true
        self.recordedSampleCount = 0
        self.recordingDuration = 0.0
        self.lastUploadStatus = nil
        
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, let start = self.startTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }
    
    /// Добавление полного набора показателей в буфер записи
    public func recordSample(motion: CMDeviceMotion) {
        guard isRecording, let start = startTime else { return }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(start)
        let ts = now.timeIntervalSince1970
        
        // Кватернион
        let q = motion.attitude.quaternion
        // Углы Эйлера
        let roll = motion.attitude.roll
        let pitch = motion.attitude.pitch
        let yaw = motion.attitude.yaw
        
        // Угловая скорость (гироскоп)
        let rot = motion.rotationRate
        // Пользовательское ускорение (без гравитации)
        let uAcc = motion.userAcceleration
        // Вектор гравитации
        let grav = motion.gravity
        
        let line = String(
            format: "%.4f,%.4f,%.6f,%.6f,%.6f,%.6f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f",
            ts, elapsed,
            q.w, q.x, q.y, q.z,
            roll, pitch, yaw,
            rot.x, rot.y, rot.z,
            uAcc.x, uAcc.y, uAcc.z,
            grav.x, grav.y, grav.z
        )
        
        recordBuffer.append(line)
        DispatchQueue.main.async {
            self.recordedSampleCount += 1
        }
    }
    
    /// Завершить запись сессии и отправить файл на GitHub
    public func stopRecording(uploadToGitHub: Bool = true, completion: @escaping (Result<String, Error>) -> Void) {
        guard isRecording else { return }
        
        timer?.invalidate()
        timer = nil
        self.isRecording = false
        
        let csvContent = recordBuffer.joined(separator: "\n")
        guard let data = csvContent.data(using: .utf8) else {
            completion(.failure(NSError(domain: "WorkoutRecorder", code: 400, userInfo: [NSLocalizedDescriptionKey: "Ошибка кодирования данных"])))
            return
        }
        
        // Имя файла по дате и времени
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestampStr = formatter.string(from: startTime ?? Date())
        let fileName = "workout_\(timestampStr).csv"
        
        // Сохраняем локально в Documents директорию на случай отсутствия интернета
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let localURL = docs.appendingPathComponent(fileName)
            try? data.write(to: localURL)
            print("[WorkoutRecorder] Сохранен локальный файл: \(localURL.path)")
        }
        
        if uploadToGitHub {
            DispatchQueue.main.async {
                self.lastUploadStatus = "Выгрузка на GitHub..."
            }
            GitHubUploader.shared.uploadWorkout(fileData: data, fileName: fileName) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let url):
                        self?.lastUploadStatus = "Успешно выгружено: \(fileName)"
                        completion(.success(url))
                    case .failure(let error):
                        self?.lastUploadStatus = "Ошибка выгрузки: \(error.localizedDescription)"
                        completion(.failure(error))
                    }
                }
            }
        } else {
            completion(.success("Сохранено локально"))
        }
    }
}
