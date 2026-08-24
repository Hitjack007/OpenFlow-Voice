import OSLog

enum Log {
    static let audio = Logger(subsystem: "com.Hitjack007.OpenFlow-Voice", category: "audio")
    static let speech = Logger(subsystem: "com.Hitjack007.OpenFlow-Voice", category: "speech")
    static let hotkey = Logger(subsystem: "com.Hitjack007.OpenFlow-Voice", category: "hotkey")
    static let inject = Logger(subsystem: "com.Hitjack007.OpenFlow-Voice", category: "inject")
    static let app = Logger(subsystem: "com.Hitjack007.OpenFlow-Voice", category: "app")
}
