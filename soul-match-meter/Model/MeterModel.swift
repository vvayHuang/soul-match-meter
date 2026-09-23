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

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    let serial: String
    let meta: String
    var state: String
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

/// The instrument's whole state. The peer exchange is real but serverless:
/// each serial carries its owner's answers (see `SerialCodec`), and the
/// report is computed only from the two serials, so both phones agree.
@MainActor
@Observable
final class MeterModel {

    enum Mode: String, Codable { case host, guest }

    // Demo knobs — the prototype exposed these as props.
    let holdSeconds: Double = 5
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
    var sent = false
    /// Set once this exchange has reached the report; a finished exchange
    /// isn't resumed on the next launch.
    var reportShown = false
    /// Empty until this phone has finished a measurement.
    var myCode = ""
    /// The other person's serial, once entered and validated.
    var peerCode: String?

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
    private var scoreTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init() {
        restore()
    }

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

    /// The two serials in a fixed order, so A×B and B×A are the same pair.
    private var pairCodes: [String] {
        [myCode, peerCode ?? ""].sorted()
    }

    /// Everything on the report comes from this — and it only depends on the
    /// two serials, never on which phone is asking.
    var hash: Int {
        SerialCodec.stableHash(pairCodes.joined(separator: "|"))
    }

    /// Both people's answers, read back out of the serials.
    private var pairAnswers: (a: [Int], b: [Int])? {
        guard let a = SerialCodec.decode(pairCodes[0]),
              let b = SerialCodec.decode(pairCodes[1]) else { return nil }
        return (a, b)
    }

    private func sameAnswer(_ question: Int) -> Bool {
        guard let p = pairAnswers else { return false }
        return p.a[question] == p.b[question]
    }

    private var matchCount: Int {
        (0..<SerialCodec.questionCount).filter { sameAnswer($0) }.count
    }

