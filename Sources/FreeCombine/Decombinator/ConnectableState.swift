//
//  MulticasterState.swift
//  
//
//  Created by Van Simmons on 6/5/22.
//

public struct ConnectableState<Output: Sendable> {
    public enum Action: Sendable, CustomStringConvertible {
        case connect(Resumption<Void>)
        case pause(Resumption<Void>)
        case resume(Resumption<Void>)
        case disconnect(Resumption<Void>)
        case distribute(DistributorState<Output>.Action)

        public var description: String {
            switch self {
                case .connect: return "connect"
                case .pause: return "pause"
                case .resume: return "resume"
                case .disconnect: return "disconnect"
                case let .distribute(subaction): return "distribute(\(subaction))"
            }
        }
    }

    public enum Error: Swift.Error {
        case alreadyConnected
        case alreadyDisconnected
        case disconnected
        case alreadyPaused
        case alreadyResumed
        case alreadyCompleted
        case internalError
    }

    let upstream: Publisher<Output>
    let downstream: @Sendable (AsyncStream<Output>.Result) async throws -> Demand

    var cancellable: Cancellable<Demand>?
    var upstreamContinuation: Resumption<Demand>?
    var isRunning: Bool = false
    var distributor: DistributorState<Output>

    public init(
        file: StaticString = #file,
        line: UInt = #line,
        deinitBehavior: DeinitBehavior = .assert,
        upstream: Publisher<Output>,
        channel: Channel<ConnectableState<Output>.Action>
    ) {
        self.upstream = upstream
        self.distributor = .init(currentValue: .none, nextKey: 0, downstreams: [:])
        self.downstream = { r in
            var queueStatus: AsyncStream<ConnectableState<Output>.Action>.Continuation.YieldResult!
            let _: Void = try await withResumption(file: file, line: line, deinitBehavior: deinitBehavior) { resumption in
                queueStatus = channel.yield(.distribute(.receive(r, resumption)))
                switch queueStatus {
                    case .enqueued:
                        ()
                    case .terminated:
                        resumption.resume(throwing: PublisherError.cancelled)
                    case .dropped:
                        fatalError("Should never drop")
                    case .none:
                        fatalError("must have a queue status")
                    @unknown default:
                        fatalError("Handle new case")
                }
            }
            if case .enqueued = queueStatus { return .more }
            return .done
        }
    }

    static func create(
        upstream: Publisher<Output>
    ) -> (Channel<ConnectableState<Output>.Action>) -> Self {
        { channel in return .init(upstream: upstream, channel: channel) }
    }

    static func complete(state: inout Self, completion: Reducer<Self, Self.Action>.Completion) async -> Void {
        switch completion {
            case .finished, .exit:
                try? await state.distributor.process(currentRepeaters: state.distributor.repeaters, with: .completion(.finished))
            case let .failure(error):
                try? await state.distributor.process(currentRepeaters: state.distributor.repeaters, with: .completion(.failure(error)))
            case .cancel:
                try? await state.distributor.process(currentRepeaters: state.distributor.repeaters, with: .completion(.cancelled))
        }
        for (_, repeater) in state.distributor.repeaters {
            repeater.finish()
        }
        state.distributor.repeaters.removeAll()
        state.cancellable?.cancel()
    }

    static func distributorCompletion(
        _ completion: Reducer<Self, Self.Action>.Completion
    ) -> Reducer<DistributorState<Output>, DistributorState<Output>.Action>.Completion {
        switch completion {
            case .finished: return .finished
            case .exit: return .exit
            case let .failure(error): return .failure(error)
            case .cancel:
                return .cancel
        }
    }

