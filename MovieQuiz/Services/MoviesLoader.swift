//
//  MoviesLoader.swift
//  MovieQuiz
//
//  Created by Дмитрий Макеев on 21.09.2026.
//

import Foundation

protocol MoviesLoading {
    func loadMovies(handler: @escaping (Result<MostPopularMovies, Error>) -> Void)
}

struct MoviesLoader: MoviesLoading {
    private enum LoaderError: LocalizedError {
        case emptyResult(String)
        
        var errorDescription: String? {
            switch self {
            case .emptyResult(let message):
                return message
            }
        }
    }
    
    // MARK: - NetworkClient
    private let networkClient = NetworkClient()
    
    // MARK: - URL
    private var mostPopularMoviesUrl: URL {
        guard let url = URL(string: "https://tv-api.com/en/API/Top250Movies/k_j4r66gt6") else {
            preconditionFailure("Unable to construct mostPopularMoviesUrl")
        }
        return url
    }
    
    func loadMovies(handler: @escaping (Result<MostPopularMovies, Error>) -> Void) {
        networkClient.fetch(url: mostPopularMoviesUrl) { result in
            switch result {
            case .success(let data):
                do {
                    let mostPopularMovies = try JSONDecoder().decode(MostPopularMovies.self, from: data)
                    if mostPopularMovies.items.isEmpty {
                        let message = mostPopularMovies.errorMessage.isEmpty
                            ? "Не удалось загрузить данные"
                            : mostPopularMovies.errorMessage
                        handler(.failure(LoaderError.emptyResult(message)))
                    } else {
                        handler(.success(mostPopularMovies))
                    }
                } catch {
                    handler(.failure(error))
                }
            case .failure(let error):
                handler(.failure(error))
            }
        }
    }
}
