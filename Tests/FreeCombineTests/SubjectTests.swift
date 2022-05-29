//
//  SubjectTests.swift
//  
//
//  Created by Van Simmons on 5/13/22.
//
import XCTest
@testable import FreeCombine

class SubjectTests: XCTestCase {

    override func setUpWithError() throws { }

    override func tearDownWithError() throws { }

    func testSimpleSubject() async throws {
        let expectation = await CheckedExpectation<Void>()

        let subject = await CurrentValueSubject(
            currentValue: 14,
            buffering: .unbounded
        )

        let publisher1 = subject.publisher()

        let counter = Counter()

        let c1 = await publisher1.sink { (result: AsyncStream<Int>.Result) in
            let count = await counter.count
            switch result {
                case .value:
                    _ = await counter.increment()
                    return .more
                case let .completion(.failure(error)):
                    XCTFail("Got an error? \(error)")
                    return .done
                case .completion(.finished):
                    XCTAssert(count == 5, "wrong number of values sent: \(count)")
                    do {
                        try await expectation.complete()
                    }
                    catch { XCTFail("Failed to complete: \(error)") }
                    return .done
                case .completion(.cancelled):
                    XCTFail("Should not have cancelled")
                    return .done
            }
        }
        do {
            try await subject.send(14)
            try await subject.send(15)
            try await subject.send(16)
            try await subject.send(17)
            try await subject.finish()
        } catch {
            XCTFail("Caught error: \(error)")
        }

        do { try await FreeCombine.wait(for: expectation, timeout: 100_000_000) }
        catch {
            let count = await counter.count
            XCTFail("Timed out, count = \(count)")
        }
        c1.cancel()
    }

    func testMultisubscriptionSubject() async throws {
        let expectation1 = await CheckedExpectation<Void>()
        let expectation2 = await CheckedExpectation<Void>()

        let subject = await CurrentValueSubject(currentValue: 14)
        let publisher = subject.publisher()

        let counter1 = Counter()
        let c1 = await publisher.sink { (result: AsyncStream<Int>.Result) in
            let count = await counter1.count
            switch result {
                case .value:
                    _ = await counter1.increment()
                    return .more
                case let .completion(.failure(error)):
                    XCTFail("Got an error? \(error)")
                    return .done
                case .completion(.finished):
                    XCTAssert(count == 5, "wrong number of values sent: \(count)")
                    do { try await expectation1.complete() }
                    catch { XCTFail("Failed to complete: \(error)") }
                    return .done
                case .completion(.cancelled):
                    XCTFail("Should not have cancelled")
                    return .done
            }
        }

        let counter2 = Counter()
        let c2 = await publisher.sink { (result: AsyncStream<Int>.Result) in
            let count = await counter2.count
            switch result {
                case .value:
                    _ = await counter2.increment()
                    return .more
                case let .completion(.failure(error)):
                    XCTFail("Got an error? \(error)")
                    return .done
                case .completion(.finished):
                    XCTAssert(count == 5, "wrong number of values sent: \(count)")
                    do { try await expectation2.complete() }
                    catch { XCTFail("Failed to complete: \(error)") }
                    return .done
                case .completion(.cancelled):
                    XCTFail("Should not have cancelled")
                    return .done
            }
        }

        do {
            try await subject.send(14)
            try await subject.send(15)
            try await subject.send(16)
            try await subject.send(17)
            try await subject.finish()
        } catch {
            XCTFail("Caught error: \(error)")
        }

        do {
            try await FreeCombine.wait(
                for: [expectation1, expectation2],
                timeout: 100_000_000,
                reducing: (),
                with: { _, _ in }
            )
        }
        catch {
            XCTFail("Timed out")
        }
        c1.cancel()
        c2.cancel()
    }

    func testSimpleCancellation() async throws {
        let counter = Counter()
        let expectation = await CheckedExpectation<Void>(name: "expectation")
        let expectation2 = await CheckedExpectation<Void>(name: "expectation2")
        let release = await CheckedExpectation<Void>(name: "release")

        let subject = await PassthroughSubject(Int.self, buffering: .unbounded)
        let p = subject.publisher()

        let can = await p.sink({ result in
            switch result {
                case let .value(value):
                    let count = await counter.increment()
                    XCTAssertEqual(value, count, "Wrong value sent")
                    if count == 8 {
                        do { try await expectation.complete() }
                        catch {  XCTFail("failed to complete") }
                        do {
                            try await FreeCombine.wait(for: release, timeout: 10_000_000)
                        } catch {
                            guard let error = error as? PublisherError, case error = PublisherError.cancelled else {
                                XCTFail("Timed out waiting for release")
                                return .done
                            }
                        }
                    } else if count > 8 {
                        if !Task.isCancelled { XCTFail("Should be cancelled"); throw PublisherError.internalError }
                        XCTFail("Got value after cancellation")
                        throw PublisherError.internalError
                    }
                    return .more
                case let .completion(.failure(error)):
                    XCTFail("Should not have gotten error: \(error)")
                    return .done
                case .completion(.finished):
                    return .done
                case .completion(.cancelled):
                    XCTFail("Should not have cancelled")
                    return .done
            }
        })

        for i in 1 ... 7 {
            do { try await subject.send(i) }
            catch { XCTFail("Failed to enqueue") }
        }

        do { try subject.nonBlockingSend(8) }
        catch { XCTFail("Failed to enqueue") }

        do { try await FreeCombine.wait(for: expectation, timeout: 1_000_000_000) }
        catch { XCTFail("Failed waiting for expectation") }

        can.cancel()
        try await release.complete()

        do {
            try await subject.send(9)
            try await subject.send(10)
        } catch {
            XCTFail("Failed to enqueue")
        }
        try await subject.finish()
        try await expectation2.complete()

        do {
            try await FreeCombine.wait(for: expectation2, timeout: 100_000_000)
        } catch {
            XCTFail("Timed out")
        }
    }

