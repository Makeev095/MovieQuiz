//
//  AlertModel.swift
//  MovieQuiz
//
//  Created by Дмитрий Макеев on 24.08.2026.
//

import Foundation

struct AlertModel {
    var title: String
    var message: String
    var buttonText: String
    var completion: () -> Void
} 
