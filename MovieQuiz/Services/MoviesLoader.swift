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

//struct MoviesLoader: MoviesLoading {
//    // MARK: - NetworkClient
//    private let networkClient = NetworkClient()
//    
//    // MARK: - URL
//    private var mostPopularMoviesUrl: URL {
//        guard let url = URL(string: "https://tv-api.com/api/top-250-movies?apikey=juv0ohccyeycmvbwn4du") else {
//            preconditionFailure("Unable to construct mostPopularMoviesUrl")
//        }
//        return url
//    }
//    
//    func loadMovies(handler: @escaping (Result<MostPopularMovies, Error>) -> Void) {
//        networkClient.fetch(url: mostPopularMoviesUrl) { result in
//            switch result {
//            case .success(let data):
//                do {
//                    let mostPopularMovies = try JSONDecoder().decode(MostPopularMovies.self, from: data)
//                    handler(.success(mostPopularMovies))
//                } catch {
//                    handler(.failure(error))
//                }
//            case .failure(let error):
//                handler(.failure(error))
//            }
//        }
//    }
//}

struct MoviesLoader: MoviesLoading {
  // MARK: - NetworkClient
  private let networkClient: NetworkRouting
  
  init(networkClient: NetworkRouting = NetworkClient()) {
      self.networkClient = networkClient
  }
    
    // MARK: - URL
    private var mostPopularMoviesUrl: URL {
        guard let url = URL(string: "https://tv-api.com/api/top-250-movies?apikey=juv0ohccyeycmvbwn4du") else {
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
                    handler(.success(mostPopularMovies))
                } catch {
                    handler(.failure(error))
                }
            case .failure(let error):
                handler(.failure(error))
            }
        }
    }
}
