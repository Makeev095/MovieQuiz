//
//  NetworkClient.swift
//  MovieQuiz
//
//  Created by Дмитрий Макеев on 21.09.2026.
//

import Foundation
import Network

final class NetworkClient {

    private enum NetworkError: Error {
        case codeError
        case emptyData
    }
    
    private var inflight: [UUID: DirectHTTPSRequest] = [:]
    private let lock = NSLock()
    
    func fetch(url: URL, handler: @escaping (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.assumesHTTP3Capable = false
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if error == nil,
               let data,
               let httpResponse = response as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode) {
                handler(.success(data))
                return
            }
            
            self?.fetchByIP(url: url, handler: handler)
        }.resume()
    }
    
    private func fetchByIP(url: URL, handler: @escaping (Result<Data, Error>) -> Void) {
        guard let host = url.host else {
            handler(.failure(NetworkError.codeError))
            return
        }
        
        resolveIPv4(host: host) { [weak self] ip in
            guard let self, let ip else {
                handler(.failure(NetworkError.codeError))
                return
            }
            
            let id = UUID()
            let direct = DirectHTTPSRequest()
            self.lock.lock()
            self.inflight[id] = direct
            self.lock.unlock()
            
            direct.start(url: url, ip: ip) { [weak self] result in
                self?.lock.lock()
                self?.inflight[id] = nil
                self?.lock.unlock()
                handler(result)
            }
        }
    }
    
    private func resolveIPv4(host: String, completion: @escaping (String?) -> Void) {
        if host == "tv-api.com" {
            completion("104.21.21.150")
            return
        }
        
        guard let dohURL = URL(string: "https://1.1.1.1/dns-query?name=\(host)&type=A") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: dohURL)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        request.assumesHTTP3Capable = false
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let answers = json["Answer"] as? [[String: Any]]
            else {
                completion(nil)
                return
            }
            
            let ip = answers.first(where: { ($0["type"] as? Int) == 1 })?["data"] as? String
            completion(ip)
        }.resume()
    }
}

private final class DirectHTTPSRequest {
    private var connection: NWConnection?
    
    func start(url: URL, ip: String, handler: @escaping (Result<Data, Error>) -> Void) {
        guard let host = url.host else {
            handler(.failure(URLError(.badURL)))
            return
        }
        
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
        
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.preferNoProxies = true
        
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: 443, using: parameters)
        self.connection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.send(url: url, host: host, handler: handler)
            case .failed(let error):
                handler(.failure(error))
                connection.cancel()
            default:
                break
            }
        }
        
        connection.start(queue: .global(qos: .userInitiated))
    }
    
    private func send(url: URL, host: String, handler: @escaping (Result<Data, Error>) -> Void) {
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let http = "GET \(path)\(query) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\nAccept: */*\r\n\r\n"
        
        connection?.send(content: Data(http.utf8), completion: .contentProcessed { [weak self] error in
            if let error {
                handler(.failure(error))
                self?.connection?.cancel()
                return
            }
            self?.receive(buffer: Data(), handler: handler)
        })
    }
    
    private func receive(buffer: Data, handler: @escaping (Result<Data, Error>) -> Void) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            if let error {
                handler(.failure(error))
                self?.connection?.cancel()
                return
            }
            
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            
            if isComplete {
                self?.connection?.cancel()
                handler(Self.parse(buffer))
            } else {
                self?.receive(buffer: buffer, handler: handler)
            }
        }
    }
    
    private static func parse(_ data: Data) -> Result<Data, Error> {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return .failure(URLError(.cannotParseResponse))
        }
        
        let headerText = String(data: data.subdata(in: 0..<headerEnd.lowerBound), encoding: .isoLatin1) ?? ""
        let body = data.subdata(in: headerEnd.upperBound..<data.count)
        let status = headerText.components(separatedBy: " ").dropFirst().first
        
        guard status == "200" else {
            return .failure(URLError(.badServerResponse))
        }
        
        if headerText.lowercased().contains("transfer-encoding: chunked") {
            return .success(decodeChunked(body))
        }
        return .success(body)
    }
    
    private static func decodeChunked(_ data: Data) -> Data {
        var result = Data()
        var remaining = data
        
        while !remaining.isEmpty {
            guard let lineEnd = remaining.range(of: Data("\r\n".utf8)) else { break }
            let sizeText = String(data: remaining.subdata(in: 0..<lineEnd.lowerBound), encoding: .ascii) ?? "0"
            let size = Int(sizeText.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16) ?? 0
            remaining = remaining.subdata(in: lineEnd.upperBound..<remaining.count)
            if size == 0 { break }
            guard remaining.count >= size else { break }
            result.append(remaining.subdata(in: 0..<size))
            let next = size + 2
            if remaining.count >= next {
                remaining = remaining.subdata(in: next..<remaining.count)
            } else {
                break
            }
        }
        
        return result
    }
}
