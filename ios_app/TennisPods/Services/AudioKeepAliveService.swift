import Foundation
import AVFoundation

/// Сервис предотвращения отключения AirPods вне ушей.
/// Проигрывает ультра-тихий (неслышимый человеку) аудиотрек в цикле,
/// сообщая iOS, что сессия аудио активна и наушники не должны засыпать.
public final class AudioKeepAliveService {
    public static let shared = AudioKeepAliveService()
    
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isRunning: Bool = false
    
    private init() {}
    
    public func start() {
        guard !isRunning else { return }
        
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback режим позволяет держать AirPods в активном состоянии связи
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
            
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            
            // Генерируем буфер с почти нулевой амплитудой (16-битный PCM тишины)
            let sampleRate: Double = 44100.0
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
            let frameCount = AVAudioFrameCount(sampleRate * 2.0) // 2 секунды
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
            buffer.frameLength = frameCount
            
            // Заполняем минимальным неслышимым белым шумом или тишиной
            if let floatData = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    for frame in 0..<Int(frameCount) {
                        floatData[channel][frame] = 0.00001 // Неслышимый уровень
                    }
                }
            }
            
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.01 // Минимальная громкость микшера
            
            try engine.start()
            player.play()
            player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            
            self.audioEngine = engine
            self.playerNode = player
            self.isRunning = true
            print("[AudioKeepAlive] Запущен аудио-поток для удержания AirPods в активном режиме.")
        } catch {
            print("[AudioKeepAlive] Ошибка запуска аудио сессии: \(error.localizedDescription)")
        }
    }
    
    public func stop() {
        guard isRunning else { return }
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false)
        print("[AudioKeepAlive] Остановлен.")
    }
}
