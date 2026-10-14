import os

enum Log {
    static let app = Logger(subsystem: "com.kikorsilva.localflow", category: "app")
    static let audio = Logger(subsystem: "com.kikorsilva.localflow", category: "audio")
    static let hotkey = Logger(subsystem: "com.kikorsilva.localflow", category: "hotkey")
    static let pipeline = Logger(subsystem: "com.kikorsilva.localflow", category: "pipeline")
}
