import Foundation
import CoreLocation
import UIKit

/// 把每一筆定位與每一次 App 生命週期變化寫進 Documents 下的純文字檔。
///
/// 這支 spike 要回答的唯一問題是「鎖屏、切背景之後，iOS 會不會把定位停掉」。
/// 因此記錄的重點不是座標本身，而是**兩筆座標之間發生了什麼**——
/// 只記座標的話，「系統中斷」與「人沒在動所以沒有新座標」在日誌上長得一模一樣，
/// 但這兩者的結論完全相反。
final class LocationLogger: NSObject, ObservableObject {

    @Published private(set) var fixCount: Int = 0
    @Published private(set) var lastFixAt: Date?
    @Published private(set) var lastCoordinateText: String = "—"
    @Published private(set) var authorizationText: String = "尚未詢問"
    @Published private(set) var isTracking: Bool = false
    @Published private(set) var lastErrorText: String?

    /// 這次 process 是不是 iOS 因定位事件把 App 喚醒重啟的——「被系統殺掉後復活」的直接證據。
    @Published private(set) var launchReasonText: String = "正常啟動"
    /// App 從安裝以來被啟動過幾次（含系統復活）。跨 process 累加，存在 UserDefaults。
    @Published private(set) var launchCount: Int = 0
    /// significant location change 是否正在監聽——這是 App 被系統終止後唯一的復活途徑。
    @Published private(set) var isMonitoringSignificantChanges: Bool = false

    /// AppDelegate 在 `didFinishLaunching` 判讀完 launchOptions 後寫進來，本類別 init 讀走。
    /// 用 static 傳遞，是因為 AppDelegate 的建立早於 ContentView 的 `@StateObject`，
    /// 沒有其他管道能把「這次啟動是不是被定位喚醒」這件事交到 logger 手上。
    static var pendingLaunchWokenByLocation = false

    private enum Keys {
        /// 使用者是否處於「追蹤中」。App 被殺後重啟時靠它決定要不要自動接續記錄。
        static let trackingEnabled = "wayink.tracking.enabled"
        /// App 累計啟動次數，用來讓「系統復活」在 UI 上可見（次數自己增加＝被重啟過）。
        static let launchCount = "wayink.launch.count"
    }

    /// 收到的座標序列,用來在地圖上畫軌跡。
    /// 註:每筆 append 都會觸發 SwiftUI 更新,長時間記錄下上千筆時效能會退化——
    /// 這一版先求正確、能看到軌跡,節流/抽稀留到之後優化。
    @Published private(set) var coordinates: [CLLocationCoordinate2D] = []

    let logURL: URL

    private let manager = CLLocationManager()

    private let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// 側載重簽後 `UIBackgroundModes` 是否還在。
    /// 這是整條路唯一沒有官方明文保證的環節，直接讀 bundle 當場就能回答，
    /// 不必等走完一小時才發現白做。
    static var backgroundModes: [String] {
        Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    }

    override init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.logURL = documents.appendingPathComponent("wayink-spike-log.txt")
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        // 預設是 true：系統判斷你停止移動時會自行暫停定位，而且不保證會恢復。
        // 不關掉的話，日誌上的「軌跡斷掉」會分不清是 iOS 中斷我們，
        // 還是我們自己要求它暫停——那會讓整個實驗得到假的否定結論。
        manager.pausesLocationUpdatesAutomatically = false

        observeLifecycle()
        applyAuthorization(manager.authorizationStatus)

        let defaults = UserDefaults.standard
        launchCount = defaults.integer(forKey: Keys.launchCount) + 1
        defaults.set(launchCount, forKey: Keys.launchCount)
        launchReasonText = Self.pendingLaunchWokenByLocation ? "定位事件喚醒(系統復活)" : "正常啟動"

        append("APP_START modes=\(Self.backgroundModes.joined(separator: "|")) log=\(logURL.path)")
        append("PROCESS_LAUNCH count=\(launchCount) reason=\(launchReasonText)")

