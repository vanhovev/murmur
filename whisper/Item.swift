//
//  Item.swift
//  whisper
//
//  Created by Valentin Vanhove on 18/11/2024.
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
