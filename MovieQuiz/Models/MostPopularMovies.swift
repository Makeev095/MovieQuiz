//
//  MostPopularMovies.swift
//  MovieQuiz
//
//  Created by Дмитрий Макеев on 21.09.2026.
//

import Foundation

struct MostPopularMovies: Codable {
    let errorMessage: String?
    let items: [MostPopularMovie]
}

struct MostPopularMovie: Codable {
    let title: String
    let rating: String
    let imageURL: URL
    
    var resizedImageURL: URL {
        let urlString = imageURL.absoluteString
        let imageUrlString = urlString.components(separatedBy: "._")[0] + "._V0_UX600_.jpg"
        
        guard let newURL = URL(string: imageUrlString) else {
            return imageURL
        }
        
        return newURL
    }
    
    private enum CodingKeys: String, CodingKey {
        case title = "fullTitle"
        case rating = "imDbRating"
        case imageURL = "image"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        imageURL = try container.decode(URL.self, forKey: .imageURL)
        
        if let ratingString = try? container.decode(String.self, forKey: .rating) {
            rating = ratingString
        } else if let ratingValue = try? container.decode(Double.self, forKey: .rating) {
            rating = String(ratingValue)
        } else {
            rating = "0"
        }
    }
}
