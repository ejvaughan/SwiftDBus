import Clibdbus
import Dispatch

public enum _DBusType: Int32 {
    case byte = 121
    case boolean = 98
    case int16 = 110
    case uint16 = 113
    case int32 = 105
    case uint32 = 117
    case int64 = 120
    case uint64 = 116
    case double = 100
    case string = 115
    case objectPath = 111
    case signature = 103
    case unixFD = 104
    case array = 97
    case variant = 118
    case `struct` = 114
    case dictEntry = 101
    case invalid = 0
}

public protocol DBusRepresentable {
    static var _dbusType: _DBusType { get }
    static var _dbusTypeSignature: String { get }
    func _append(to iter: UnsafeMutablePointer<DBusMessageIter>)
}

extension DBusRepresentable {
    public static var _dbusTypeSignature: String {
        return String(Character(UnicodeScalar(UInt32(self._dbusType.rawValue))!))
    }
}

public protocol DBusBasicType: DBusRepresentable, Hashable { }

extension DBusBasicType {
    public func _append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        var val = self
        withUnsafeBytes(of: &val) {
            _ = dbus_message_iter_append_basic(iter, type(of: val)._dbusType.rawValue, $0.baseAddress!)
        }
    }
}

public protocol DBusStruct: DBusRepresentable {
    static var fieldTypes: [DBusRepresentable.Type] { get }
    var fieldValues: [DBusRepresentable] { get }
}

extension DBusStruct {
    static var _dbusType: _DBusType {
        return .struct
    }
    
    static var _dbusTypeSignature: String {
        return "(" + fieldTypes.map({$0._dbusTypeSignature}).joined(separator: "") + ")"
    }
    
    func _append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        var subIter = DBusMessageIter()
        dbus_message_iter_open_container(iter, type(of: self)._dbusType.rawValue, nil, &subIter)
        for value in fieldValues {
            value._append(to: &subIter)
        }
        dbus_message_iter_close_container(iter, &subIter)
    }
}

func getValue(_ iter: UnsafeMutablePointer<DBusMessageIter>) -> Any {
    guard let type = _DBusType(rawValue: dbus_message_iter_get_arg_type(iter)), type != .invalid else { fatalError() }
    defer {
        dbus_message_iter_next(iter)
    }
    
    switch type {
    case .byte:
        var val: UInt8 = 0
        dbus_message_iter_get_basic(iter, &val)
        return val
    case .boolean:
        var val: dbus_bool_t = 0
        dbus_message_iter_get_basic(iter, &val)
        return val > 0
    case .int16:
        var val: Int16 = 0
        dbus_message_iter_get_basic(iter, &val)
        return val
    case .uint16:
        var val: UInt16 = 0
        dbus_message_iter_get_basic(iter, &val)
        return val
    case .int32:
        fallthrough
    case .unixFD:
        var val: Int32 = 0
        dbus_message_iter_get_basic(iter, &val)
        return val
    case .uint32:
        var val: UInt32 = 0
        dbus_message_iter_get_basic(iter, &val)
        return val
    case .int64:
        var val: Int64 = 0
        dbus_message_iter_get_basic(iter, &val)
        return val
    case .uint64:
        var val: UInt64 = 0
        dbus_message_iter_get_basic(iter, &val)
        return val
    case .double:
        var val: Double = 0
        dbus_message_iter_get_basic(iter, &val)
        return val
    case .string:
        var str: UnsafePointer<Int8>? = nil
        dbus_message_iter_get_basic(iter, &str)
        return str.flatMap({ String(cString: $0) }) ?? ""
    case .objectPath:
        var str: UnsafePointer<Int8>? = nil
        dbus_message_iter_get_basic(iter, &str)
        return DBusObjectPath(str.flatMap({ String(cString: $0) }) ?? "")
    case .variant:
        var subIter = DBusMessageIter()
        dbus_message_iter_recurse(iter, &subIter)
        return getValue(&subIter)
    case .array:
        fallthrough
    case .struct:
        var values = [Any]()
        var subIter = DBusMessageIter()
        dbus_message_iter_recurse(iter, &subIter)
        
        while _DBusType(rawValue: dbus_message_iter_get_arg_type(&subIter))! != .invalid {
            values.append(getValue(&subIter))
        }
        
        if type == .array && _DBusType(rawValue: dbus_message_iter_get_element_type(iter))! == .dictEntry {
            if let entries = values as? [(AnyHashable, Any)] {
                var dict: [AnyHashable:Any] = [:]
                for entry in entries {
                    dict[entry.0] = entry.1
                }
                return dict
            } else {
                fatalError()
            }
        }
        
        return values
    case .dictEntry:
        var subIter = DBusMessageIter()
        dbus_message_iter_recurse(iter, &subIter)
        return (getValue(&subIter), getValue(&subIter))
    default:
        break
    }
    
    fatalError()
}

