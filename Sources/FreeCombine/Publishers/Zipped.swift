//
//  Zipped.swift
//  
//
//  Created by Van Simmons on 5/8/22.
//

public extension Publisher {
    func zip<Other>(
        _ other: Publisher<Other>
    ) -> Publisher<(Output, Other)> {
        Zipped(self, other)
    }
}

public func Zipped<Left, Right>(
    _ left: Publisher<Left>,
    _ right: Publisher<Right>
) -> Publisher<(Left, Right)> {
    zip(left, right)
}

public func zip<Left, Right>(
    _ left: Publisher<Left>,
    _ right: Publisher<Right>
) -> Publisher<(Left, Right)> {
    .init(
        initialState: ZipState<Left, Right>.create(left: left, right: right),
        buffering: .bufferingOldest(2),
        reducer: Reducer(
            onCompletion: ZipState<Left, Right>.complete,
            disposer: ZipState<Left, Right>.dispose,
            reducer: ZipState<Left, Right>.reduce
        ),
        extractor: \.mostRecentDemand
    )
}

public func zip<A, B, C>(
    _ one: Publisher<A>,
    _ two: Publisher<B>,
    _ three: Publisher<C>
) -> Publisher<(A, B, C)> {
    zip(zip(one, two), three)
        .map { ($0.0.0, $0.0.1, $0.1) }
}

public func zip<A, B, C, D>(
    _ one: Publisher<A>,
    _ two: Publisher<B>,
    _ three: Publisher<C>,
    _ four: Publisher<D>
) -> Publisher<(A, B, C, D)> {
    zip(zip(one, two), zip(three, four))
        .map { ($0.0.0, $0.0.1, $0.1.0, $0.1.1) }
}

public func zip<A, B, C, D, E>(
    _ one: Publisher<A>,
    _ two: Publisher<B>,
    _ three: Publisher<C>,
    _ four: Publisher<D>,
    _ five: Publisher<E>
) -> Publisher<(A, B, C, D, E)> {
    zip(zip(zip(one, two), zip(three, four)), five)
        .map { ($0.0.0.0, $0.0.0.1, $0.0.1.0, $0.0.1.1, $0.1) }
}

public func zip<A, B, C, D, E, F>(
    _ one: Publisher<A>,
    _ two: Publisher<B>,
    _ three: Publisher<C>,
    _ four: Publisher<D>,
    _ five: Publisher<E>,
    _ six: Publisher<F>
) -> Publisher<(A, B, C, D, E, F)> {
    zip(zip(zip(one, two), zip(three, four)), zip(five, six))
        .map { ($0.0.0.0, $0.0.0.1, $0.0.1.0, $0.0.1.1, $0.1.0, $0.1.1) }
}

public func zip<A, B, C, D, E, F, G>(
    _ one: Publisher<A>,
    _ two: Publisher<B>,
    _ three: Publisher<C>,
    _ four: Publisher<D>,
    _ five: Publisher<E>,
    _ six: Publisher<F>,
    _ seven: Publisher<G>
) -> Publisher<(A, B, C, D, E, F, G)> {
    zip(zip(zip(one, two), zip(three, four)), zip(zip(five, six), seven))
        .map { ($0.0.0.0, $0.0.0.1, $0.0.1.0, $0.0.1.1, $0.1.0.0, $0.1.0.1, $0.1.1) }
}

public func zip<A, B, C, D, E, F, G, H>(
    _ one: Publisher<A>,
    _ two: Publisher<B>,
    _ three: Publisher<C>,
    _ four: Publisher<D>,
    _ five: Publisher<E>,
    _ six: Publisher<F>,
    _ seven: Publisher<G>,
    _ eight: Publisher<H>
) -> Publisher<(A, B, C, D, E, F, G, H)> {
    zip(zip(zip(one, two), zip(three, four)), zip(zip(five, six), zip(seven, eight)))
        .map { ($0.0.0.0, $0.0.0.1, $0.0.1.0, $0.0.1.1, $0.1.0.0, $0.1.0.1, $0.1.1.0, $0.1.1.1) }
}
