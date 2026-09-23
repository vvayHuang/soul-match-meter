import Foundation
import Observation
import SwiftUI

// MARK: - Screens

enum Screen: Int, CaseIterable, Identifiable {
    case boot = 0
    case home
    case serial
    case calibration
    case hold
    case receipt
    case report
    case settings
    case history

    var id: Int { rawValue }

    var no: String { String(format: "%02d", rawValue) }

    var label: String {
        switch self {
        case .boot: "開機動畫"
        case .home: "待機觀景窗"
        case .serial: "輸入對方序號"
        case .calibration: "校正問題 ×3"
        case .hold: "按住測量 5 秒"
        case .receipt: "快照收據"
        case .report: "配對報告"
        case .settings: "設定（全是假的）"
        case .history: "歷史紀錄／空狀態"
        }
    }

    var tag: String {
        switch self {
        case .boot: "BOOT"
        case .home: "HOME"
        case .serial: "SERIAL"
        case .calibration: "CALIB"
        case .hold: "HOLD"
        case .receipt: "RECEIPT"
        case .report: "REPORT"
        case .settings: "SETUP"
        case .history: "LOG"
        }
    }
}

// MARK: - Content

struct CalibrationQuestion {
    let text: String
    let options: [String]
    let temps: [String]
}

struct ResultTier {
    let min: Int
    let title: String
    let subtitle: String
}

struct HistoryEntry: Identifiable {
    let id = UUID()
    let serial: String
    let meta: String
    let state: String
}

struct ReceiptRow: Identifiable {
    var id: String { key }
    let key: String
    let value: String
}

struct Metric: Identifiable {
    var id: String { key }
    let key: String
    let value: String
    let amount: Double
}

// MARK: - Model

/// The instrument's whole state. The peer exchange is faked: a serial is
/// generated locally, "sending" it starts a timer, and the peer always answers.
@MainActor
@Observable
final class MeterModel {

    enum Mode { case host, guest }

    // Demo knobs — the prototype exposed these as props.
    let holdSeconds: Double = 5
    let friendDelaySeconds: Double = 4
    /// 0 means "derive the score from the answers".
    let scoreOverride: Int = 0

    // Navigation
    var screen: Screen = .boot
    var mode: Mode = .host

    // Serial entry
    var input = ""
    var codeError = ""

    // Calibration
    var questionIndex = 0
    var answers: [Int?] = [nil, nil, nil]

    // Hold
    var holding = false
    var holdPct: Double = 0
    var statusIndex = 0
    var dropped = false
    /// Bumped on every hold tick; drives the continuous buzz while pressing.
    var buzzTick = 0
    /// Bumped each time the gauge nearly peaks and then slips back down.
    var slipTick = 0

    // Receipt / peer
    var copied = false
    var shared = false
    var waiting = false
    var friendArrived = false
    var myCode = MeterModel.newSerial()

    // Report
    var barsOn = false
    var scoreAnim: Int?

    // Settings
    var unit = "°C"
    var eps = 0.80
    var scanlines = true

    // Log
    var history: [HistoryEntry] = []

    // Chrome
    var toast = ""
    var confirming = false

    // Timing runs on main-actor tasks rather than Timers: the model is
    // @MainActor, so there is nothing to hop and nothing to make Sendable.
    private var bootTask: Task<Void, Never>?
    private var holdTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var friendTask: Task<Void, Never>?
    private var scoreTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    // MARK: Static content

    let questions: [CalibrationQuestion] = [
        .init(
            text: "你現在最像哪種動物？",
            options: ["烏龜", "貓", "恐龍", "企鵝"],
            temps: ["24.1 °C", "31.7 °C", "38.2 °C", "21.4 °C"]
        ),
        .init(
            text: "手機剩 1% 電，你會？",
            options: ["直接關機裝死", "先傳「我電要沒了」", "邊充邊講兩小時", "問陌生人借線"],
            temps: ["22.8 °C", "29.4 °C", "40.1 °C", "35.6 °C"]
        ),
        .init(
            text: "半夜肚子餓，你是？",
            options: ["鹹酥雞", "泡麵加蛋", "冰箱裡的剩菜", "忍住然後失眠"],
            temps: ["41.2 °C", "33.5 °C", "26.9 °C", "23.3 °C"]
        ),
    ]

    let statusLines = [
        "掃描前世熱源…",
        "比對你阿嬤的八字…",
        "正在詢問隔壁的貓…",
        "校正尷尬指數…",
        "偷看對方的歌單…",
    ]

    let resultTiers: [ResultTier] = [
        .init(min: 90, title: "同一顆腦袋", subtitle: "分裝成兩包。很可怕，但很配。"),
        .init(min: 70, title: "鹹酥雞搭檔", subtitle: "一個負責點，一個負責吃。本機建議維持現狀。"),
        .init(min: 50, title: "室友級靈魂", subtitle: "可以共用冰箱，不建議共用秘密。"),
        .init(min: 0, title: "不同頻道的兩台電視", subtitle: "建議繼續當朋友，並互相靜音。"),
    ]

