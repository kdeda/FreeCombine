//
//  Publisher+FlatMap.swift
//  FreeCombine
//
//  Created by Van Simmons on 4/17/20.
//  Copyright © 2020 ComputeCycles, LLC. All rights reserved.
//

// TODO: Implement flatMap
//public extension Publisher {
//    func flatMap<T>(
//        _ transform: @escaping (Output) -> Publisher<T, Failure>
//    ) -> Publisher<T, Failure> {
//        //public struct Publisher<T, Failure: Error> {
//        //    public let call: (Subscriber<T, Failure>) -> Subscription
//        //}
//
//        let hoist = { (downstream: Subscriber<T, Failure>) -> Subscriber<Output, Failure> in
//            downstream.contraFlatMap(downstream.join, transform)
//        }
//        
//        let lower = { (upstream: Subscription) -> Subscription in
//            upstream
//        }
//        
//        return .init(dimap(hoist, lower))
//    }
//}
