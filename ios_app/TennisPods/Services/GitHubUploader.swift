import Foundation

/// Модуль выгрузки логов тренировок в GitHub репозиторий yerarassyl/tennispods
/// в директорию `records/`.
public final class GitHubUploader {
    public static let shared = GitHubUploader()
    
    // Владелец и репозиторий
    private let owner = "yerarassyl"
    private let repo = "tennispods"
    
    // Токен можно задать в настройках приложения или через UserDefaults
    // При сборке по умолчанию можно использовать токен или ввести его прямо в UI
    public var personalAccessToken: String {
        get {
            UserDefaults.standard.string(forKey: "github_pat") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "github_pat")
        }
    }
    
    private init() {}
    
    /// Выгружает файл тренировки на GitHub через GitHub Contents API
    /// - Parameters:
    ///   - fileData: Содержимое файла CSV / JSON
    ///   - fileName: Имя файла (например, `session_2026-10-06_17-15-00.csv`)
    ///   - completion: Результат выгрузки (Success URL или Error)
    public func uploadWorkout(
        fileData: Data,
        fileName: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let base64Content = fileData.base64EncodedString()
        let path = "records/\(fileName)"
        
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)") else {
            completion(.failure(NSError(domain: "GitHubUploader", code: 400, userInfo: [NSLocalizedDescriptionKey: "Неверный URL API"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        let token = personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "message": "Upload tennis workout session: \(fileName)",
            "content": base64Content,
            "branch": "main"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "GitHubUploader", code: 500, userInfo: [NSLocalizedDescriptionKey: "Пустой ответ сервера"])))
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                let successMsg = "https://github.com/\(self.owner)/\(self.repo)/blob/main/\(path)"
                completion(.success(successMsg))
            } else {
                let serverError = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
                completion(.failure(NSError(domain: "GitHubUploader", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: serverError])))
            }
        }.resume()
    }
}
