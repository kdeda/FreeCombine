//
//  CompactMap.swift
//  FreeCombine
//
//  Created by Van Simmons on 4/25/20.
//  Copyright © 2020 ComputeCycles, LLC. All rights reserved.
//

public extension Publisher {
    func compactMap<T>(
        _ isIncluded: @escaping (T?) -> T
    ) -> Publisher<Output, Failure> where Output == T? {
        let ref = StateRef<Demand>(.max(1))
        return transformation(
            joinSubscriber: { downstream in
                .init { (publication) -> Demand in
                    switch publication {
                    case .value(let value):
                        return value != nil ? ref.save(downstream(.value(value!))) : ref.state
                    case .none, .failure, .finished:
                        return downstream(publication)
                    }
                }
            },
            transformPublication: identity
        )
    }
}
