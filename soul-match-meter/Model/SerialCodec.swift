import Foundation

/// Serial format: `SM-` + 6 digits = 5 data digits + 1 check digit.
///
/// The data digits carry the three calibration answers (4 × 4 × 4 = 64
/// combinations) plus a random nonce, so the peer can read your answers back
/// out of the serial without any server:
///
///     data = nonce * 64 + answerCode        (0 … 99_967)
///     answerCode = a0 + a1 * 4 + a2 * 16
///
/// The check digit uses weights coprime to 10, so any single mistyped digit
/// is caught.
enum SerialCodec {
    static let prefix = "SM-"
    static let length = 6
    static let optionsPerQuestion = 4
    static let questionCount = 3

    private static let combos = 64
    static let maxNonce = 100_000 / combos - 1 // 1561 → data ≤ 99_967
    private static let weights = [1, 3, 7, 9, 1]

    /// Builds a serial from three answer indices (each 0…3).
    static func make(answers: [Int], nonce: Int = Int.random(in: 0...maxNonce)) -> String {
        let code = answerCode(answers)
        let data = String(format: "%05d", nonce * combos + code)
        return prefix + data + String(checkDigit(data))
    }

    /// A valid serial with random answers — used by the RND key.
    static func random() -> String {
        make(answers: (0..<questionCount).map { _ in Int.random(in: 0..<optionsPerQuestion) })
    }

    /// Accepts "SM-123456" or "123456". Returns nil when the length or the
    /// check digit is wrong.
    static func decode(_ serial: String) -> [Int]? {
        let digits = serial.hasPrefix(prefix) ? String(serial.dropFirst(prefix.count)) : serial
        guard digits.count == length, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else {
            return nil
        }
        let data = String(digits.prefix(length - 1))
        guard let check = Int(String(digits.last!)), check == checkDigit(data),
              let value = Int(data) else { return nil }
        var code = value % combos
        return (0..<questionCount).map { _ in
            defer { code /= optionsPerQuestion }
            return code % optionsPerQuestion
        }
    }

    static func isValid(_ serial: String) -> Bool { decode(serial) != nil }

    private static func answerCode(_ answers: [Int]) -> Int {
        var code = 0
        var place = 1
        for i in 0..<questionCount {
            let a = i < answers.count ? answers[i] : 0
            code += max(0, min(optionsPerQuestion - 1, a)) * place
            place *= optionsPerQuestion
        }
        return code
    }

    private static func checkDigit(_ data: String) -> Int {
        let sum = zip(data, weights).reduce(0) { acc, pair in
            acc + (Int(String(pair.0)) ?? 0) * pair.1
        }
        return (10 - sum % 10) % 10
    }

    /// Stable string hash (Swift's `hashValue` changes every launch, so it
    /// can't be used for results two phones must agree on).
    static func stableHash(_ s: String) -> Int {
        var h = 7
        for scalar in s.unicodeScalars {
            h = (h &* 31 &+ Int(scalar.value)) % 9973
        }
        return h
    }
}
