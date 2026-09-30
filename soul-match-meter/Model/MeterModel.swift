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
    /// A finished report reopened from the log.
    case historyReport

    var id: Int { rawValue }

    var no: String { self == .historyReport ? "08c" : String(format: "%02d", rawValue) }

    var label: String {
        switch self {
        case .boot: "開機動畫"
        case .home: "待機觀景窗"
        case .serial: "輸入對方序號"
        case .calibration: "校正問題 ×3"
        case .hold: "按住測量"
        case .receipt: "快照收據"
        case .report: "配對報告"
        case .settings: "設定（全是假的）"
        case .history: "歷史紀錄／空狀態"
        case .historyReport: "紀錄 · 配對報告"
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
        case .history, .historyReport: "LOG"
        }
    }
}

// MARK: - Content

struct CalibrationQuestion {
    let text: String
    let options: [String]
    /// The report metric this question feeds.
    let metric: String
    /// For "difference" metrics a matching answer reads low, not high.
    var lowerIsBetter = false
}

struct ResultTier {
    let min: Int
    let title: String
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    let serial: String
    let meta: String
    var state: String
    /// The finished report, kept as shown so reopening it never drifts. Nil
    /// while waiting for the peer (and on entries saved before reports were kept).
    var report: MatchReport? = nil
}

/// Everything a report screen shows, frozen.
struct MatchReport: Codable, Equatable {
    let pair: String
    let score: Int
    let title: String
    let metrics: [Metric]
}

struct ReceiptRow: Identifiable {
    var id: String { key }
    let key: String
    let value: String
}

struct Metric: Identifiable, Codable, Equatable {
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

    // Demo knob — the prototype exposed this as a prop.
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
    /// Which three bank questions this exchange uses. The host draws them;
    /// the guest reads them out of the host's serial.
    var questionSet: [Int] = [0, 1, 2]

    // Hold
    var holding = false
    var holdPct: Double = 0
    var dropped = false
    /// Bumped on every hold tick; drives the continuous buzz while pressing.
    var buzzTick = 0

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
    /// The log entry's report shown on 08c.
    var viewing: MatchReport?

    // Settings — none of these change a result.
    var palette: ThermalPalette = .iron {
        didSet { ThermalCamera.shared.setPalette(palette) }
    }
    var holdSeconds: Double = 5
    var shutter = true

    // Log
    var history: [HistoryEntry] = []

    // Chrome
    var toast = ""
    var confirming = false

    // Timing runs on main-actor tasks rather than Timers: the model is
    // @MainActor, so there is nothing to hop and nothing to make Sendable.
    private var bootTask: Task<Void, Never>?
    private var holdTask: Task<Void, Never>?
    private var scoreTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init() {
        restore()
    }

    // MARK: Static content

    let questionBank: [CalibrationQuestion] = [
        .init(
            text: "你現在最像哪種動物？",
            options: ["烏龜", "貓", "恐龍", "企鵝"],
            metric: "動物相容"
        ),
        .init(
            text: "手機剩 1% 電，你會？",
            options: ["直接關機裝死", "先傳「我電要沒了」", "邊充邊講兩小時", "問陌生人借線"],
            metric: "電量焦慮差",
            lowerIsBetter: true
        ),
        .init(
            text: "半夜肚子餓，你是？",
            options: ["鹹酥雞", "泡麵加蛋", "冰箱裡的剩菜", "忍住然後失眠"],
            metric: "宵夜同步"
        ),
        .init(
            text: "收到一句「在嗎？」，你會？",
            options: ["秒回「在」", "三小時後再回", "已讀然後忘記", "回「不在」"],
            metric: "回覆同步"
        ),
        .init(
            text: "週末的理想起床時間？",
            options: ["鬧鐘響之前", "早上十點", "中午以後", "週末沒有早上"],
            metric: "作息時差",
            lowerIsBetter: true
        ),
        .init(
            text: "出門前的最後一件事？",
            options: ["檢查瓦斯", "找鑰匙", "照鏡子", "回去拿忘記的東西"],
            metric: "出門延遲差",
            lowerIsBetter: true
        ),
        .init(
            text: "打開外送 App 之後，你會？",
            options: ["點上次那家", "滑二十分鐘再關掉", "專看評價最低的", "讓對方決定"],
            metric: "選擇障礙同步"
        ),
        .init(
            text: "你的手機桌布是？",
            options: ["預設桌布", "寵物", "某個風景", "一整片黑"],
            metric: "桌布相容"
        ),
        .init(
            text: "突然下雨又沒帶傘，你會？",
            options: ["直接衝", "等雨停", "買一把新的", "假裝很享受"],
            metric: "淋雨協議"
        ),
        .init(
            text: "朋友唱歌走音，你會？",
            options: ["跟著一起走音", "默默把伴唱調大", "鼓掌最大聲", "偷偷切下一首"],
            metric: "社交噪音差",
            lowerIsBetter: true
        ),
    ]