extension UInt8: DBusBasicType {
    public static var _dbusType: _DBusType {
        return .byte
    }
}

extension Bool: DBusBasicType {
    public static var _dbusType: _DBusType {
        return .boolean
    }
    
    public func _append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        var val: dbus_bool_t = self ? 1 : 0
        withUnsafeBytes(of: &val) {
            _ = dbus_message_iter_append_basic(iter, type(of: self)._dbusType.rawValue, $0.baseAddress!)
        }
    }
}

extension Int16: DBusBasicType {
    public static var _dbusType: _DBusType {
        return .int16
    }
}

extension UInt16: DBusBasicType {
    public static var _dbusType: _DBusType {
        return .uint16
    }
}

extension Int32: DBusBasicType {
    public static var _dbusType: _DBusType {
        return .int32
    }
}

extension UInt32: DBusBasicType {
    public static var _dbusType: _DBusType {
        return .int32
    }
}

extension Int64: DBusBasicType {
    public static var _dbusType: _DBusType {
        return .int64
    }
}

extension UInt64: DBusBasicType {
    public static var _dbusType: _DBusType {
        return .uint64
    }
}

extension Double: DBusBasicType {
    public static var _dbusType: _DBusType {
        return .double
    }
}

extension String: DBusBasicType {
    public static var _dbusType: _DBusType {
        return .string
    }
    
    public func _append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        self.withCString {
            var val = $0
            _ = dbus_message_iter_append_basic(iter, type(of: self)._dbusType.rawValue, &val)
        }
    }
}

public struct DBusObjectPath: DBusBasicType {
    public let path: String
    
    public init(_ path: String) {
        self.path = path
    }
    
    public static var _dbusType: _DBusType {
        return .objectPath
    }
    
    public func _append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        self.path.withCString {
            var val = $0
            _ = dbus_message_iter_append_basic(iter, type(of: self)._dbusType.rawValue, &val)
        }
    }
    
    public static func==(lhs: DBusObjectPath, rhs: DBusObjectPath) -> Bool {
        return lhs.path == rhs.path
    }
    
    public var hashValue: Int {
        return self.path.hashValue
    }
}

public struct DBusVariant<T: DBusRepresentable>: DBusRepresentable {
    public let val: T
    
    public init(_ val: T) {
        self.val = val
    }
    
    public static var _dbusType: _DBusType {
        return .variant
    }
    
    public func _append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        T.self._dbusTypeSignature.withCString {
            var subIter = DBusMessageIter()
            dbus_message_iter_open_container(iter, type(of: self)._dbusType.rawValue, $0, &subIter)
            self.val._append(to: &subIter)
            dbus_message_iter_close_container(iter, &subIter)
        }
    }
}

public struct DBusArray<T: DBusRepresentable>: DBusRepresentable {
    
    public let values: [T]
    
    public init(_ values: [T]) {
        self.values = values
    }
    
    public static var _dbusType: _DBusType {
        return .array
    }
    
    public static var _dbusTypeSignature: String {
        return "a" + T._dbusTypeSignature
    }
    
    public func _append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        T.self._dbusTypeSignature.withCString {
            var subIter = DBusMessageIter()
            dbus_message_iter_open_container(iter, type(of: self)._dbusType.rawValue, $0, &subIter)
            
            for val in self.values {
                val._append(to: &subIter)
            }
            
            dbus_message_iter_close_container(iter, &subIter)
        }
    }
}

public struct DBusMap<Key: DBusBasicType, Value: DBusRepresentable>: DBusRepresentable {
    let values: [Key:Value]
    
    init(_ values: [Key:Value]) {
        self.values = values
    }
    
    public static var _dbusType: _DBusType {
        return .array
    }
    
    public static var _dbusTypeSignature: String {
        return "a" + self.dictEntrySignature
    }
    
    private static var dictEntrySignature: String {
        return "{" + Key._dbusTypeSignature + Value._dbusTypeSignature + "}"
    }
    
    public func _append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        type(of: self).dictEntrySignature.withCString {
            var entriesIter = DBusMessageIter()
            dbus_message_iter_open_container(iter, _DBusType.array.rawValue, $0, &entriesIter)
            for (key, value) in self.values {
                var entryIter = DBusMessageIter()
                dbus_message_iter_open_container(&entriesIter, _DBusType.dictEntry.rawValue, nil, &entryIter)
                key._append(to: &entryIter)
                value._append(to: &entryIter)
                dbus_message_iter_close_container(&entriesIter, &entryIter)
            }
            dbus_message_iter_close_container(iter, &entriesIter)
        }
    }
}

extension DBusError: Error { }

