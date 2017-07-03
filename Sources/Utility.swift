//
//  Utility.swift
//  SwiftDbus
//
//  Created by Ethan Vaughan on 7/1/17.
//
//

import Clibdbus

// print becomes a nop for release builds
func print(items: Any..., separator: String = " ", terminator: String = "\n") {
    
    #if DEBUG
        
        var idx = items.startIndex
        let endIdx = items.endIndex
        
        repeat {
            Swift.print(items[idx], separator: separator, terminator: idx == (endIdx - 1) ? terminator : separator)
            idx += 1
        }
            while idx < endIdx
        
    #endif
}
