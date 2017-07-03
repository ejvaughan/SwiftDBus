//
//  ObjectProxy.swift
//  SwiftDbus
//
//  Created by Ethan Vaughan on 7/1/17.
//
//

import Clibdbus

func PendingCallReceivedReply(pendingCall: OpaquePointer?, data: UnsafeMutableRawPointer?) {
    guard let pendingCall = pendingCall, let data = data else { return }
    let objectProxy = Unmanaged<ObjectProxy>.fromOpaque(data).takeUnretainedValue()
    
    if let replyRaw = dbus_pending_call_steal_reply(pendingCall) {
        let reply = MessageWrapper(replyRaw)
        
        if reply.type == .error {
            objectProxy.callbacks[pendingCall]?(.error(reply.errorName))
        } else {
            objectProxy.callbacks[pendingCall]?(.success(reply.arguments))
        }
        
        dbus_message_unref(replyRaw)
    } else {
        // Timeout
        objectProxy.callbacks[pendingCall]?(.timeout)
    }
    
    objectProxy.callbacks[pendingCall] = nil
}

func ObjectProxyFilterMessage(connection: OpaquePointer?, rawMessage: OpaquePointer?, data: UnsafeMutableRawPointer?) -> DBusHandlerResult {
    guard let rawMessage = rawMessage, let data = data else { return DBUS_HANDLER_RESULT_NOT_YET_HANDLED }
    
    let objectProxy = Unmanaged<ObjectProxy>.fromOpaque(data).takeUnretainedValue()
    let message = MessageWrapper(rawMessage)
    
    let uniqueName = objectProxy.service.hasPrefix(":") ? objectProxy.service : objectProxy.connection.uniqueNameForBusName[objectProxy.service]
    
    guard let name = uniqueName,
        let sender = message.sender,
        let path = message.objectPath,
        message.type == .signal &&
        sender == name &&
        path == objectProxy.objectPath else { return DBUS_HANDLER_RESULT_NOT_YET_HANDLED }
    
    if let interface = objectProxy.interface {
        guard let messageInterface = message.interface, messageInterface == interface else { return DBUS_HANDLER_RESULT_NOT_YET_HANDLED }
    }
    
    guard let signalName = message.member, let handler = objectProxy.signalHandlers[signalName] else { return DBUS_HANDLER_RESULT_NOT_YET_HANDLED }
    
    handler(message.arguments)
    
    // We return not handled, because it's possible to create multiple proxies for the same object
    // If we returned handled, then the other proxies will not have a chance to invoke their own signal handlers
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED
}

public class ObjectProxy {
    public enum InvocationResult {
        case success([Any])
        case error(String?)
        case timeout
    }
    
    public typealias MethodCallback = (InvocationResult) -> Void
    public typealias SignalHandler = ([Any]) -> Void
    
    public let service: String
    public let interface: String?
    public let objectPath: String
    public unowned let connection: Connection
    private var connectionStrongRef: Connection?
    var callbacks: [OpaquePointer:MethodCallback] = [:]
    var signalHandlers: [String:SignalHandler] = [:]
    
    init(connection: Connection, stronglyReference: Bool = true, service: String, interface: String? = nil, objectPath: String) {
        self.connection = connection
        if stronglyReference {
            self.connectionStrongRef = connection
        }
        self.service = service
        self.interface = interface
        self.objectPath = objectPath
        
        dbus_connection_add_filter(connection.conn, ObjectProxyFilterMessage, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
    
    deinit {
        dbus_connection_remove_filter(connection.conn, ObjectProxyFilterMessage, Unmanaged.passUnretained(self).toOpaque())
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
    
    public func registerSignalHandler(for signal: String, with handler: @escaping SignalHandler) {
        var rule = "type='signal',sender='" + self.service + "',path='" + self.objectPath + "',member='" + signal + "'"
        
        if let interface = interface {
            rule += ",interface='"  + interface + "'"
        }
        
        rule.withCString {
            dbus_bus_add_match(connection.conn, $0, nil)
        }
        
        signalHandlers[signal] = handler
    }
}