    static func dispose(action: Self.Action, completion: Reducer<Self, Self.Action>.Completion) async -> Void {
        switch action {
            case let .connect(continuation):
                continuation.resume(throwing: Error.alreadyCompleted)
            case let .pause(continuation):
                continuation.resume(throwing: Error.alreadyCompleted)
            case let .resume(continuation):
                continuation.resume(throwing: Error.alreadyCompleted)
            case let .disconnect(continuation):
                continuation.resume(throwing: Error.alreadyCompleted)
            case let .distribute(distributorAction):
                await DistributorState<Output>.dispose(action: distributorAction, completion: distributorCompletion(completion))
        }
    }

    static func reduce(`self`: inout Self, action: Self.Action) async throws -> Reducer<Self, Action>.Effect {
        if Task.isCancelled {
            switch action {
                case let .connect(continuation):
                    continuation.resume(throwing: PublisherError.cancelled)
                case let .pause(continuation):
                    continuation.resume(throwing: PublisherError.cancelled)
                case let .resume(continuation):
                    continuation.resume(throwing: PublisherError.cancelled)
                case let .disconnect(continuation):
                    continuation.resume(throwing: PublisherError.cancelled)
                case let .distribute(distributorAction):
                    await DistributorState<Output>.dispose(action: distributorAction, completion: .cancel)
            }
        }
        return try await `self`.reduce(action: action)
    }

    mutating func reduce(action: Action) async throws -> Reducer<Self, Action>.Effect {
        switch action {
            case let .connect(continuation):
                return try await connect(continuation)
            case let .pause(continuation):
                return try await pause(continuation)
            case let .resume(continuation):
                return try await resume(continuation)
            case let .disconnect(continuation):
                return try await disconnect(continuation)
            case let .distribute(action):
                return try await distribute(action)
        }
    }

    mutating func connect(
        _ resumption: Resumption<Void>
    ) async throws -> Reducer<Self, Action>.Effect {
        guard case .none = cancellable else {
            resumption.resume()
            return .none
        }
        let localUpstream = upstream
        let localDownstream = downstream
        cancellable = try await Cancellable.join {
            await localUpstream.sink(localDownstream)
        }
        isRunning = true
        resumption.resume()
        return .none
    }

    mutating func pause(
        _ resumption: Resumption<Void>
    ) async throws -> Reducer<Self, Action>.Effect {
        guard let _ = cancellable else {
            resumption.resume(throwing: Error.disconnected)
            return .completion(.failure(Error.disconnected))
        }
        guard isRunning else {
            resumption.resume(throwing: Error.alreadyPaused)
            return .completion(.failure(Error.alreadyPaused))
        }
        isRunning = false
        resumption.resume()
        return .none
    }

    mutating func resume(
        _ resumption: Resumption<Void>
    ) async throws -> Reducer<Self, Action>.Effect {
        guard let _ = cancellable else {
            resumption.resume(throwing: Error.disconnected)
            return .completion(.failure(Error.disconnected))
        }
        guard !isRunning else {
            resumption.resume(throwing: Error.alreadyResumed)
            return .completion(.failure(Error.alreadyResumed))
        }
        isRunning = true
        upstreamContinuation?.resume(returning: .more)
        resumption.resume()
        return .none
    }

    mutating func disconnect(
        _ resumption: Resumption<Void>
    ) async throws -> Reducer<Self, Action>.Effect {
        guard let _ = cancellable else {
            resumption.resume(throwing: Error.alreadyDisconnected)
            return .completion(.failure(Error.alreadyDisconnected))
        }
        isRunning = false
        upstreamContinuation?.resume(returning: .done)
        resumption.resume()
        return .completion(.exit)
    }

    mutating func distribute(
        _ action: DistributorState<Output>.Action
    ) async throws -> Reducer<Self, Action>.Effect {
        switch try await distributor.reduce(action: action) {
            case .none:
                return .none
            case .published(_):
                return .none // FIXME: Need to handle this
            case let .completion(completion):
                switch completion {
                    case .finished:
                        return .completion(.finished)
                    case .exit:
                        return .completion(.exit)
                    case let .failure(error):
                        return .completion(.failure(error))
                    case .cancel:
                        return .completion(.cancel)
                }
        }
    }
}
