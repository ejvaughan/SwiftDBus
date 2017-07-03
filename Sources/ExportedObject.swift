//
//  ExportedObject.swift
//  SwiftDbus
//
//  Created by Ethan Vaughan on 7/1/17.
//
//

import Clibdbus

public enum MethodResult {
    case success([DBusRepresentable]?)
    case error(String)
}

public typealias ExportedMethodReturnCallback = (MethodResult) -> Void
public typealias ExportedMethod = ([Any], ExportedMethodReturnCallback) -> Void

public protocol ExportedObject: class {
    var exportedMethods: [String:[String: ExportedMethod]] { get }
    weak var connection: Connection? { get set }
    func emitSignal(name: String, interface: String, arguments: [DBusRepresentable]?)
}

extension ExportedObject {
    public func emitSignal(name: String, interface: String, arguments: [DBusRepresentable]? = nil) {
        guard let connection = connection, let path = connection.exportedObjectPath(for: self) else { return }
        
        let message = path.withCString { pathStr in
            return name.withCString { nameStr in
                return interface.withCString { interfaceStr in
                    return dbus_message_new_signal(pathStr, interfaceStr, nameStr)
                }
            }
        }
        defer {
            dbus_message_unref(message)
        }
        
        if let arguments = arguments {
            var messageIter = DBusMessageIter()
            dbus_message_iter_init_append(message, &messageIter)
            arguments.forEach { $0._append(to: &messageIter) }
        }
        
        dbus_connection_send(connection.conn, message, nil)
    }
}
