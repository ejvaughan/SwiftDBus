//
//  MessageWrapper.swift
//  SwiftDbus
//
//  Created by Ethan Vaughan on 7/1/17.
//
//

import Clibdbus

/// Utility wrapper for DBusMessage
class MessageWrapper: CustomDebugStringConvertible {
    
    enum MessageType: Int32 {
        case invalid
        case methodCall
        case methodReturn
        case error
        case signal
    }
    
    let message: OpaquePointer
    
    lazy private(set) var member: String? = (dbus_message_get_member(self.message) as UnsafePointer<Int8>?).flatMap { String(cString: $0) }
    
    lazy private(set) var objectPath: String? = (dbus_message_get_path(self.message) as UnsafePointer<Int8>?).flatMap { String(cString: $0) }
    
    lazy private(set) var interface: String? = (dbus_message_get_interface(self.message) as UnsafePointer<Int8>?).flatMap { String(cString: $0) }
    
    lazy private(set) var sender: String? = (dbus_message_get_sender(self.message) as UnsafePointer<Int8>?).flatMap { String(cString: $0) }
    
    lazy private(set) var destination: String? = (dbus_message_get_destination(self.message) as UnsafePointer<Int8>?).flatMap { String(cString: $0) }
    
    lazy private(set) var errorName: String? = (dbus_message_get_error_name(self.message) as UnsafePointer<Int8>?).flatMap { String(cString: $0) }
    
    lazy private(set) var type: MessageType = MessageType(rawValue: dbus_message_get_type(self.message))!
    
    init(_ message: OpaquePointer) {
        self.message = message
    }
    
    lazy private(set) var arguments: [Any] = {
        var iter = DBusMessageIter()
        dbus_message_iter_init(self.message, &iter)
        
        var values = [Any]()
        
        while _DBusType(rawValue: dbus_message_iter_get_arg_type(&iter)) != .invalid {
            values.append(getValue(&iter))
        }
        
        return values
    }()
    
    var debugDescription: String {
        return "Sender: \(self.sender ?? "None")\n" +
            "Type: \(self.type)\n" +
            "Object: \(self.objectPath ?? "None")\n" +
            "Interface: \(self.interface ?? "None")\n" +
        "Member: \(self.member ?? "None")"
    }
}