func ConnectionAddWatch(watch: OpaquePointer?, data: UnsafeMutableRawPointer?) -> dbus_bool_t {
    guard let watch = watch, let data = data else { return 0 }
    let conn = Unmanaged<Connection>.fromOpaque(data).takeUnretainedValue()
    
    let fd = dbus_watch_get_unix_fd(watch)
    let flags = dbus_watch_get_flags(watch)
    
    if flags & DBUS_WATCH_READABLE.rawValue > 0 {
        // Create read source
        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: conn.queue)
        readSource.setEventHandler {
            print("Handling read source... has incoming messages: \(dbus_connection_get_dispatch_status(conn.conn) == DBUS_DISPATCH_DATA_REMAINS)")
            dbus_watch_handle(watch, DBUS_WATCH_READABLE.rawValue)
            
            while (dbus_connection_get_dispatch_status(conn.conn) != DBUS_DISPATCH_COMPLETE) {
                dbus_connection_dispatch(conn.conn)
            }
            
            print("Handling read source... has incoming messages: \(dbus_connection_get_dispatch_status(conn.conn) == DBUS_DISPATCH_DATA_REMAINS)")
        }
        
        conn.readSources[watch] = readSource
        
        if dbus_watch_get_enabled(watch) > 0 {
            readSource.resume()
        }
    }
    
    if flags & DBUS_WATCH_WRITABLE.rawValue > 0 {
        // Create write source
        let writeSource = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: conn.queue)
        writeSource.setEventHandler {
            dbus_watch_handle(watch, DBUS_WATCH_WRITABLE.rawValue)
        }
        
        conn.writeSources[watch] = writeSource
        
        if dbus_watch_get_enabled(watch) > 0 {
            writeSource.resume()
        }
    }
    
    return 1
}

func ConnectionRemoveWatch(watch: OpaquePointer?, data: UnsafeMutableRawPointer?) {
    guard let watch = watch, let data = data else { return }
    let conn = Unmanaged<Connection>.fromOpaque(data).takeUnretainedValue()
    
    if let readSource = conn.readSources[watch] {
        readSource.cancel()
        
        conn.readSources[watch] = nil
    }
    
    if let writeSource = conn.writeSources[watch] {
        writeSource.cancel()
        conn.writeSources[watch] = nil
    }
}

func ConnectionToggleWatch(watch: OpaquePointer?, data: UnsafeMutableRawPointer?) {
    guard let watch = watch, let data = data else { return }
    let conn = Unmanaged<Connection>.fromOpaque(data).takeUnretainedValue()
    
    let enabled = dbus_watch_get_enabled(watch) != 0
    
    if let readSource = conn.readSources[watch] {
        if enabled {
            readSource.resume()
        } else {
            readSource.suspend()
        }
    }
    
    if let writeSource = conn.writeSources[watch] {
        if enabled {
            writeSource.resume()
        } else {
            writeSource.suspend()
        }
    }
}

func ConnectionAddTimeout(timeout: OpaquePointer?, data: UnsafeMutableRawPointer?) -> dbus_bool_t {
    guard let timeout = timeout, let data = data else { return 0 }
    let conn = Unmanaged<Connection>.fromOpaque(data).takeUnretainedValue()
    
    let interval = dbus_timeout_get_interval(timeout)
    let timer = DispatchSource.makeTimerSource(queue: conn.queue)
    timer.scheduleRepeating(deadline: .now() + .milliseconds(Int(interval)), interval: .milliseconds(Int(interval)))
    timer.setEventHandler { 
        dbus_timeout_handle(timeout)
        while (dbus_connection_get_dispatch_status(conn.conn) != DBUS_DISPATCH_COMPLETE) {
            dbus_connection_dispatch(conn.conn)
        }
    }
    conn.timers[timeout] = timer
    timer.resume()
    return 1
}

func ConnectionRemoveTimeout(timeout: OpaquePointer?, data: UnsafeMutableRawPointer?) {
    guard let timeout = timeout, let data = data else { return }
    let conn = Unmanaged<Connection>.fromOpaque(data).takeUnretainedValue()
    
    conn.timers[timeout]?.cancel()
    conn.timers[timeout] = nil
}

func ConnectionToggleTimeout(timeout: OpaquePointer?, data: UnsafeMutableRawPointer?) {
    guard let timeout = timeout, let data = data else { return }
    let conn = Unmanaged<Connection>.fromOpaque(data).takeUnretainedValue()
    
    let enabled = dbus_timeout_get_enabled(timeout) > 0
    
    if enabled {
        conn.timers[timeout]?.resume()
    } else {
        conn.timers[timeout]?.suspend()
    }
}

