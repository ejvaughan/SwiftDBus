import XCTest
import Clibdbus
@testable import SwiftDbus

class SwiftDbusTests: XCTestCase {

    func testStringIterAppend() {
        var message = dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_CALL)
        defer {
            dbus_message_unref(message)
        }
        
        var storeIter = DBusMessageIter()
        dbus_message_iter_init_append(message, &storeIter)
        let str = "Hello, world!"
        str._append(to: &storeIter)
        
        var readIter = DBusMessageIter()
        dbus_message_iter_init(message, &readIter)
        
        XCTAssertEqual(getValue(&readIter) as! String, str)
    }
    
    func testGetVariantFromIter() {
        var message = dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_CALL)
        defer {
            dbus_message_unref(message)
        }
        
        var storeIter = DBusMessageIter()
        dbus_message_iter_init_append(message, &storeIter)
        
        let val = "hello"
        DBusVariant(val)._append(to: &storeIter)
        
        var readIter = DBusMessageIter()
        dbus_message_iter_init(message, &readIter)
        
        XCTAssertEqual(getValue(&readIter) as! String, val)
    }
    
    func testGetArrayFromIter() {
        var message = dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_CALL)
        defer {
            dbus_message_unref(message)
        }
        
        let rawArray: [UInt8] = [0, 1]
        let arr = DBusArray(rawArray)
        
        var storeIter = DBusMessageIter()
        dbus_message_iter_init_append(message, &storeIter)
        arr._append(to: &storeIter)
        
        var readIter = DBusMessageIter()
        dbus_message_iter_init(message, &readIter)
        
        XCTAssertEqual(getValue(&readIter) as! [UInt8], rawArray)
    }
    
    func testGetDictFromIter() {
        var message = dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_CALL)
        defer {
            dbus_message_unref(message)
        }
        
        var storeIter = DBusMessageIter()
        dbus_message_iter_init_append(message, &storeIter)
        
        let rawDict = ["hello":UInt8(0), "world":UInt8(1)]
        let dict = DBusMap(rawDict)
        dict._append(to: &storeIter)
        
        var readIter = DBusMessageIter()
        dbus_message_iter_init(message, &readIter)
        
        XCTAssertEqual(getValue(&readIter) as! [String:UInt8], rawDict)
    }
    
    func testGetObjectPathFromIter() {
        var message = dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_CALL)
        defer {
            dbus_message_unref(message)
        }
        
        var storeIter = DBusMessageIter()
        dbus_message_iter_init_append(message, &storeIter)
        
        let val = DBusObjectPath("/com/ejv/somepath")
        val._append(to: &storeIter)
        
        var readIter = DBusMessageIter()
        dbus_message_iter_init(message, &readIter)
        
        XCTAssertEqual(getValue(&readIter) as! DBusObjectPath, val)
    }
    
    func testGetStructFromIter() {
        struct MyStruct: DBusStruct {
            var fieldValues: [DBusRepresentable] {
                return ["Hello", UInt8(0)]
            }
            
            static var fieldTypes: [DBusRepresentable.Type] {
                return [String.self, UInt8.self]
            }
        }
        
        var message = dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_CALL)
        defer {
            dbus_message_unref(message)
        }
        
        var storeIter = DBusMessageIter()
        dbus_message_iter_init_append(message, &storeIter)
        
        let s = MyStruct()
        s._append(to: &storeIter)
        
        var readIter = DBusMessageIter()
        dbus_message_iter_init(message, &readIter)
        
        let values = getValue(&readIter) as! [DBusRepresentable]
        
        XCTAssertEqual(values[0] as! String, s.fieldValues[0] as! String)
        XCTAssertEqual(values[1] as! UInt8, s.fieldValues[1] as! UInt8)
    }
    
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
        
        senderConnection.request(name: "com.ejv.test", queueRequest: false) { result in
            guard let result = result, result == .primaryOwner else { XCTFail(); return }
            
            var serial: dbus_uint32_t = 0
            let signalMessage = dbus_message_new_signal("/com/ejv/test", "com.ejv.test", "Foo")
            dbus_connection_send(senderConnection.conn, signalMessage, &serial)
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
            
            receiverConnection.request(name: "com.ejv.test", queueRequest: false) { result in
                guard let result = result, result == .primaryOwner else { XCTFail(); return }
            }
        }
        
        waitForExpectations(timeout: 5.0, handler: nil)
    }

    static var allTests = [
        ("testStringIterAppend", testStringIterAppend)
    ]
}
