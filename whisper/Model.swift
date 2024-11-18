//
//  Model.swift
//  whisper
//
//  Created by Valentin Vanhove on 18/11/2024.
//

import Foundation
import SwiftData

@Model
final class Model {
    var model: String
    var language: String
    
    init(model: String, language: String) {
        self.model = model
        self.language = language
    }
}
