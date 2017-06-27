import Clibdbus

public enum DBusType: Int32 {
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
}

public protocol DBusRepresentable {
    static var dbusType: DBusType { get }
    static var dbusTypeSignature: String { get }
    
    func append(to iter: UnsafeMutablePointer<DBusMessageIter>)
}

public protocol DBusBasicType: DBusRepresentable, Hashable { }

extension DBusRepresentable {
    public static var dbusTypeSignature: String {
        return String(Character(UnicodeScalar(UInt32(self.dbusType.rawValue))!))
    }
}

extension DBusBasicType {
    public func append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        var val = self
        withUnsafeBytes(of: &val) {
            _ = dbus_message_iter_append_basic(iter, type(of: val).dbusType.rawValue, $0.baseAddress!)
        }
    }
}

extension UInt8: DBusBasicType {
    public static var dbusType: DBusType {
        return .byte
    }
}

extension Bool: DBusBasicType {
    public static var dbusType: DBusType {
        return .boolean
    }
    
    public func append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        var val: UInt32 = self ? 1 : 0
        withUnsafeBytes(of: &val) {
            _ = dbus_message_iter_append_basic(iter, type(of: self).dbusType.rawValue, $0.baseAddress!)
        }
    }
}

extension Int16: DBusBasicType {
    public static var dbusType: DBusType {
        return .int16
    }
}

extension UInt16: DBusBasicType {
    public static var dbusType: DBusType {
        return .uint16
    }
}

extension Int32: DBusBasicType {
    public static var dbusType: DBusType {
        return .int32
    }
}

extension UInt32: DBusBasicType {
    public static var dbusType: DBusType {
        return .int32
    }
}

extension Int64: DBusBasicType {
    public static var dbusType: DBusType {
        return .int64
    }
}

extension UInt64: DBusBasicType {
    public static var dbusType: DBusType {
        return .uint64
    }
}

extension String: DBusBasicType {
    public static var dbusType: DBusType {
        return .string
    }
    
    public func append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        self.withCString {
            _ = dbus_message_iter_append_basic(iter, type(of: self).dbusType.rawValue, $0)
        }
    }
}

public struct DBusObjectPath: DBusBasicType {
    public let path: String
    
    public init(_ path: String) {
        self.path = path
    }
    
    public static var dbusType: DBusType {
        return .objectPath
    }
    
    public func append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        self.path.withCString {
            _ = dbus_message_iter_append_basic(iter, type(of: self).dbusType.rawValue, $0)
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
    
    public static var dbusType: DBusType {
        return .variant
    }
    
    public func append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        T.self.dbusTypeSignature.withCString {
            var subIter = DBusMessageIter()
            dbus_message_iter_open_container(iter, type(of: self).dbusType.rawValue, $0, &subIter)
            self.val.append(to: &subIter)
            dbus_message_iter_close_container(iter, &subIter)
        }
    }
}

public struct DBusArray<T: DBusRepresentable>: DBusRepresentable {
    
    public let values: [T]
    
    public init(_ values: [T]) {
        self.values = values
    }
    
    public static var dbusType: DBusType {
        return .array
    }
    
    public static var dbusTypeSignature: String {
        return "a" + T.dbusTypeSignature
    }
    
    public func append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        T.self.dbusTypeSignature.withCString {
            var subIter = DBusMessageIter()
            dbus_message_iter_open_container(iter, type(of: self).dbusType.rawValue, $0, &subIter)
            
            for val in self.values {
                val.append(to: &subIter)
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
    
    public static var dbusType: DBusType {
        return .dictEntry
    }
    
    public static var dbusTypeSignature: String {
        return "a" + self.dictEntrySignature
    }
    
    private static var dictEntrySignature: String {
        return "{" + Key.dbusTypeSignature + Value.dbusTypeSignature + "}"
    }
    
    public func append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        type(of: self).dictEntrySignature.withCString {
            var entriesIter = DBusMessageIter()
            dbus_message_iter_open_container(iter, DBusType.array.rawValue, $0, &entriesIter)
            for (key, value) in self.values {
                var entryIter = DBusMessageIter()
                dbus_message_iter_open_container(&entriesIter, DBusType.dictEntry.rawValue, nil, &entryIter)
                key.append(to: &entryIter)
                value.append(to: &entryIter)
                dbus_message_iter_close_container(&entriesIter, &entryIter)
            }
            dbus_message_iter_close_container(iter, &entriesIter)
        }
    }
}

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
    
//    public init(_ busType: BusType) throws {
//        var error: DBusError
//        
//        guard let c = dbus_bus_get(busType.underlyingType, &error) else { throw
//    }
}

public class ObjectProxy {
    let service: String
    let interface: String?
    let objectPath: String
    let connection: Connection
    
    init(connection: Connection, service: String, interface: String? = nil, objectPath: String) {
        self.connection = connection
        self.service = service
        self.interface = interface
        self.objectPath = objectPath
    }
    
    func invoke(method: String, arguments: DBusRepresentable..., completionHandler: ([DBusRepresentable]?, Error?) -> Void) {
        guard let message = service.withCString({ serviceStr in
            return objectPath.withCString { objectPathStr in
                return method.withCString { methodStr in
                    return dbus_message_new_method_call(serviceStr, objectPathStr, nil, methodStr)
                }
            }
        }) else { return }
        
        var args = DBusMessageIter()
        dbus_message_iter_init_append(message, &args)
        arguments.forEach { $0.append(to: &args) }
        
        // Send the message
        
        dbus_message_unref(message)
    }
}
