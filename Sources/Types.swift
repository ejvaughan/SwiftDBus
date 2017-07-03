//
//  Types.swift
//  SwiftDbus
//
//  Created by Ethan Vaughan on 7/1/17.
//
//

import Clibdbus

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
    case .signature:
        var str: UnsafePointer<Int8>? = nil
        dbus_message_iter_get_basic(iter, &str)
        return DBusSignature(str.flatMap({ String(cString: $0) }) ?? "")
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
        return .uint32
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

public struct DBusSignature: DBusBasicType {
    public let signature: String
    
    public init(_ signature: String) {
        self.signature = signature
    }
    
    public static var _dbusType: _DBusType {
        return .signature
    }
    
    public func _append(to iter: UnsafeMutablePointer<DBusMessageIter>) {
        signature.withCString {
            var val = $0
            _ = dbus_message_iter_append_basic(iter, type(of: self)._dbusType.rawValue, &val)
        }
    }
    
    public static func==(lhs: DBusSignature, rhs: DBusSignature) -> Bool {
        return lhs.signature == rhs.signature
    }
    
    public var hashValue: Int {
        return self.signature.hashValue
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
