import SwiftUI

struct ContentView: View {
    @State private var model = MeterModel()
    #if DEBUG
    @State private var showingIndex = false
    #endif

    var body: some View {
        screens
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        #if DEBUG
        .overlay(alignment: .bottomTrailing) { indexButton }
        #endif
        .animation(.easeOut(duration: 0.26), value: model.screen)
        .preferredColorScheme(.dark)
        .onAppear { model.onAppear() }
        .onChange(of: model.saved) { model.persist() }
        #if DEBUG
        .sheet(isPresented: $showingIndex) {
            ScreenIndexSheet(model: model, isPresented: $showingIndex)
        }
        #endif
    }

    private var screens: some View {
        Group {
            switch model.screen {
            case .boot: BootScreen(model: model)
            case .home: HomeScreen(model: model)
            case .serial: SerialEntryScreen(model: model)
            case .calibration: CalibrationScreen(model: model)
            case .hold: HoldScreen(model: model)
            case .receipt: ReceiptScreen(model: model)
            case .report: ReportScreen(model: model)
            case .settings: SettingsScreen(model: model)
            case .history: HistoryScreen(model: model)
            }
        }
        .id(model.screen)
        .transition(.opacity)
    }

    #if DEBUG
    /// Sits in the home-indicator band, clear of every screen's content.
    private var indexButton: some View {
        Button { showingIndex = true } label: {
            Text("INDEX")
                .font(IR.mono(9, .semibold))
                .tracking(1)
                .foregroundStyle(IR.onPlateMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(IR.plateSolid.opacity(0.6))
                .overlay { Rectangle().stroke(IR.outlineQuiet, lineWidth: 1) }
        }
        .padding(.trailing, 8)
        .offset(y: 26) // into the home-indicator band, clear of every screen
    }
    #endif
}

#if DEBUG
/// Development-only jump list, mirroring the prototype's SCREEN INDEX rail.
private struct ScreenIndexSheet: View {
    let model: MeterModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCREEN INDEX · 9 頁")
                .font(IR.mono(10.5, .semibold))
                .tracking(1.5)
                .foregroundStyle(IR.primary)

            VStack(spacing: 6) {
                ForEach(Screen.allCases) { screen in
                    let on = model.screen == screen
                    Button {
                        model.go(screen)
                        isPresented = false
                    } label: {
                        HStack(spacing: 10) {
                            Text(screen.no)
                                .font(IR.mono(11.5))
                                .foregroundStyle(on ? IR.primaryInk.opacity(0.7) : Color(hex: 0x9AA3B2))
                            Text(screen.label)
                                .font(IR.cjk(13.5, .bold))
                                .foregroundStyle(on ? IR.onInverse : Color(hex: 0xE8EAEF))
                            Spacer(minLength: 8)
                            Text(screen.tag)
                                .font(IR.mono(10.5))
                                .foregroundStyle(on ? IR.primaryInk.opacity(0.7) : Color(hex: 0x9AA3B2))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .background(on ? IR.primary : Color(hex: 0x0E1116))
                        .overlay { Rectangle().stroke(on ? IR.primary : IR.outlineQuiet, lineWidth: 1) }
                        .contentShape(Rectangle())
                    }
                    .hudPress()
                }
            }

            Text("完整流程：A 01 → 03 → 04 → 05 傳序號 → 02 輸入 B 的序號 → 06；B 02 輸入 A 的序號 → 03 → 04 → 05 傳回序號 → 06。直接跳 06 沒有對方序號，結果不準。")
                .font(IR.cjk(12))
                .lineSpacing(5)
                .foregroundStyle(Color(hex: 0x9AA3B2))

            Spacer(minLength: 0)
        }
        .padding(16)
        .padding(.top, 14) // clear of the sheet grabber
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: 0x14181F).ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}
#endif

#Preview("01 · HOME") {
    ContentView()
}