    /// The three questions in play, in serial order.
    var questions: [CalibrationQuestion] {
        questionSet.map { questionBank[$0] }
    }

    let resultTiers: [ResultTier] = [
        .init(min: 95, title: "同一顆腦袋"),
        .init(min: 90, title: "出廠設定一樣"),
        .init(min: 84, title: "共用一條充電線"),
        .init(min: 78, title: "鹹酥雞搭檔"),
        .init(min: 72, title: "同一個 Wi-Fi 的兩台裝置"),
        .init(min: 66, title: "會互相按讚的鄰居"),
        .init(min: 60, title: "室友級靈魂"),
        .init(min: 54, title: "排隊剛好站前後"),
        .init(min: 48, title: "同一台電梯的陌生人"),
        .init(min: 42, title: "時差六小時"),
        .init(min: 36, title: "兩隻不同品種的貓"),
        .init(min: 0, title: "不同頻道的兩台電視"),
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

    /// Both people's answers, read back out of the serials. Only comparable
    /// when both answered the same draw.
    private var pairAnswers: (a: [Int], b: [Int])? {
        guard let a = SerialCodec.decode(pairCodes[0]),
              let b = SerialCodec.decode(pairCodes[1]),
              a.questions == b.questions else { return nil }
        return (a.answers, b.answers)
    }

    private func sameAnswer(_ slot: Int) -> Bool {
        guard let p = pairAnswers else { return false }
        return p.a[slot] == p.b[slot]
    }

    private var matchCount: Int {
        (0..<SerialCodec.questionCount).filter { sameAnswer($0) }.count
    }

    /// Score bands by identical answers (0…3). Neighbouring bands overlap so
    /// the tier isn't fixed by the count, but three matches always read high.
    private static let scoreBands: [ClosedRange<Int>] = [30...59, 45...74, 60...89, 85...100]

    /// A point inside the match-count band, picked by the pair hash.
    var score: Int {
        guard scoreOverride == 0 else { return scoreOverride }
        let band = Self.scoreBands[min(matchCount, Self.scoreBands.count - 1)]
        return band.lowerBound + hash % band.count
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

    var liveTemperature: Double { 23.6 + holdFraction * 18.2 }

    /// Shown on the receipt, before any peer exists — so it's from my serial only.
    var imageNumber: String { "IMG_0\(372914 + SerialCodec.stableHash(myCode) % 80)" }

    var pairLabel: String {
        pairCodes.map { $0.isEmpty ? "SM-??????" : $0 }.joined(separator: " × ")
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

    /// One bar per question in the draw. Same answer → the bar looks "right":
    /// high for a match metric, low for a difference metric.
    var metrics: [Metric] {
        let h = hash
        let spread = [1, 3, 7]
        return questions.enumerated().map { slot, question in
            let v = h * spread[slot % spread.count]
            let value = question.lowerIsBetter
                ? (sameAnswer(slot) ? v % 12 : 35 + v % 60)
                : (sameAnswer(slot) ? 82 + v % 18 : 18 + v % 50)
            return Metric(key: question.metric, value: "\(value)%", amount: Double(value) / 100)
        }
    }

    /// This exchange's report, as the report screen shows it.
    var liveReport: MatchReport {
        MatchReport(pair: pairLabel, score: score, title: resultTier.title, metrics: metrics)
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
        case .historyReport: runCountUp(to: (viewing ?? liveReport).score)
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
        scoreTask?.cancel()
        answerTask?.cancel()
    }

    /// The boot sequence runs 2.4 s; with reduced motion it holds its last
    /// frame and leaves at 1.6 s.
    func armBoot(after seconds: Double = 2.4) {
        bootTask?.cancel()
        bootTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finishBoot()
        }
    }

    /// Leaves the boot screen. A finished measurement that was never paired
    /// picks up at its receipt, whether or not it was handed off yet, so the
    /// serial can still be sent and the host can still enter the reply.
    func finishBoot() {
        go(canResume ? .receipt : .home)
    }

    private var canResume: Bool {
        guard !myCode.isEmpty, !reportShown else { return false }
        return mode == .host || peerCode != nil
    }

    // MARK: Flow entry points

    func startHost() {
        mode = .host
        peerCode = nil
        questionSet = SerialCodec.randomQuestions()
        // A new measurement supersedes whatever was waiting.
        myCode = ""
        sent = false
        copied = false
        questionIndex = 0
        answers = [nil, nil, nil]
        go(.calibration)
    }

    func startGuest() {
        mode = .guest
        peerCode = nil
        myCode = ""
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
        guard let reading = SerialCodec.decode(code) else {
            codeError = "ERR 09 · 校驗失敗，這個靈魂不存在"
            return
        }
        guard code != myCode else {
            codeError = "ERR 11 · 這是你自己的序號"
            return
        }

        if mode == .host && !myCode.isEmpty {
            // Host already measured: the reply must answer the same draw.
            guard reading.questions == questionSet else {
                codeError = "ERR 13 · 題目對不上，這不是回給你的序號"
                return
            }
            peerCode = code
            go(.report)
        } else {
            // Guest: answer whatever the host drew.
            peerCode = code
            questionSet = reading.questions
            questionIndex = 0
            answers = [nil, nil, nil]
            go(.calibration)
        }
    }

    // MARK: Calibration

    func pick(option index: Int) {
        // One answer per question; a second tap while the first settles is ignored.
        guard answers[questionIndex] == nil else { return }
        answers[questionIndex] = index
        let wasLast = questionIndex >= questions.count - 1
        answerTask?.cancel()
        answerTask = Task { [weak self] in
            // Long enough for the selected row to read as selected before moving on.
            try? await Task.sleep(for: .seconds(IR.durAdvance))
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

        holdTask = Task { [weak self] in
            // 50ms ticks, matching the instrument's reading cadence.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                let next = min(100, self.holdPct + 100 / (self.holdSeconds * 20))
                guard next >= 100 else {
                    self.holdPct = next
                    self.buzzTick += 1
                    continue
                }
                self.holdPct = 100
                if self.shutter { ShutterSound.play() }
                self.holding = false
                // The serial is minted only now, so it can carry the answers.
                self.myCode = SerialCodec.make(
                    questions: self.questionSet,
                    answers: self.answers.map { $0 ?? 0 },
                    avoiding: self.peerCode
                )
                // A fresh serial hasn't been handed to anyone yet. (Kept across
                // other navigation so backing out of serial entry keeps the state.)
                self.sent = false
                self.copied = false
                self.reportShown = false
                // Hold the locked reading on screen before moving on.
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled else { return }
                // Both sides get a receipt: the guest has to send theirs back too.
                self.go(.receipt)
                return
            }
        }
    }

    func endHold() {
        guard holdPct < 100, holding else { return }
        holdTask?.cancel()
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

    private static let snapshotMeta = "PEAK 41.8 °C · ε 0.80"

    /// Logs this measurement the first time it leaves the phone. The guest
    /// already holds both serials, so theirs goes in finished.
    private func logSnapshot() {
        guard peerCode == nil else { return recordReport() }
        guard !history.contains(where: { $0.serial == myCode }) else { return }
        history.insert(HistoryEntry(serial: myCode, meta: Self.snapshotMeta, state: "等待回傳"), at: 0)
    }

    /// Files the finished pair at the top of the log, replacing the row that
    /// was waiting on it.
    private func recordReport() {
        let report = liveReport
        history.removeAll { $0.serial == myCode || $0.serial == report.pair }
        history.insert(
            HistoryEntry(serial: report.pair, meta: Self.snapshotMeta, state: "\(report.score) %", report: report),
            at: 0
        )
    }

    /// 08c: reopen a finished report from the log.
    func open(_ entry: HistoryEntry) {
        guard let report = entry.report else { return }
        viewing = report
        go(.historyReport)
    }

    // MARK: Report

    private func runReport() {
        reportShown = true
        recordReport()
        runCountUp(to: score)
    }

    private func runCountUp(to target: Int) {
        barsOn = false
        scoreAnim = 0

        scoreTask?.cancel()
        scoreTask = Task { [weak self] in
            guard let self else { return }
            // Count the percentage up over ~26 frames, eased out; the bars
            // start filling 90ms in.
            var t = 0.0
            var elapsed = 0
            while !Task.isCancelled {
                if elapsed >= 90, !self.barsOn {
                    withAnimation(IR.hud(IR.durLock)) { self.barsOn = true }
                }
                elapsed += 34
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
    /// exchange and the log. Questions and answers aren't stored — they're in `myCode`.
    struct Saved: Codable, Equatable {
        var mode: Mode
        var myCode: String
        var peerCode: String?
        var sent: Bool
        var copied: Bool
        var reportShown: Bool
        var history: [HistoryEntry]
    }

    /// v2: serials also carry the question draw; v1 serials don't decode.
    private static let savedKey = "meter.saved.v2"

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
        if let reading = SerialCodec.decode(myCode) {
            questionSet = reading.questions
            answers = reading.answers.map { Optional($0) }
        }
    }

    // MARK: Settings

    /// Turning the shutter on plays it once, so you know what you turned on.
    func setShutter(_ on: Bool) {
        shutter = on
        if on { ShutterSound.play() }
    }

    func factoryReset() {
        palette = .iron
        holdSeconds = 5
        shutter = true
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
