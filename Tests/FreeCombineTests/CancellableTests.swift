//
//  CancellableTests.swift
//  
//
//  Created by Van Simmons on 6/8/22.
//

import XCTest
@testable import FreeCombine

final class CancellableTests: XCTestCase {

    override func setUpWithError() throws { }

    override func tearDownWithError() throws { }

    func testCancellable() async throws {
        let expectation1 = await Expectation<Void>()
        let expectation2 = await Expectation<Void>()
        let expectation3 = await Expectation<Void>()

        let expectation1a = await Expectation<Bool>()
        let expectation2a = await Expectation<Bool>()
        let expectation3a = await Expectation<Bool>()

        var c: Cancellable<(Cancellable<Void>, Cancellable<Void>, Cancellable<Void>)>? = .none
        c = Cancellable {
            let t1 = Cancellable(deinitBehavior: .silentCancel) {
                try await expectation1.value
                try expectation1a.complete(Task.isCancelled)
            }
            let t2 = Cancellable(deinitBehavior: .silentCancel) {
                try await expectation2.value
                try expectation2a.complete(Task.isCancelled)
            }
            let t3 = Cancellable(deinitBehavior: .silentCancel) {
                try await expectation3.value
                try expectation3a.complete(Task.isCancelled)
            }
            return (t1, t2, t3)
        }
        let _ = await c?.result
        if let c = c {
            XCTAssert(c.isCompleting, "Not marked as completing")
        } else {
            XCTFail("should exist")
        }
        c = .none

        try await Task.sleep(nanoseconds: 10_000)

        try await expectation1.complete()
        try await expectation2.complete()
        try await expectation3.complete()

        let r1 = try await expectation1a.value
        let r2 = try await expectation2a.value
        let r3 = try await expectation3a.value

        XCTAssert(r1, "Inner task 1 not cancelled")
        XCTAssert(r2, "Inner task 2 not cancelled")
        XCTAssert(r3, "Inner task 3 not cancelled")
    }
}
