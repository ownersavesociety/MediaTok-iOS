import Foundation
import XCTest

final class MTKeysTests: XCTestCase {
    func testPeerKeyStringRoundTrip() {
        let key = MTPeerKey(namespace: 2, id: 1234567890)
        XCTAssertEqual(key?.stringValue, "2:1234567890")
        XCTAssertEqual(MTPeerKey(string: "2:1234567890"), key)
        XCTAssertEqual(MTPeerKey(string: "3:-5"), MTPeerKey(namespace: 3, id: -5))
    }

    func testPeerKeyRejectsNonCanonicalText() {
        for text in ["", "2", ":5", "2:", "8:1", "-1:1", "02:5", "2:05", "2:+5", " 2:5", "2:5 ", "2:5:6", "a:b", "2:-0"] {
            XCTAssertNil(MTPeerKey(string: text), text)
        }
        XCTAssertNil(MTPeerKey(namespace: 8, id: 1))
        XCTAssertNil(MTPeerKey(namespace: -1, id: 1))
    }

    func testMessageKeyStringRoundTrip() {
        let peer = MTPeerKey(namespace: 0, id: 777000)!
        let key = MTMessageKey(peer: peer, namespace: 0, id: 1234)
        XCTAssertEqual(key.stringValue, "0:777000/0:1234")
        XCTAssertEqual(MTMessageKey(string: "0:777000/0:1234"), key)
        XCTAssertEqual(MTMessageKey(string: "2:5/3:-7")?.namespace, 3)
        for text in ["0:777000", "0:777000/", "0:777000/0", "0:777000/0:1234/1", "9:1/0:1", "0:1/0:99999999999"] {
            XCTAssertNil(MTMessageKey(string: text), text)
        }
    }

    func testCodableUsesTheStringForms() throws {
        let peer = MTPeerKey(namespace: 1, id: 42)!
        let message = MTMessageKey(peer: peer, namespace: 0, id: 7)
        let account = MTAccountID(rawValue: -9)
        let encoder = JSONEncoder()
        XCTAssertEqual(String(decoding: try encoder.encode(peer), as: UTF8.self), "\"1:42\"")
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: try encoder.encode(message)), "1:42/0:7")
        XCTAssertEqual(String(decoding: try encoder.encode(account), as: UTF8.self), "-9")

        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(MTPeerKey.self, from: Data("\"1:42\"".utf8)), peer)
        XCTAssertEqual(try decoder.decode(MTMessageKey.self, from: Data("\"1:42/0:7\"".utf8)), message)
        XCTAssertEqual(try decoder.decode(MTAccountID.self, from: Data("-9".utf8)), account)
        XCTAssertThrowsError(try decoder.decode(MTPeerKey.self, from: Data("\"9:1\"".utf8)))
        XCTAssertEqual(try decoder.decode(Set<MTPeerKey>.self, from: Data("[\"1:42\"]".utf8)), [peer])
    }

    func testOrdering() {
        let a = MTPeerKey(namespace: 0, id: 5)!
        let b = MTPeerKey(namespace: 0, id: 6)!
        let c = MTPeerKey(namespace: 1, id: 1)!
        XCTAssertEqual([c, b, a].sorted(), [a, b, c])
        XCTAssertTrue(MTMessageKey(peer: a, namespace: 1, id: 1) < MTMessageKey(peer: b, namespace: 0, id: 0))
        XCTAssertTrue(MTAccountID(rawValue: -1) < MTAccountID(rawValue: 1))
    }

    /// Vectors computed from the bit layout of `PeerId.init(_ n: Int64)` / `_toInt64()` in
    /// Postbox/Sources/Peer.swift. The TelegramCore bridge re-checks them against Postbox itself.
    func testLegacyInt64Vectors() {
        let vectors: [(Int32, Int64, Int64)] = [
            (0, 777000, 777000),
            (2, 1234567890, 9824502482),
            (3, -5, 17179869179),
            (0, 4294967301, 34359738373),
            (7, 0, 9223372032559808512),
            (2, 1000000000000, 7983616823296),
            (2, 1234567890123, 9871747122379),
            (0, 5000000000, 35064771072)
        ]
        for (namespace, id, legacy) in vectors {
            let key = MTPeerKey(namespace: namespace, id: id)!
            XCTAssertEqual(MTLegacyKeys.peerKey(fromLegacyInt64: legacy), key, "\(legacy)")
            XCTAssertEqual(MTLegacyKeys.legacyInt64(of: key), legacy, "\(key)")
        }
        XCTAssertNil(MTLegacyKeys.legacyInt64(of: MTPeerKey(namespace: 3, id: -5000000000)!))
    }

    func testLegacyMessageKeys() {
        let key = MTLegacyKeys.messageKey(fromLegacyString: "9824502482_15")
        XCTAssertEqual(key?.peer, MTPeerKey(namespace: 2, id: 1234567890))
        XCTAssertEqual(key?.namespace, 0)
        XCTAssertEqual(key?.id, 15)
        XCTAssertEqual(MTLegacyKeys.messageKey(fromLegacyString: "777000_3", messageNamespace: 1)?.namespace, 1)
        for text in ["", "777000", "_3", "777000_", "777000_x", "a_1", "777000_99999999999"] {
            XCTAssertNil(MTLegacyKeys.messageKey(fromLegacyString: text), text)
        }
        XCTAssertEqual(MTLegacyKeys.peerKey(fromRawId: 1234567890, namespace: 2), MTPeerKey(namespace: 2, id: 1234567890))
        XCTAssertNil(MTLegacyKeys.peerKey(fromRawId: 1, namespace: 9))
    }

    func testAccountIdStringForm() {
        XCTAssertEqual(MTAccountID(rawValue: -42).stringValue, "-42")
        XCTAssertEqual(MTAccountID(string: "-42"), MTAccountID(rawValue: -42))
        XCTAssertNil(MTAccountID(string: "042"))
        XCTAssertNil(MTAccountID(string: "x"))
    }
}
