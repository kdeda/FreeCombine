//
//  Collect.swift
//  
//
//  Created by Van Simmons on 5/19/22.
//

public extension Publisher {
    func collect() -> Publisher<[Output]> {
        return .init { continuation, downstream in
            let currentValue: ValueRef<[Output]> = ValueRef(value: [])
            return self(onStartup: continuation) { r in
                guard !Task.isCancelled else {
                    return try await handleCancellation(of: downstream)
                }
                switch r {
                    case .value(let a):
                        await currentValue.append(a)
                        return .more
                    case let .completion(value):
                        _ = try await downstream(.value(currentValue.value))
                        return try await downstream(.completion(value))
                }
            }
        }
    }
}
