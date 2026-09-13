//
//  Item.swift
//  Lantern
//
//  Created by Nathan on 9/13/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
