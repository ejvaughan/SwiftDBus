//
//  Connection.swift
//  SwiftDbus
//
//  Created by Ethan Vaughan on 7/1/17.
//
//

import Clibdbus
import Dispatch

func ConnectionAddWatch(watch: OpaquePointer?, data: UnsafeMutableRawPointer?) -> dbus_bool_t {
    guard let watch = watch, let data = data else { return 0 }
    let conn = Unmanaged<Connection>.fromOpaque(data).takeUnretainedValue()
    
    let fd = dbus_watch_get_unix_fd(watch)
    let flags = dbus_watch_get_flags(watch)
    
    if flags & DBUS_WATCH_READABLE.rawValue > 0 {
        // Create read source
        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: conn.queue)
        readSource.setEventHandler {
            print("Handling read source...")
            dbus_watch_handle(watch, DBUS_WATCH_READABLE.rawValue)
            
            while (dbus_connection_get_dispatch_status(conn.conn) != DBUS_DISPATCH_COMPLETE) {
                #if DEBUG
                    let borrowedMessage = dbus_connection_borrow_message(conn.conn)
                    if let message = borrowedMessage {
                        print(MessageWrapper(message))
                        dbus_connection_return_message(conn.conn, message)
                    }
                #endif
                
                dbus_connection_dispatch(conn.conn)
            }
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
//    if status != DBUS_DISPATCH_COMPLETE {
//        conn.queue.async {
//            while dbus_connection_get_dispatch_status(underlyingConnection) != DBUS_DISPATCH_COMPLETE {
//                dbus_connection_dispatch(underlyingConnection)
//            }
//        }
//    }
//}

func ConnectionFilterMessage(connection: OpaquePointer?, rawMessage: OpaquePointer?, data: UnsafeMutableRawPointer?) -> DBusHandlerResult {
    guard let rawMessage = rawMessage, let data = data else { return DBUS_HANDLER_RESULT_NOT_YET_HANDLED }
    
    let message = MessageWrapper(rawMessage)
    let connection = Unmanaged<Connection>.fromOpaque(data).takeUnretainedValue()
    
    // Observe changes to the primary owner of the proxy's bus name
    if let interface = message.interface,
        let member = message.member,
        message.type == .signal &&
        interface == "org.freedesktop.DBus" &&
        member == "NameOwnerChanged"
    {
        let busName = message.arguments[0] as! String
        let newOwner = message.arguments[2] as! String
        
        connection.uniqueNameForBusName[busName] = newOwner
    }
    
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED
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
    
    public enum RequestNameResult: UInt32 {
        case primaryOwner = 1
        case queued
        case taken
        case alreadyOwner
    }
    
    let conn: OpaquePointer
    lazy var busProxy: ObjectProxy = ObjectProxy(connection: self, service: "org.freedesktop.DBus", interface: "org.freedesktop.DBus", objectPath: "/org/freedesktop/DBus")
    var readSources: [OpaquePointer:DispatchSourceRead] = [:]
    var writeSources: [OpaquePointer:DispatchSourceWrite] = [:]
    var timers: [OpaquePointer:DispatchSourceTimer] = [:]
    var uniqueNameForBusName: [String:String] = ["org.freedesktop.DBus":"org.freedesktop.DBus"]
    var uniqueNameObservations: Set<String> = []
    
    
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
        
        dbus_connection_add_filter(conn, ConnectionFilterMessage, data, nil)
    }
    
    deinit {
        dbus_connection_remove_filter(conn, ConnectionFilterMessage, Unmanaged.passUnretained(self).toOpaque())
        dbus_connection_close(self.conn)
        dbus_connection_unref(self.conn)
    }
    
    public func request(name: String, allowingReplacement: Bool = false, queueRequest: Bool = true, replaceExisting: Bool = false, completionHandler: @escaping (RequestNameResult?) -> Void) {
        var flags: UInt32 = 0

        if allowingReplacement {
            flags |= UInt32(DBUS_NAME_FLAG_ALLOW_REPLACEMENT)
        }
        if !queueRequest {
            flags |= UInt32(DBUS_NAME_FLAG_DO_NOT_QUEUE)
        }
        if replaceExisting {
            flags |= UInt32(DBUS_NAME_FLAG_REPLACE_EXISTING)
        }

        busProxy.invoke(method: "RequestName", arguments: name, flags) { result in
            switch result {
            case let .success(arguments):
                let resultCode = arguments[0] as! UInt32
                completionHandler(RequestNameResult(rawValue: resultCode)!)
            default:
                completionHandler(nil)
            }
        }
    }
    
    private func observeUniqueNameChanges(for service: String) {
        guard !uniqueNameObservations.contains(service) else { return }
        
        let matchRule = "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='" + service + "'"
        matchRule.withCString {
            dbus_bus_add_match(conn, $0, nil)
        }
        uniqueNameObservations.insert(service)
    }
    
    public func makeProxy(forService service: String, interface: String? = nil, objectPath: String, completionHandler: @escaping (ObjectProxy?) -> Void) {
        if service.hasPrefix(":") || uniqueNameForBusName[service] != nil {
            let proxy = ObjectProxy(connection: self, service: service, interface: interface, objectPath: objectPath)
            completionHandler(proxy)
        } else {
            observeUniqueNameChanges(for: service)
            
            busProxy.invoke(method: "GetNameOwner", arguments: service) { result in
                switch result {
                case let .success(arguments):
                    let uniqueName = arguments[0] as! String
                    self.uniqueNameForBusName[service] = uniqueName
                    let proxy = ObjectProxy(connection: self, service: service, interface: interface, objectPath: objectPath)
                    completionHandler(proxy)
                case let .error(errorName?) where errorName == "org.freedesktop.DBus.Error.NameHasNoOwner":
                    // Because we are observing owner changes for this name, we will get notified when this name gains an owner
                    let proxy = ObjectProxy(connection: self, service: service, interface: interface, objectPath: objectPath)
                    completionHandler(proxy)
                default: // timeout or other error
                    completionHandler(nil)
                }
            }
        }
    }
}
