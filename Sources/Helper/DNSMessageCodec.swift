import Foundation

/// RFC 1035 DNS wire-format helpers used by the local resolver proxy.
enum DNSMessageCodec {
    struct Question: Equatable {
        let name: String
        let type: UInt16
        let `class`: UInt16
    }

    /// Reads the first question section from a DNS query or response.
    static func firstQuestion(in message: Data) -> Question? {
        guard message.count >= 12 else { return nil }

        var offset = 12
        guard let (name, nameEnd) = decodeName(in: message, at: &offset, origin: 12) else {
            return nil
        }
        offset = nameEnd
        guard offset + 4 <= message.count else { return nil }

        let type = message.readUInt16(at: offset)
        let dnsClass = message.readUInt16(at: offset + 2)
        return Question(name: name, type: type, class: dnsClass)
    }

    /// Builds an NXDOMAIN response by mutating the query header in place.
    static func nxDomainResponse(for query: Data) -> Data? {
        guard query.count >= 12 else { return nil }

        var response = query
        let recursionDesired = response[2] & 0x01
        response[2] = 0x80 | recursionDesired // QR = response
        response[3] = 0x83 // RA + RCODE NXDOMAIN

        for index in 6..<12 {
            response[index] = 0
        }
        return response
    }

    /// Collects A/AAAA answer rdata as human-readable strings.
    static func answerStrings(in message: Data) -> [String]? {
        guard message.count >= 12 else { return nil }

        let questionCount = Int(message.readUInt16(at: 4))
        let answerCount = Int(message.readUInt16(at: 6))
        guard questionCount > 0 else { return [] }

        var offset = 12
        for _ in 0..<questionCount {
            guard skipName(in: message, at: &offset, origin: 12) else { return nil }
            guard offset + 4 <= message.count else { return nil }
            offset += 4
        }

        var results: [String] = []
        results.reserveCapacity(answerCount)

        for _ in 0..<answerCount {
            guard skipName(in: message, at: &offset, origin: 12) else { break }
            guard offset + 10 <= message.count else { break }

            let type = message.readUInt16(at: offset)
            let rdLength = Int(message.readUInt16(at: offset + 8))
            offset += 10
            guard offset + rdLength <= message.count else { break }

            switch (type, rdLength) {
            case (1, 4):
                results.append(formatIPv4(message, at: offset))
            case (28, 16):
                results.append(formatIPv6(message, at: offset))
            default:
                break
            }
            offset += rdLength
        }

        return results
    }

    // MARK: - Name decoding

    private static func decodeName(
        in message: Data,
        at offset: inout Int,
        origin: Int
    ) -> (String, Int)? {
        var labels: [String] = []
        var position = offset
        var jumped = false
        var endPosition = offset
        var hops = 0

        while position < message.count {
            hops += 1
            if hops > 128 { return nil }

            let length = Int(message[position])
            if length == 0 {
                position += 1
                if !jumped { endPosition = position }
                offset = endPosition
                return (labels.joined(separator: "."), endPosition)
            }

            if (length & 0xC0) == 0xC0 {
                guard position + 1 < message.count else { return nil }
                let pointer = ((length & 0x3F) << 8) | Int(message[position + 1])
                if !jumped {
                    endPosition = position + 2
                    jumped = true
                }
                position = pointer
                continue
            }

            position += 1
            guard position + length <= message.count else { return nil }
            let label = message.subdata(in: position..<(position + length))
            labels.append(String(data: label, encoding: .utf8) ?? "")
            position += length
        }

        return nil
    }

    private static func skipName(in message: Data, at offset: inout Int, origin: Int) -> Bool {
        var position = offset
        var hops = 0

        while position < message.count {
            hops += 1
            if hops > 128 { return false }

            let length = Int(message[position])
            if length == 0 {
                position += 1
                offset = position
                return true
            }

            if (length & 0xC0) == 0xC0 {
                guard position + 1 < message.count else { return false }
                offset = position + 2
                return true
            }

            position += 1
            guard position + length <= message.count else { return false }
            position += length
        }

        return false
    }

    // MARK: - Rdata formatting

    private static func formatIPv4(_ message: Data, at offset: Int) -> String {
        (0..<4).map { String(message[offset + $0]) }.joined(separator: ".")
    }

    private static func formatIPv6(_ message: Data, at offset: Int) -> String {
        stride(from: 0, to: 16, by: 2).map { index in
            let value = message.readUInt16(at: offset + index)
            return String(format: "%x", value)
        }.joined(separator: ":")
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }
}
