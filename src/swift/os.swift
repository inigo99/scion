// The os overlay: OSLog, OSLogType and os_log(...) on top of the unified log of os/log.h (scion keeps no log:
// os_log_type_enabled is false). Apple's overlay has the same declarations, so compiled apps bind to these.
@_exported import os

extension OSLogType {
    public static var `default`: OSLogType { OSLogType(rawValue: 0x00) }
    public static var info: OSLogType { OSLogType(rawValue: 0x01) }
    public static var debug: OSLogType { OSLogType(rawValue: 0x02) }
    public static var error: OSLogType { OSLogType(rawValue: 0x10) }
    public static var fault: OSLogType { OSLogType(rawValue: 0x11) }
}

extension OSLog {
    public static let `default` = OSLog(subsystem: "", category: "")
    public static let disabled = OSLog(subsystem: "", category: "")
    public convenience init(subsystem: String, category: String) {
        self.init(__subsystem: subsystem, category: category)
    }
}

/// scion keeps no log, so the message and its arguments are not formatted
public func os_log(_ message: StaticString, dso: UnsafeRawPointer? = #dsohandle, log: OSLog = .default, type: OSLogType = .default, _ args: CVarArg...) {}
public func os_log(_ type: OSLogType, dso: UnsafeRawPointer = #dsohandle, log: OSLog = .default, _ message: StaticString, _ args: CVarArg...) {}
