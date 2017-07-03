//
//  ObjectProxyTests.swift
//  SwiftDbus
//
//  Created by Ethan Vaughan on 7/2/17.
//
//

import XCTest
import Clibdbus
@testable import SwiftDbus

class ObjectProxyTests: XCTestCase {
    func testInvokeMethod() {
        let connection = try! Connection(type: .session)
        let dbusObject = ObjectProxy(connection: connection, service: "org.freedesktop.DBus", interface: "org.freedesktop.DBus", objectPath: "/org/freedesktop/DBus")
        
        let expect = expectation(description: "Waiting for method callback")
        
        dbusObject.invoke(method: "ListNames") { result in
            if case let .success(arguments) = result {
                print("Received names: \(arguments)")
            } else {
                XCTFail()
            }
            
            expect.fulfill()
        }
        
        waitForExpectations(timeout: 5.0, handler: nil)
    }
    
    func testSignalHandlerForUniqueConnectionName() {
        let receiverConnection = try! Connection(type: .session)
        let senderConnection = try! Connection(type: .session)
        let senderName = String(cString: dbus_bus_get_unique_name(senderConnection.conn))
        
        let expect = expectation(description: "Waiting for 'Foo' signal")
        
        var p: ObjectProxy?
        
        receiverConnection.makeProxy(forService: senderName, interface: "com.ejv.test", objectPath: "/com/ejv/test") { proxy in
            guard let proxy = proxy else { XCTFail(); return }
            
            p = proxy
            
            proxy.registerSignalHandler(for: "Foo", with: { (results) in
                expect.fulfill()
            })
            
            // Delay sending the signal to ensure that the signal handler in the other connection has been installed (i.e. the dbus daemon
            // processes the AddMatch method call message resulting from registerSignalHandler() before it processes this signal message
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                var serial: dbus_uint32_t = 0
                let signalMessage = dbus_message_new_signal("/com/ejv/test", "com.ejv.test", "Foo")
                dbus_connection_send(senderConnection.conn, signalMessage, &serial)
            }
        }
        
        waitForExpectations(timeout: 5.0, handler: nil)
    }
    
    func testSignalHandlerForWellKnownName() {
        let receiverConnection = try! Connection(type: .session)
        
        let expect = expectation(description: "Waiting for 'Foo' signal")
        
        var p: ObjectProxy?
        
        receiverConnection.makeProxy(forService: "com.ejv.test", interface: "com.ejv.test", objectPath: "/com/ejv/test") { (proxy) in
            guard let proxy = proxy else { XCTFail(); return }
            
            p = proxy
            
            proxy.registerSignalHandler(for: "Foo", with: { (results) in
                expect.fulfill()
            })
        }
        
        let senderConnection = try! Connection(type: .session)
        
        senderConnection.request(name: "com.ejv.test", allowingReplacement: true, queueRequest: false, replaceExisting: true) { result in
            guard let result = result, result == .primaryOwner else { XCTFail(); return }
            
            // Delay sending the signal to ensure that the signal handler in the other connection has been installed (i.e. the dbus daemon
            // processes the AddMatch method call message resulting from registerSignalHandler() before it processes this signal message
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                var serial: dbus_uint32_t = 0
                let signalMessage = dbus_message_new_signal("/com/ejv/test", "com.ejv.test", "Foo")
                dbus_connection_send(senderConnection.conn, signalMessage, &serial)
            }
        }
        
        waitForExpectations(timeout: 5.0, handler: nil)
    }
    
    func testBusObjectProxySignalHandler() {
        let receiverConnection = try! Connection(type: .session)
        
        let expect = expectation(description: "Waiting for 'NameAcquired' signal")
        
        var p: ObjectProxy?
        
        receiverConnection.makeProxy(forService: "org.freedesktop.DBus", interface: "org.freedesktop.DBus", objectPath: "/org/freedesktop/DBus") { proxy in
            guard let proxy = proxy else { XCTFail(); return }
            
            p = proxy
            
            proxy.registerSignalHandler(for: "NameAcquired", with: { (results) in
                if let name = results[0] as? String, name == "com.ejv.test" {
                    expect.fulfill()
                }
            })
            
            receiverConnection.request(name: "com.ejv.test", allowingReplacement: true, queueRequest: false, replaceExisting: true) { result in
                guard let result = result, result == .primaryOwner else { XCTFail(); return }
            }
        }
        
        waitForExpectations(timeout: 5.0, handler: nil)
    }
    
    static var allTests = [
        ("testInvokeMethod", testInvokeMethod),
        ("testSignalHandlerForUniqueConnectionName", testSignalHandlerForUniqueConnectionName),
        ("testSignalHandlerForWellKnownName", testSignalHandlerForWellKnownName),
        ("testBusObjectProxySignalHandler", testBusObjectProxySignalHandler)
    ]
}