//func ConnectionDispatchStatusChanged(underlyingConnection: OpaquePointer?, status: DBusDispatchStatus, data: UnsafeMutableRawPointer?) {
//    guard let underlyingConnection = underlyingConnection, let data = data else { return }
//    let conn = Unmanaged<Connection>.fromOpaque(data).takeUnretainedValue()
//    
//    if status == DBUS_DISPATCH_DATA_REMAINS {
//        conn.queue.async {
//            dbus_connection_dispatch(underlyingConnection)
//        }
//    }
//}

public class Connection {
    
    public enum BusType {
        case system
        case session
        
        var underlyingType: DBusBusType {
            switch self {
            case .system: return DBUS_BUS_SYSTEM
            case .session: return DBUS_BUS_SESSION
            }
        }
    }
    
    let conn: OpaquePointer
    var readSources: [OpaquePointer:DispatchSourceRead] = [:]
    var writeSources: [OpaquePointer:DispatchSourceWrite] = [:]
    var timers: [OpaquePointer:DispatchSourceTimer] = [:]
    
    public let queue: DispatchQueue
    
    public init(type busType: BusType, queue: DispatchQueue = .main) throws {
        var error = DBusError()
        guard let c = dbus_bus_get_private(busType.underlyingType, &error) else { throw error }
        self.conn = c
        self.queue = queue
        
        let data = Unmanaged.passUnretained(self).toOpaque()
        //dbus_connection_set_dispatch_status_function(conn, ConnectionDispatchStatusChanged, data, nil)
        dbus_connection_set_watch_functions(c, ConnectionAddWatch, ConnectionRemoveWatch, ConnectionToggleWatch, data, nil)
        dbus_connection_set_timeout_functions(conn, ConnectionAddTimeout(timeout:data:), ConnectionRemoveTimeout, ConnectionToggleTimeout, data, nil)
    }
    
    deinit {
        dbus_connection_close(self.conn)
        dbus_connection_unref(self.conn)
    }
}

func PendingCallReceivedReply(pendingCall: OpaquePointer?, data: UnsafeMutableRawPointer?) {
    guard let pendingCall = pendingCall, let data = data else { return }
    let objectProxy = Unmanaged<ObjectProxy>.fromOpaque(data).takeUnretainedValue()
    
    if let reply = dbus_pending_call_steal_reply(pendingCall) {
        if dbus_message_get_type(reply) == DBUS_MESSAGE_TYPE_ERROR {
            let errorName = dbus_message_get_error_name(reply)
            objectProxy.callbacks[pendingCall]?(nil, DBusErr(name: errorName.flatMap({ String(cString: $0) })))
        } else {
            var iter = DBusMessageIter()
            dbus_message_iter_init(reply, &iter)
            
            var values = [Any]()
            
            while _DBusType(rawValue: dbus_message_iter_get_arg_type(&iter)) != .invalid {
                values.append(getValue(&iter))
            }
            
            objectProxy.callbacks[pendingCall]?(values, nil)
        }
        
        dbus_message_unref(reply)
    }
    
    dbus_pending_call_unref(pendingCall)
}

public struct DBusErr {
    public let name: String?
    
    init(name: String?) {
        self.name = name
    }
}

public class ObjectProxy {
    public typealias MethodCallback = ([Any]?, DBusErr?) -> Void
    
    public let service: String
    public let interface: String?
    public let objectPath: String
    public let connection: Connection
    var callbacks: [OpaquePointer:MethodCallback] = [:]
    
    public init(connection: Connection, service: String, interface: String? = nil, objectPath: String) {
        self.connection = connection
        self.service = service
        self.interface = interface
        self.objectPath = objectPath
    }
    
    public func invoke(method: String, arguments: DBusRepresentable..., completionHandler: @escaping MethodCallback) {
        guard let message = service.withCString({ serviceStr in
            return objectPath.withCString { objectPathStr in
                return method.withCString { methodStr -> OpaquePointer! in
                    if let interface = interface {
                        return interface.withCString({ interfaceStr in
                            return dbus_message_new_method_call(serviceStr, objectPathStr, interfaceStr, methodStr)
                        })
                    }
                    
                    return dbus_message_new_method_call(serviceStr, objectPathStr, nil, methodStr)
                }
            }
        }) else { return }
        
        var args = DBusMessageIter()
        dbus_message_iter_init_append(message, &args)
        arguments.forEach { $0._append(to: &args) }
        
        // Send the message
        var pendingCall: OpaquePointer? = nil
        dbus_connection_send_with_reply(connection.conn, message, &pendingCall, DBUS_TIMEOUT_USE_DEFAULT)
        if let pendingCall = pendingCall {
            callbacks[pendingCall] = completionHandler
        }
        dbus_pending_call_set_notify(pendingCall, PendingCallReceivedReply, Unmanaged.passUnretained(self).toOpaque(), nil)
        
        dbus_message_unref(message)
    }
}
