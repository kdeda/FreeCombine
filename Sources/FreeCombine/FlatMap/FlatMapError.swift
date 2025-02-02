//
//  FlatMapError.swift
//  
//
//  Created by Van Simmons on 5/18/22.
//
public extension Publisher {
    func flatMapError(_ f: @escaping (Swift.Error) async -> Publisher<Output>) -> Publisher<Output> {
        .init { continuation, downstream in
            self(onStartup: continuation) { r in switch r {
                case .value(let a):
                    return try await downstream(.value(a))
                case .completion(.failure(let e)):
                    return try await f(e)(flattener(downstream)).value
                case .completion(.finished):
                    return try await downstream(.completion(.finished))
                case .completion(.cancelled):
                    return try await downstream(.completion(.cancelled))
            } }
        }
    }
}
