//
//  Subject.swift
//  
//
//  Created by Van Simmons on 3/22/22.
//

public func CurrentValueSubject<Output>(
    currentValue: Output,
    buffering: AsyncStream<DistributorState<Output>.Action>.Continuation.BufferingPolicy = .bufferingOldest(1),
    onStartup: Resumption<Void>
) -> StateTask<DistributorState<Output>, DistributorState<Output>.Action> {
    .init(
        channel: .init(buffering: buffering),
        initialState: { channel in .init(currentValue: currentValue, nextKey: 0, downstreams: [:]) },
        onStartup: onStartup,
        reducer: Reducer(
            onCompletion: DistributorState<Output>.complete,
            disposer: DistributorState<Output>.dispose,
            reducer: DistributorState<Output>.reduce
        )
    )
}

public func CurrentValueSubject<Output>(
    currentValue: Output,
    buffering: AsyncStream<DistributorState<Output>.Action>.Continuation.BufferingPolicy = .bufferingOldest(1)
) async -> StateTask<DistributorState<Output>, DistributorState<Output>.Action> {
    await .stateTask(
        channel: .init(buffering: buffering),
        initialState: { channel in .init(currentValue: currentValue, nextKey: 0, downstreams: [:]) },
        reducer: Reducer(
            onCompletion: DistributorState<Output>.complete,
            disposer: DistributorState<Output>.dispose,
            reducer: DistributorState<Output>.reduce
        )
    )
}
