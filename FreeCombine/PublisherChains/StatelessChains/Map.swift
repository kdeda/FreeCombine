//
//  Composition.swift
//  FreeCombine
//
//  Created by Van Simmons on 4/13/20.
//  Copyright © 2020 ComputeCycles, LLC. All rights reserved.
//

public extension Publisher {
    func map<T>(
        _ transform: @escaping (Output) -> T
    ) -> Publisher<T, Failure> {
        transformation(transformPublication: Publication.map(transform))
    }
}