    /// 30…79 from the pair hash, +7 for every identical answer (max 100).
    var score: Int {
        scoreOverride > 0 ? scoreOverride : min(100, 30 + hash % 50 + matchCount * 7)
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

    /// Shown on the receipt, before any peer exists — so it's from my serial only.
    var imageNumber: String { "IMG_0\(372914 + SerialCodec.stableHash(myCode) % 80)" }

    var pairLabel: String {
        pairCodes.map { $0.isEmpty ? "SM-??????" : $0 }.joined(separator: " × ")
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
        // Q1 animal, Q2 battery, Q3 snack. Same answer → the bar looks "right".
        let animal = sameAnswer(0) ? 82 + h % 18 : 18 + h % 50
        let battery = sameAnswer(1) ? h % 12 : 35 + (h * 3) % 60
        let snack = sameAnswer(2) ? 85 + (h * 7) % 15 : 30 + (h * 7) % 50
        return [
            .init(key: "ANIMAL MATCH 動物相容", value: "\(animal)%", amount: Double(animal) / 100),
            .init(key: "NIGHT SNACK 宵夜同步", value: "\(snack)%", amount: Double(snack) / 100),
            .init(key: "BATTERY PANIC 電量焦慮差", value: "\(battery)%", amount: Double(battery) / 100),
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
        shared = false
        toast = ""
        confirming = false

        switch next {
        case .boot: armBoot()
        case .report: runReport()
        default: break
        }
    }

    func onAppear() {
        switch screen {
        case .boot: armBoot()
        case .report: runReport()
        default: break
        }
    }

    func clearAll() {
        bootTask?.cancel()
        holdTask?.cancel()
        statusTask?.cancel()
        scoreTask?.cancel()
        answerTask?.cancel()
    }

    private func armBoot() {
        bootTask?.cancel()
        bootTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.finishBoot()
        }
    }

    /// Leaves the boot screen. A serial that was handed off but never paired
    /// picks up at its receipt, so the host can still enter the reply.
    func finishBoot() {
        go(canResume ? .receipt : .home)
    }

    private var canResume: Bool {
        guard !myCode.isEmpty, sent || copied, !reportShown else { return false }
        return mode == .host || peerCode != nil
    }

    // MARK: Flow entry points

    func startHost() {
        mode = .host
        peerCode = nil
        // A new measurement supersedes whatever was waiting.
        sent = false
        copied = false
        questionIndex = 0
        answers = [nil, nil, nil]
        go(.calibration)
    }

    func startGuest() {
        mode = .guest
        peerCode = nil
        sent = false
        copied = false
        input = ""
        codeError = ""
        go(.serial)
    }

    /// Host, after sending: type in the serial the other person sent back.
    func enterPeerCode() {
        input = ""
        codeError = ""
        go(.serial)
    }

    /// Back from serial entry: a host who already measured returns to the receipt.
    func serialBack() {
        go(mode == .host && !myCode.isEmpty ? .receipt : .home)
    }

    // MARK: Serial entry

    func tapKey(_ label: String) {
        switch label {
        case "DEL":
            input = String(input.dropLast())
            codeError = ""
        case "RND":
            // Easter egg: a valid serial from a random stranger's soul.
            input = String(SerialCodec.random().dropFirst(SerialCodec.prefix.count))
            codeError = ""
        default:
            guard input.count < SerialCodec.length else { return }
            input += label
            codeError = ""
        }
    }

    func submitCode() {
        guard input.count >= SerialCodec.length else {
            codeError = "ERR 07 · 序號不足 \(SerialCodec.length) 碼"
            return
        }
        let code = SerialCodec.prefix + input
        guard SerialCodec.isValid(code) else {
            codeError = "ERR 09 · 校驗失敗，這個靈魂不存在"
            return
        }
        guard code != myCode else {
            codeError = "ERR 11 · 這是你自己的序號"
            return
        }
        peerCode = code

        if mode == .host && !myCode.isEmpty {
            // Host already measured: both serials are in hand.
            markPaired()
            go(.report)
        } else {
            questionIndex = 0
            answers = [nil, nil, nil]
            go(.calibration)
        }
    }

    private func markPaired() {
        if let i = history.firstIndex(where: { $0.serial == myCode }) {
            history[i].state = "已配對"
        }
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
                // The serial is minted only now, so it can carry the answers.
                self.myCode = SerialCodec.make(answers: self.answers.map { $0 ?? 0 })
                // A fresh serial hasn't been handed to anyone yet. (Kept across
                // other navigation so backing out of serial entry keeps the state.)
                self.sent = false
                self.copied = false
                self.reportShown = false
                try? await Task.sleep(for: .milliseconds(520))
                // Both sides get a receipt: the guest has to send theirs back too.
                self.go(.receipt)
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

    // MARK: Peer exchange

    /// What goes into the share sheet. The host invites; the guest sends back.
    var shareMessage: String {
        if mode == .guest {
            return "我也測好了，我的序號是 \(myCode)。在「靈魂配對測量儀」輸入它，就能看我們的配對報告。"
        }
        return "我在「靈魂配對測量儀」測好了，序號 \(myCode)。換你測，測完把你的序號傳回來給我。"
    }

    /// Backup path: the serial alone, for pasting anywhere.
    func copyCode() {
        UIPasteboard.general.string = myCode
        copied = true
        logSnapshot()
        showToast("已複製序號 \(myCode)")
    }

    /// Called when the share sheet actually sent something (not on cancel).
    func markSent() {
        sent = true
        logSnapshot()
        showToast("序號已傳出")
    }

    private func logSnapshot() {
        guard !history.contains(where: { $0.serial == myCode }) else { return }
        history.insert(
            HistoryEntry(
                serial: myCode,
                meta: "PEAK 41.8 °C · ε \(epsLabel)",
                state: peerCode == nil ? "等待回傳" : "已配對"
            ),
            at: 0
        )
    }

    // MARK: Report

    private func runReport() {
        reportShown = true
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
        myCode = ""
        peerCode = nil
        mode = .host
        questionIndex = 0
        answers = [nil, nil, nil]
        input = ""
        confirming = false
        go(.home)
    }

    // MARK: Persistence

    /// The part of the state that survives relaunching the app: the pending
    /// exchange and the log. Answers aren't stored — they're in `myCode`.
    struct Saved: Codable, Equatable {
        var mode: Mode
        var myCode: String
        var peerCode: String?
        var sent: Bool
        var copied: Bool
        var reportShown: Bool
        var history: [HistoryEntry]
    }

    private static let savedKey = "meter.saved.v1"

    var saved: Saved {
        Saved(
            mode: mode,
            myCode: myCode,
            peerCode: peerCode,
            sent: sent,
            copied: copied,
            reportShown: reportShown,
            history: history
        )
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        mode = saved.mode
        myCode = saved.myCode
        peerCode = saved.peerCode
        sent = saved.sent
        copied = saved.copied
        reportShown = saved.reportShown
        history = saved.history
        if let decoded = SerialCodec.decode(myCode) {
            answers = decoded.map { Optional($0) }
        }
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
