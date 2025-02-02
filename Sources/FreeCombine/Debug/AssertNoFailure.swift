//
//  AssertNoFailure.swift
//  
//
//  Created by Van Simmons on 6/7/22.
//
public extension Publisher {
    func assertNoFailure(
        _ prefix: String = "",
           file: StaticString = #file,
           line: UInt = #line
    ) -> Self {
        .init { continuation, downstream in
            self(onStartup: continuation) { r in
                guard !Task.isCancelled else {
                    return try await handleCancellation(of: downstream)
                }
                switch r {
                    case .value, .completion(.cancelled), .completion(.finished):
                        return try await downstream(r)
                    case let .completion(.failure(error)):
                        fatalError("\(prefix) \(file)@\(line): \(error)")
                }
            }
        }
    }
}
