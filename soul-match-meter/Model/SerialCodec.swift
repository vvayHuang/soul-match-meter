import Foundation

/// Serial format: `SM-` + 6 digits = 5 data digits + 1 check digit.
///
/// The data digits carry which three questions were drawn from the bank
/// (10 choose 3 = 120 sets), the three answers (4 × 4 × 4 = 64 combinations)
/// and a random nonce, so the peer can read your questions and answers back
/// out of the serial without any server:
///
///     data = nonce * 7680 + setIndex * 64 + answerCode   (0 … 99_839)
///     answerCode = a0 + a1 * 4 + a2 * 16
///
/// The check digit uses weights coprime to 10, so any single mistyped digit
/// is caught.
enum SerialCodec {
    static let prefix = "SM-"
    static let length = 6
    static let optionsPerQuestion = 4
    static let questionCount = 3
    static let bankSize = 10

    /// What a serial carries.
    struct Reading: Equatable {
        /// Indices into the question bank, ascending.
        let questions: [Int]
        let answers: [Int]
        let nonce: Int
    }

    /// Every 3-question draw from the bank, in lexicographic order.
    private static let sets: [[Int]] = {
        var result: [[Int]] = []
        for a in 0..<bankSize {
            for b in (a + 1)..<bankSize {
                for c in (b + 1)..<bankSize {
                    result.append([a, b, c])
                }
            }
        }
        return result
    }()

    private static let answerCombos = 64
    private static var combos: Int { sets.count * answerCombos } // 7680
    static var maxNonce: Int { 100_000 / combos - 1 } // 12 → data ≤ 99_839
    private static let weights = [1, 3, 7, 9, 1]

    /// A fresh random draw of three questions.
    static func randomQuestions() -> [Int] {
        sets.randomElement() ?? [0, 1, 2]
    }

    /// Builds a serial from a question draw and three answer indices (each
    /// 0…3). Pass the peer's serial as `avoiding` so the two can never come
    /// out identical, even with identical answers.
    static func make(questions: [Int], answers: [Int], avoiding peer: String? = nil) -> String {
        let taken = peer.flatMap { decode($0) }?.nonce
        let nonce = (0...maxNonce).filter { $0 != taken }.randomElement() ?? 0
        let setIndex = sets.firstIndex(of: questions.sorted()) ?? 0
        let value = nonce * combos + setIndex * answerCombos + answerCode(answers)
        let data = String(format: "%05d", value)
        return prefix + data + String(checkDigit(data))
    }

    /// A valid serial with a random draw and random answers — used by the RND key.
    static func random() -> String {
        make(
            questions: randomQuestions(),
            answers: (0..<questionCount).map { _ in Int.random(in: 0..<optionsPerQuestion) }
        )
    }

    /// Accepts "SM-123456" or "123456". Returns nil when the length or the
    /// check digit is wrong, or the data is out of range.
    static func decode(_ serial: String) -> Reading? {
        let digits = serial.hasPrefix(prefix) ? String(serial.dropFirst(prefix.count)) : serial
        guard digits.count == length, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else {
            return nil
        }
        let data = String(digits.prefix(length - 1))
        guard let check = Int(String(digits.last!)), check == checkDigit(data),
              let value = Int(data), value < (maxNonce + 1) * combos else { return nil }
        var code = value % answerCombos
        let answers = (0..<questionCount).map { _ in
            defer { code /= optionsPerQuestion }
            return code % optionsPerQuestion
        }
        return Reading(
            questions: sets[(value % combos) / answerCombos],
            answers: answers,
            nonce: value / combos
        )
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
