//
//  MergeState.swift
//  
//
//  Created by Van Simmons on 5/19/22.
//
struct MergeState<Output: Sendable> {
    typealias CombinatorAction = Self.Action
    enum Action {
        case setValue(AsyncStream<(Int, Output)>.Result, Resumption<Demand>)
        case removeCancellable(Int, Resumption<Demand>)
        case failure(Int, Error, Resumption<Demand>)
        var resumption: Resumption<Demand> {
            switch self {
                case .setValue(_, let resumption): return resumption
                case .removeCancellable(_, let resumption): return resumption
                case .failure(_, _, let resumption): return resumption
            }
        }
    }

    let downstream: (AsyncStream<Output>.Result) async throws -> Demand

    var cancellables: [Int: Cancellable<Demand>]
    var mostRecentDemand: Demand = .more

    init(
        channel: Channel<MergeState<Output>.Action>,
        downstream: @escaping (AsyncStream<(Output)>.Result) async throws -> Demand,
        upstreams upstream1: Publisher<Output>,
        _ upstream2: Publisher<Output>,
        _ otherUpstreams: [Publisher<Output>]
    ) async {
        self.downstream = downstream
        var localCancellables = [Int: Cancellable<Demand>]()
        let upstreams = ([upstream1, upstream2] + otherUpstreams).enumerated()
            .map { index, publisher in publisher.map { value in (index, value) } }

        for (index, publisher) in upstreams.enumerated() {
            localCancellables[index] = await channel.consume(publisher: publisher, using: { result, continuation in
                switch result {
                    case .value:
                        return .setValue(result, continuation)
                    case .completion(.finished), .completion(.cancelled):
                        return .removeCancellable(index, continuation)
                    case let .completion(.failure(error)):
                        return .failure(index, error, continuation)
                }
            })
        }
        cancellables = localCancellables
    }

    static func create(
        upstreams upstream1: Publisher<Output>,
        _ upstream2: Publisher<Output>,
        _ otherUpstreams: [Publisher<Output>]
    ) -> (@escaping (AsyncStream<Output>.Result) async throws -> Demand) -> (Channel<MergeState<Output>.Action>) async -> Self {
        { downstream in { channel in
            await .init(channel: channel, downstream: downstream, upstreams: upstream1, upstream2, otherUpstreams)
        } }
    }

    static func complete(state: inout Self, completion: Reducer<Self, Self.Action>.Completion) async -> Void {
        for can in state.cancellables.values { can.cancel(); _ = await can.result }
        state.cancellables.removeAll()
        guard state.mostRecentDemand != .done else { return }
        do {
            switch completion {
                case .finished:
                    state.mostRecentDemand = try await state.downstream(.completion(.finished))
                case .cancel:
                    state.mostRecentDemand = try await state.downstream(.completion(.cancelled))
                case .exit, .failure:
                    () // These came from downstream and should not go down again
            }
        } catch { }
    }

    static func dispose(action: Self.Action, completion: Reducer<Self, Self.Action>.Completion) async -> Void {
        action.resumption.resume(throwing: PublisherError.cancelled)
    }

    static func reduce(
        `self`: inout Self,
        action: Self.Action
    ) async throws -> Reducer<Self, Action>.Effect {
        return try await `self`.reduce(action: action)
    }

    private mutating func reduce(
        action: Self.Action
    ) async throws -> Reducer<Self, Action>.Effect {
        guard !Task.isCancelled else {
            action.resumption.resume(throwing: PublisherError.cancelled)
            return .completion(.cancel)
        }
        switch action {
            case let .setValue(value, continuation):
                return try await reduceValue(value, continuation)
            case let .removeCancellable(index, continuation):
                continuation.resume(returning: .done)
                if let c = cancellables.removeValue(forKey: index) {
                    let _ = await c.result
                }
                if cancellables.count == 0 {
                    let c: Completion = Task.isCancelled ? .cancelled : .finished
                    mostRecentDemand = try await downstream(.completion(c))
                    return .completion(.exit)
                }
                return .none
            case let .failure(_, error, continuation):
                continuation.resume(returning: .done)
                cancellables.removeAll()
                mostRecentDemand = try await downstream(.completion(.failure(error)))
                return .completion(.failure(error))
        }
    }

    private mutating func reduceValue(
        _ value: AsyncStream<(Int, Output)>.Result,
        _ resumption: Resumption<Demand>
    ) async throws -> Reducer<Self, Action>.Effect {
        switch value {
            case let .value((index, output)):
                guard let _ = cancellables[index] else {
                    fatalError("received value after task completion")
                }
                do {
                    mostRecentDemand = try await downstream(.value(output))
                    resumption.resume(returning: mostRecentDemand)
                    return .none
                }
                catch {
                    resumption.resume(throwing: error)
                    return .completion(.failure(error))
                }
            case let .completion(.failure(error)):
                resumption.resume(returning: .done)
                return .completion(.failure(error))
            case .completion(.finished):
                resumption.resume(returning: .done)
                return .none
            case .completion(.cancelled):
                resumption.resume(returning: .done)
                return .none
        }
    }
}