    // MARK: Derived values

    static func newSerial() -> String {
        "SM-" + (0..<5).map { _ in String(Int.random(in: 0...9)) }.joined()
    }

    /// The prototype's deterministic pseudo-hash. Everything downstream of the
    /// reading — the score, the ΔT, the metrics, the image number — comes from it.
    var hash: Int {
        let s = myCode + input + answers.map { $0.map(String.init) ?? "" }.joined()
        var h = 7
        for scalar in s.unicodeScalars {
            h = (h &* 31 &+ Int(scalar.value)) % 9973
        }
        return h
    }

    var score: Int {
        scoreOverride > 0 ? scoreOverride : 38 + (hash % 61)
    }

    var resultTier: ResultTier {
        resultTiers.first { score >= $0.min } ?? resultTiers[resultTiers.count - 1]
    }

    var currentQuestion: CalibrationQuestion {
        questions[min(questionIndex, questions.count - 1)]
    }

    var answeredCount: Int { answers.compactMap { $0 }.count }

    /// 0…1 of the way from the 23.6 °C floor to the 41.8 °C white-hot peak.
    var holdFraction: Double { holdPct / 100 }

    var liveTemperature: Double { 23.6 + gaugeFraction * 18.2 }

    /// Hold progress mapped onto (time, gauge) keyframes. The gauge teases:
    /// it almost tops out, slips back, climbs again, and only locks at the end.
    private static let teaseKeys: [(t: Double, v: Double)] = [
        (0.00, 0.00),
        (0.28, 0.95),
        (0.40, 0.35),
        (0.60, 0.97),
        (0.70, 0.45),
        (0.88, 0.99),
        (0.93, 0.62),
        (1.00, 1.00),
    ]

    /// Times at which the gauge turns from rising to falling.
    private static let teasePeaks: [Double] = [0.28, 0.60, 0.88]

    /// 0…1 cursor position for the palette scale. Unlike `holdFraction`
    /// (honest elapsed time), this one is theatrical.
    var gaugeFraction: Double {
        let t = holdFraction
        let keys = Self.teaseKeys
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        for i in 1..<keys.count where t <= keys[i].t {
            let a = keys[i - 1], b = keys[i]
            let u = (t - a.t) / (b.t - a.t)
            let eased = u * u * (3 - 2 * u)
            return a.v + (b.v - a.v) * eased
        }
        return 1
    }

    var epsLabel: String { String(format: "%.2f", eps) }

    var imageNumber: String { "IMG_0\(372914 + hash % 80)" }

    var pairLabel: String {
        let peer = input.isEmpty ? String(40871 + hash % 90) : input
        return "\(myCode) × SM-\(peer)"
    }

    var deltaLabel: String {
        String(format: "PERCENT · ΔT %.1f °C", 1 + Double(hash % 70) / 10)
    }

    var receiptRows: [ReceiptRow] {
        [
            .init(key: "HOLD TIME", value: String(format: "%.1fs", holdSeconds)),
            .init(key: "PEAK TEMP", value: "41.8 °C"),
            .init(key: "EMISSIVITY", value: "0.80"),
            .init(key: "ANSWERS", value: answers.enumerated()
                .map { index, answer in
                    guard let answer else { return "—" }
                    return String(questions[index].options[answer].prefix(2))
                }
                .joined(separator: " / ")),
            .init(key: "VALID FOR", value: "24H"),
        ]
    }

    var metrics: [Metric] {
        let h = hash
        return [
            .init(key: "ANIMAL MATCH 動物相容", value: "\(40 + h % 60)%", amount: Double(40 + h % 60) / 100),
            .init(key: "NIGHT SNACK 宵夜同步", value: "\(55 + (h * 7) % 45)%", amount: Double(55 + (h * 7) % 45) / 100),
            .init(key: "BATTERY PANIC 電量焦慮差", value: "\(h % 38)%", amount: Double(h % 38) / 100),
        ]
    }

    var statusText: String {
        if holding { return statusLines[statusIndex % statusLines.count] }
        if holdPct >= 100 { return "量到了，別亂動。" }
        return "待機中。手指呢？"
    }

    var hasStatus: Bool { holding || holdPct >= 100 || dropped }

    var spotColor: Color {
        let g = gaugeFraction * 100
        if g > 80 { return IR.thermal70 }
        if g > 55 { return IR.thermal50 }
        if g > 30 { return IR.thermal30 }
        return IR.thermal20
    }

    // MARK: Navigation

    func go(_ next: Screen) {
        clearAll()
        toastTask?.cancel()
        screen = next
        holding = false
        holdPct = 0
        dropped = false
        waiting = next == .receipt
        friendArrived = false
        copied = false
        shared = false
        toast = ""
        confirming = false

        switch next {
        case .boot: armBoot()
        case .receipt: armFriend()
        case .report: runReport()
        default: break
        }
    }

    func onAppear() {
        switch screen {
        case .boot: armBoot()
        case .receipt: armFriend()
        case .report: runReport()
        default: break
        }
    }

