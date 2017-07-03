//
//  ExportedObjectTests.swift
//  SwiftDbus
//
//  Created by Ethan Vaughan on 7/2/17.
//
//

import XCTest
import Clibdbus
@testable import SwiftDbus

class SomeObject: ExportedObject {
    weak var connection: Connection?
    lazy var exportedMethods: [String:[String:ExportedMethod]] = [
        "com.ejv.test": [
            "echo": self.echo
        ]
    ]
    
    func echo(arguments: [Any], callback: ExportedMethodReturnCallback) {
        guard let input = arguments.first as? String else {
            callback(.error("org.freedesktop.DBus.Error.InvalidArgs"))
            return
        }
        
        callback(.success([input]))
    }
}

class ExportedObjectTests: XCTestCase {
    
    func testExportedObject() {
        let exportedObject = SomeObject()
        let connection = try! Connection(type: .session)
        
        connection.export(object: exportedObject, at: "/com/ejv/test")
        
        let expect = expectation(description: "Waiting for method call")
        
        var p: ObjectProxy?
        
        connection.makeProxy(forService: connection.uniqueName, objectPath: "/com/ejv/test") { proxy in
            guard let proxy = proxy else { XCTFail(); return }
            
            p = proxy
            
            let str = "Hello, world"
            proxy.invoke(method: "echo", arguments: str) { result in
                switch result {
                case .success(let echoed) where (echoed[0] as! String) == str:
                    expect.fulfill()
                default:
                    XCTFail()
                }
            }
        }
        
        waitForExpectations(timeout: 5.0, handler: nil)
    }
}