        // 復活的核心：上次若在追蹤中（旗標還在），這次啟動不論是使用者手開還是被系統喚醒，
        // 都要自動接續記錄——被系統喚醒時沒有人會去按「開始記錄」，不自動接就等於復活了卻不記錄。
        if defaults.bool(forKey: Keys.trackingEnabled) {
            append("AUTO_RESUME 偵測到上次為追蹤中，嘗試自動恢復記錄")
            resumeIfAuthorized()
        }
    }

    // MARK: - 對外操作

    func start() {
        append("START_REQUESTED auth=\(describe(manager.authorizationStatus))")
        // 記下「使用者要追蹤」。這個旗標是復活的依據：App 被殺後重啟時靠它決定要不要自動接續。
        UserDefaults.standard.set(true, forKey: Keys.trackingEnabled)
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates()
        default:
            append("START_BLOCKED 權限被拒或受限，無法開始")
        }
    }

    /// 乾淨地停止並清除追蹤旗標。沒有這個，旗標一旦設為 true，之後每次啟動都會自動恢復，
    /// 使用者就無法結束測試（會變成裝上去就永遠在背景記錄）。
    func stop() {
        UserDefaults.standard.set(false, forKey: Keys.trackingEnabled)
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        isTracking = false
        isMonitoringSignificantChanges = false
        append("STOP_REQUESTED 已停止定位並清除自動恢復旗標")
    }

    /// App 重啟（含系統復活）時呼叫：已有權限就直接接續記錄，不需任何使用者互動。
    /// 與 `start()` 的差別是它不改旗標、不主動請求權限——復活情境下權限本來就已授予過。
    private func resumeIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates()
        default:
            append("AUTO_RESUME_BLOCKED 目前非授權狀態，無法自動恢復")
        }
    }

    private func beginUpdates() {
        guard !isTracking else { return }

        if manager.authorizationStatus == .authorizedAlways {
            // 若側載重簽把 UIBackgroundModes 拿掉了，下一行會直接讓 App 崩潰。
            // 先寫入 ENABLING 再設定，日誌若停在 ENABLING 就是明確答案。
            append("BACKGROUND_UPDATES_ENABLING")
            manager.allowsBackgroundLocationUpdates = true
            append("BACKGROUND_UPDATES_ENABLED")
        } else {
            append("BACKGROUND_UPDATES_SKIPPED 只有 WhenInUse，鎖屏後預期會斷（非 iOS 的錯）")
        }

        manager.startUpdatingLocation()

        // significant location change：App 被系統終止（記憶體壓力）後，唯一能把它重新
        // 喚醒到背景的機制。standard location updates 在 App 被殺後不會復活，只有這個會。
        // 需要 Always 權限；WhenInUse 下註冊無效，故明確限定在 Always 分支。
        if manager.authorizationStatus == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
            isMonitoringSignificantChanges = true
            append("SLC_MONITORING_STARTED 已註冊顯著位置變化（App 被殺後靠此復活）")
        } else {
            append("SLC_MONITORING_SKIPPED 非 Always 權限，App 被殺後無法復活")
        }

        isTracking = true
        append("UPDATES_STARTED")
    }

    // MARK: - 生命週期

    private func observeLifecycle() {
        let events: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "APP_BACKGROUND"),
            (UIApplication.willEnterForegroundNotification, "APP_FOREGROUND"),
            (UIApplication.didBecomeActiveNotification, "APP_ACTIVE"),
            (UIApplication.willResignActiveNotification, "APP_RESIGN_ACTIVE"),
            (UIApplication.willTerminateNotification, "APP_TERMINATE"),
        ]
        for (name, tag) in events {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.append(tag)
            }
        }
    }

    // MARK: - 寫檔

    /// 每一行獨立開檔、寫入、關檔。速度不重要（最密也就每秒一筆），
    /// 但「App 被系統殺掉時最後幾行不能遺失」很重要——而那正是要觀察的事件本身。
    private func append(_ message: String) {
        let line = "\(stamp.string(from: Date())) [\(appStateText())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
    }

    private func appStateText() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "前景"
        case .inactive: return "非作用中"
        case .background: return "背景"
        @unknown default: return "未知"
        }
    }

    private func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "尚未詢問"
        case .restricted: return "受限"
        case .denied: return "已拒絕"
        case .authorizedAlways: return "永遠"
        case .authorizedWhenInUse: return "使用App期間"
        @unknown default: return "未知"
        }
    }

    private func applyAuthorization(_ status: CLAuthorizationStatus) {
        authorizationText = describe(status)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationLogger: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        applyAuthorization(status)
        append("AUTH_CHANGED \(describe(status))")

        if status == .authorizedAlways || status == .authorizedWhenInUse {
            beginUpdates()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            fixCount += 1
            lastFixAt = Date()
            coordinates.append(location.coordinate)
            lastCoordinateText = String(
                format: "%.5f, %.5f",
                location.coordinate.latitude,
                location.coordinate.longitude
            )
            append(String(
                format: "FIX lat=%.6f lon=%.6f acc=%.1f spd=%.1f age=%.1f",
                location.coordinate.latitude,
                location.coordinate.longitude,
                location.horizontalAccuracy,
                location.speed,
                Date().timeIntervalSince(location.timestamp)
            ))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastErrorText = error.localizedDescription
        append("ERROR \(error.localizedDescription)")
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        append("SYSTEM_PAUSED 系統自行暫停了定位")
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        append("SYSTEM_RESUMED 系統自行恢復了定位")
    }
}
