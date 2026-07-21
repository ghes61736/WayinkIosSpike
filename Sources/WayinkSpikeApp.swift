import SwiftUI
import UIKit

@main
struct WayinkSpikeApp: App {
    // SwiftUI 的 App 生命週期拿不到 launchOptions，必須靠 UIKit 的 AppDelegate 才能判讀
    // 「這次啟動是不是被定位事件喚醒的」——那是「系統復活」與「使用者手開」的唯一可靠訊號。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// 唯一任務：在 App 完成啟動的那一刻讀 launchOptions，把「這次是不是被定位喚醒」記給 logger。
/// `launchOptions[.location]` 有值，代表 App 是被系統因顯著位置變化重新喚醒的（先前已被殺）。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LocationLogger.pendingLaunchWokenByLocation = launchOptions?[.location] != nil
        return true
    }
}

/// 主畫面的設計目標是「回來看一眼就知道結果」。
/// 撈記錄檔是備援手段，不該是判讀的必要條件——走完一小時回到家還得先接電腦
/// 才知道測到什麼，會讓每一次重測的成本高到不想重測。
struct ContentView: View {

    @StateObject private var logger = LocationLogger()
    @State private var recenterToken = 0
    @State private var baseMapStyle: BaseMapStyle = .osm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Wayink 定位 Spike")
                    .font(.title2)
                    .bold()

                mapCard
                backgroundModeCard
                relaunchCard
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

    // MARK: - 地圖（驗證 MapLibre iOS 能否渲染）

    private var mapCard: some View {
        card("地圖（MapLibre iOS）") {
            // 底圖切換：OSM 街道 ／ PMTiles 影像。切到 PMTiles 是要驗證 iOS 能否讀 pmtiles source。
            Picker("底圖", selection: $baseMapStyle) {
                ForEach(BaseMapStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)

            ZStack(alignment: .bottomTrailing) {
                MapLibreView(
                    coordinates: logger.coordinates,
                    recenterToken: recenterToken,
                    style: baseMapStyle
                )
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // 拖動地圖後,地圖會停止跟隨;按這個鈕拉回自己的位置並重新跟隨。
                Button {
                    recenterToken += 1
                } label: {
                    Image(systemName: "location.fill")
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                }
                .padding(12)
            }
            Text("地圖會跟著你走動移動。拖走後按右下角定位鈕拉回來。藍線是走過的軌跡(要走動才畫得出來)。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("切到「PMTiles 影像」＝驗證 MapLibre iOS 能否讀 pmtiles source（Wayink 離線底圖的技術前提）。"
                 + "這版用官方遠端 demo pmtiles、需 wifi 就能測；本機離線大檔是下一步硬骨頭。")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    // MARK: - 啟動與復活（背景定位最後一塊未驗拼圖）

    private var relaunchCard: some View {
        card("啟動與復活") {
            let resurrected = logger.launchReasonText.contains("復活")
            HStack(spacing: 4) {
                Text("本次啟動：")
                Text(logger.launchReasonText)
                    .foregroundStyle(resurrected ? .orange : .primary)
                    .bold()
            }
            .font(.callout)

            Text("App 啟動次數（含系統復活）：\(logger.launchCount)")
                .font(.callout)

            Label(
                logger.isMonitoringSignificantChanges
                    ? "顯著位置變化監聽中（被殺後可復活）"
                    : "尚未監聽顯著位置變化",
                systemImage: logger.isMonitoringSignificantChanges ? "checkmark.circle.fill" : "circle"
            )
            .font(.caption)
            .foregroundStyle(logger.isMonitoringSignificantChanges ? .green : .secondary)

            Text("驗證復活：開始記錄後出門走一整天。iOS 可能因記憶體壓力把 App 殺掉，"
                 + "若之後「啟動次數」自己增加、且本次啟動顯示「定位事件喚醒」，"
                 + "就證明 App 被殺後靠顯著位置變化自動復活並接續記錄了。")
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

            // 停止並清除自動恢復旗標。沒有它，裝上去就會永遠在背景記錄、無法乾淨結束測試。
            Button(role: .destructive) {
                logger.stop()
            } label: {
                Text("停止記錄")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!logger.isTracking)

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