    func clearAll() {
        bootTask?.cancel()
        holdTask?.cancel()
        statusTask?.cancel()
        friendTask?.cancel()
        scoreTask?.cancel()
        answerTask?.cancel()
    }

    private func armBoot() {
        bootTask?.cancel()
        bootTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.go(.home)
        }
    }

    // MARK: Flow entry points

    func startHost() {
        mode = .host
        questionIndex = 0
        answers = [nil, nil, nil]
        go(.calibration)
    }

    func startGuest() {
        mode = .guest
        input = ""
        codeError = ""
        go(.serial)
    }

    // MARK: Serial entry

    func tapKey(_ label: String) {
        switch label {
        case "DEL":
            input = String(input.dropLast())
            codeError = ""
        case "RND":
            input = String(Int.random(in: 10000...99998))
            codeError = ""
        default:
            guard input.count < 5 else { return }
            input += label
            codeError = ""
        }
    }

    func submitCode() {
        guard input.count >= 5 else {
            codeError = "ERR 07 · 序號不足 5 碼"
            return
        }
        guard "SM-" + input != myCode else {
            codeError = "ERR 11 · 這是你自己的序號"
            return
        }
        questionIndex = 0
        answers = [nil, nil, nil]
        go(.calibration)
    }

    // MARK: Calibration

    func pick(option index: Int) {
        answers[questionIndex] = index
        let wasLast = questionIndex >= questions.count - 1
        answerTask?.cancel()
        answerTask = Task { [weak self] in
            // Long enough for the selected row to read as selected before moving on.
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled, let self else { return }
            if wasLast {
                self.go(.hold)
            } else {
                self.questionIndex += 1
            }
        }
    }

    // MARK: Hold

    func startHold() {
        guard holdPct < 100 else { return }
        holding = true
        dropped = false
        holdTask?.cancel()
        statusTask?.cancel()

        holdTask = Task { [weak self] in
            // 50ms ticks, matching the instrument's reading cadence.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                let next = min(100, self.holdPct + 100 / (self.holdSeconds * 20))
                guard next >= 100 else {
                    let crossedPeak = Self.teasePeaks.contains {
                        self.holdPct / 100 < $0 && next / 100 >= $0
                    }
                    self.holdPct = next
                    self.buzzTick += 1
                    if crossedPeak { self.slipTick += 1 }
                    continue
                }
                self.clearAll()
                self.holdPct = 100
                self.holding = false
                let destination: Screen = self.mode == .host ? .receipt : .report
                try? await Task.sleep(for: .milliseconds(520))
                self.go(destination)
                return
            }
        }

        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled, let self else { return }
                self.statusIndex += 1
            }
        }
    }

    func endHold() {
        guard holdPct < 100, holding else { return }
        holdTask?.cancel()
        statusTask?.cancel()
        holding = false
        holdPct = 0
        dropped = true
    }

    // MARK: Peer exchange (faked)

    private func armFriend() {
        friendTask?.cancel()
        let delay = friendDelaySeconds
        friendTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.waiting = false
            self.friendArrived = true
        }
    }

    func copyCode() {
        UIPasteboard.general.string = myCode
        copied = true
        showToast("已複製序號 \(myCode)")
    }

    func sendCode() {
        let entry = HistoryEntry(
            serial: myCode,
            meta: "PEAK 41.8 °C · ε \(epsLabel)",
            state: "等待回傳"
        )
        waiting = true
        friendArrived = false
        if !history.contains(where: { $0.serial == myCode }) {
            history.insert(entry, at: 0)
        }
        clearAll()
        armFriend()
        showToast("序號已傳出")
    }

    // MARK: Report

    private func runReport() {
        let target = score
        barsOn = false
        scoreAnim = 0

        scoreTask?.cancel()
        scoreTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.85).delay(0.12)) {
                self.barsOn = true
            }

            // Count the percentage up over ~26 frames, eased out.
            var t = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(34))
                guard !Task.isCancelled else { return }
                t += 1.0 / 26
                guard t < 1 else {
                    self.scoreAnim = nil
                    return
                }
                let eased = 1 - pow(1 - t, 3)
                self.scoreAnim = Int((Double(target) * eased).rounded())
            }
        }
    }

    func again() {
        myCode = MeterModel.newSerial()
        questionIndex = 0
        answers = [nil, nil, nil]
        input = ""
        confirming = false
        go(.home)
    }

    // MARK: Settings

    func stepEmissivity(_ delta: Double) {
        eps = ((eps + delta) * 100).rounded() / 100
        eps = min(1, max(0.1, eps))
    }

    func factoryReset() {
        unit = "°C"
        eps = 0.80
        scanlines = true
        showToast("已回復原廠設定")
    }

    func clearHistory() {
        history.removeAll()
        showToast("紀錄已清空")
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(IR.uiCurve) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled, let self else { return }
            withAnimation(IR.uiCurve) { self.toast = "" }
        }
    }
}
