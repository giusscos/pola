//
//  Item.swift
//  pola
//
//  Created by Giuseppe Cosenza on 08/06/2026.
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