    func testSimpleTermination() async throws {
        let counter = Counter()
        let expectation = await CheckedExpectation<Void>()

        let subject = await PassthroughSubject(Int.self)
        let p = subject.publisher()

        let c1 = await p.sink( { result in
            switch result {
                case let .value(value):
                    let count = await counter.increment()
                    XCTAssertEqual(value, count, "Wrong value sent")
                    return .more
                case let .completion(.failure(error)):
                    XCTFail("Should not have gotten error: \(error)")
                    return .done
                case .completion(.finished):
                    do { try await expectation.complete() }
                    catch { XCTFail("Failed to complete expectation") }
                    let count = await counter.count
                    XCTAssert(count == 1000, "Received wrong number of invocations: \(count)")
                    return .done
                case .completion(.cancelled):
                    XCTFail("Should not have cancelled")
                    return .done
            }
        })

        for i in 1 ... 1000 {
            do { try await subject.send(i) }
            catch { XCTFail("Failed to enqueue") }
        }
        try await subject.finish()

        do {
            try await FreeCombine.wait(for: expectation, timeout: 50_000_000)
        } catch {
            let count = await counter.count
            XCTFail("Timed out waiting for expectation.  processed: \(count)")
        }
        c1.cancel()
    }

    func testSimpleSubjectSend() async throws {
        let counter = Counter()
        let expectation = await CheckedExpectation<Void>()

        let subject = await PassthroughSubject(Int.self)
        let p = subject.publisher()

        let c1 = await p.sink({ result in
            switch result {
                case let .value(value):
                    let count = await counter.increment()
                    XCTAssertEqual(value, count, "Wrong value sent")
                    return .more
                case let .completion(.failure(error)):
                    XCTFail("Should not have gotten error: \(error)")
                    return .done
                case .completion(.finished):
                    do { try await expectation.complete() }
                    catch { XCTFail("Could not complete, error: \(error)") }
                    let count = await counter.count
                    XCTAssert(count == 5, "Received wrong number of invocations: \(count)")
                    return .done
                case .completion(.cancelled):
                    XCTFail("Should not have cancelled")
                    return .done
            }
        })

        for i in (1 ... 5) {
            do { try await subject.send(i) }
            catch { XCTFail("Failed to enqueue") }
        }
        try await subject.finish()

        do {
            try await FreeCombine.wait(for: expectation, timeout: 10_000_000)
        } catch {
            let count = await counter.count
            XCTFail("Timed out waiting for expectation.  processed: \(count)")
        }
        c1.cancel()
    }

    func testSyncAsync() async throws {
        let expectation = await CheckedExpectation<Void>()
        let fsubject1 = await FreeCombine.PassthroughSubject(Int.self)
        let fsubject2 = await FreeCombine.PassthroughSubject(String.self)
        
        let fseq1 = "abcdefghijklmnopqrstuvwxyz".asyncPublisher
        let fseq2 = (1 ... 100).asyncPublisher

        let fz1 = fseq1.zip(fseq2)
        let fz2 = fz1.map { left, right in String(left) + String(right) }

        let fm1 = fsubject1.publisher()
            .map(String.init)
            .merge(with: fsubject2.publisher())

        let counter = Counter()
        let c1 = await fz2
            .merge(with: fm1)
            .sink({ value in
                switch value {
                    case .value(_):
                        await counter.increment()
                        return .more
                    case let .completion(.failure(error)):
                        XCTFail("Should not have received failure: \(error)")
                        return .done
                    case .completion(.finished):
                        let count = await counter.count
                        if count != 28  { XCTFail("Incorrect number of values") }
                        try await expectation.complete()
                        return .done
                    case .completion(.cancelled):
                        XCTFail("Should not have cancelled")
                        return .done
                }
            })

        try await fsubject1.send(14)
        try await fsubject2.send("hello, combined world!")

        try await fsubject1.finish()
        try await fsubject2.finish()

        do { try await FreeCombine.wait(for: expectation, timeout: 10_000_000_000) }
        catch { XCTFail("timed out") }

        c1.cancel()
    }
}
