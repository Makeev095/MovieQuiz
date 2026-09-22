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
        request.timeoutInterval = 8
        request.assumesHTTP3Capable = false
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if error == nil,
               let data,
               let httpResponse = response as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode),
               !data.isEmpty {
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
        
        resolveIPv4(host: host) { [weak self] ips in
            guard let self, !ips.isEmpty else {
                handler(.failure(NetworkError.codeError))
                return
            }
            
            self.tryIPs(url: url, ips: ips, index: 0, handler: handler)
        }
    }
    
    private func tryIPs(url: URL, ips: [String], index: Int, handler: @escaping (Result<Data, Error>) -> Void) {
        guard index < ips.count else {
            handler(.failure(NetworkError.codeError))
            return
        }
        
        let id = UUID()
        let direct = DirectHTTPSRequest()
        lock.lock()
        inflight[id] = direct
        lock.unlock()
        
        direct.start(url: url, ip: ips[index]) { [weak self] result in
            self?.lock.lock()
            self?.inflight[id] = nil
            self?.lock.unlock()
            
            switch result {
            case .success:
                handler(result)
            case .failure:
                self?.tryIPs(url: url, ips: ips, index: index + 1, handler: handler)
            }
        }
    }
    
    private func resolveIPv4(host: String, completion: @escaping ([String]) -> Void) {
        switch host {
        case "tv-api.com":
            completion(["104.21.21.150", "172.67.199.79"])
            return
        case "wsrv.nl":
            completion(["188.114.97.3", "188.114.96.3"])
            return
        default:
            break
        }
        
        guard let dohURL = URL(string: "https://1.1.1.1/dns-query?name=\(host)&type=A") else {
            completion([])
            return
        }
        
        var request = URLRequest(url: dohURL)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        request.assumesHTTP3Capable = false
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let answers = json["Answer"] as? [[String: Any]]
            else {
                completion([])
                return
            }
            
            let ips = answers.compactMap { answer -> String? in
                guard (answer["type"] as? Int) == 1 else { return nil }
                return answer["data"] as? String
            }
            completion(ips)
        }.resume()
    }
}

private final class DirectHTTPSRequest {
    private var connection: NWConnection?
    private var didFinish = false
    private let lock = NSLock()
    private var handler: ((Result<Data, Error>) -> Void)?
    
    func start(url: URL, ip: String, handler: @escaping (Result<Data, Error>) -> Void) {
        self.handler = handler
        
        guard let host = url.host else {
            finish(.failure(URLError(.badURL)))
            return
        }
        
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.preferNoProxies = true
        
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: 443, using: parameters)
        self.connection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.send(url: url, host: host)
            case .failed(let error):
                self?.finish(.failure(error))
            default:
                break
            }
        }
        
        connection.start(queue: .global(qos: .userInitiated))
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.finish(.failure(URLError(.timedOut)))
        }
    }
    
    private func send(url: URL, host: String) {
        let target = Self.requestTarget(for: url)
        let http = "GET \(target) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: MovieQuiz/1.0\r\nConnection: close\r\nAccept: */*\r\n\r\n"
        
        connection?.send(content: Data(http.utf8), completion: .contentProcessed { [weak self] error in
            if let error {
                self?.finish(.failure(error))
                return
            }
            self?.receive(buffer: Data())
        })
    }
    
    private static func requestTarget(for url: URL) -> String {
        let absolute = url.absoluteString
        guard let schemeEnd = absolute.range(of: "://") else {
            return "/"
        }
        let afterScheme = absolute[schemeEnd.upperBound...]
        if let pathStart = afterScheme.firstIndex(of: "/") {
            return String(afterScheme[pathStart...])
        }
        return "/"
    }
    
    private func receive(buffer: Data) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            if let error {
                self?.finish(.failure(error))
                return
            }
            
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            
            if isComplete {
                self?.finish(Self.parse(buffer))
            } else {
                self?.receive(buffer: buffer)
            }
        }
    }
    
    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        let already = didFinish
        didFinish = true
        lock.unlock()
        
        guard !already else { return }
        connection?.cancel()
        connection = nil
        handler?(result)
        handler = nil
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
