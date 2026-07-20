import SwiftUI
import UIKit

@main
struct WayinkSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// 主畫面的設計目標是「回來看一眼就知道結果」。
/// 撈記錄檔是備援手段，不該是判讀的必要條件——走完一小時回到家還得先接電腦
/// 才知道測到什麼，會讓每一次重測的成本高到不想重測。
struct ContentView: View {

    @StateObject private var logger = LocationLogger()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Wayink 定位 Spike")
                    .font(.title2)
                    .bold()

                backgroundModeCard
                statusCard
                controlCard
                fileCard

                if let error = logger.lastErrorText {
                    card("最後一次錯誤") {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - 側載是否保留了背景模式

    private var backgroundModeCard: some View {
        card("背景模式（讀自實際安裝的 Info.plist）") {
            let modes = LocationLogger.backgroundModes
            if modes.contains("location") {
                Label("location 已保留，側載沒有把它拿掉", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("缺少 location — 背景定位不會運作，本次測試無效", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
            Text("實際內容：\(modes.isEmpty ? "（空）" : modes.joined(separator: "、"))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 即時狀態

    private var statusCard: some View {
        card("記錄狀態") {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(logger.fixCount) 筆")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text("最後一筆：\(elapsedText(logger.lastFixAt))")
                        .font(.callout)
                    Text("座標：\(logger.lastCoordinateText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("定位權限：\(logger.authorizationText)")
                .font(.callout)
            Text(logger.isTracking ? "追蹤中" : "尚未開始")
                .font(.callout)
                .foregroundStyle(logger.isTracking ? .green : .secondary)
        }
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                logger.start()
            } label: {
                Text(logger.isTracking ? "追蹤中" : "開始記錄")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(logger.isTracking)

            Text("iOS 不會第一次就給「永遠」權限。若權限顯示「使用App期間」，"
                 + "請到 設定 → 隱私權與安全性 → 定位服務 → Wayink Spike 手動改成「永遠」。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 記錄檔取出

    private var fileCard: some View {
        card("記錄檔") {
            Text(logger.logURL.lastPathComponent)
                .font(.callout)
            Text("可在「檔案」App → 我的 iPhone → Wayink Spike 找到")
                .font(.caption)
                .foregroundStyle(.secondary)
            ShareLink(item: logger.logURL) {
                Label("分享記錄檔", systemImage: "square.and.arrow.up")
            }
            .font(.callout)
        }
    }

    // MARK: - 小工具

    private func elapsedText(_ date: Date?) -> String {
        guard let date else { return "尚未收到" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "\(seconds) 秒前"
        }
        return "\(seconds / 60) 分 \(seconds % 60) 秒前"
    }

    @ViewBuilder
    private func card<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
