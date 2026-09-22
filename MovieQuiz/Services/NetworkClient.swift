//
//  NetworkClient.swift
//  MovieQuiz
//
//  Created by Дмитрий Макеев on 21.09.2026.
//

import Foundation

struct NetworkClient {

    private enum NetworkError: LocalizedError {
        case codeError
        case emptyData
        
        var errorDescription: String? {
            switch self {
            case .codeError, .emptyData:
                return "Не удалось загрузить данные"
            }
        }
    }
    
    func fetch(url: URL, handler: @escaping (Result<Data, Error>) -> Void) {
        let request = URLRequest(url: url)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                handler(.failure(error))
                return
            }
            
            if let response = response as? HTTPURLResponse,
                response.statusCode < 200 || response.statusCode >= 300 {
                handler(.failure(NetworkError.codeError))
                return
            }
            
            guard let data = data else {
                handler(.failure(NetworkError.emptyData))
                return
            }
            handler(.success(data))
        }
        
        task.resume()
    }
}
