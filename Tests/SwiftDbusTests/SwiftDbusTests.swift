import XCTest
import Clibdbus
@testable import SwiftDbus

class SwiftDbusTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertEqual(DBusArray<DBusArray<UInt8>>._dbusTypeSignature, "aay")
    }

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
        
        dbusObject.invoke(method: "ListNames") { (results, error) in
            if let error = error {
                XCTFail()
            } else {
                print("Received names: \(results!)")
            }
            
            expect.fulfill()
        }
        
        waitForExpectations(timeout: 2.0, handler: nil)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
