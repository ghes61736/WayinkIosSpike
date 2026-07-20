# Wayink iOS 背景定位 Spike

驗證單一問題：**iOS 在螢幕鎖定、App 切到背景的情況下，長時間持續記錄 GPS 軌跡會不會被系統中斷。**

這是 [Wayink](https://github.com/) Android 專案評估是否值得移植到 iOS 的前置實驗。
Wayink 的核心決策是「背景 GPS 穩定性是生死線」——若 iOS 做不到對等，整個移植計畫作廢。
因此這件事要先於任何架構工作驗證。

本 repo **不含 Wayink 任何程式碼或金鑰**，只有一支極簡的 Swift 定位記錄 App。

## 為什麼是 public repo

GitHub Actions 的 macOS runner 對 public repo **完全免費、無配額上限**；
private repo 的 macOS 用量以 10 倍計費，Free 方案 2000 分鐘只剩約 200 分鐘可用。
開發機是 Windows、沒有 Mac，macOS runner 是唯一的編譯環境，配額不能省。

## 建置流程

開發機沒有 Xcode，Swift 是盲寫的，**CI 就是編譯器**。

1. push → GitHub Actions 在 macOS runner 上跑
2. `xcodegen generate` 由 `project.yml` 產生 `.xcodeproj`（**絕不手寫 `.xcodeproj`**）
3. `xcodebuild ... CODE_SIGNING_ALLOWED=NO` 產出 unsigned `.app`
4. 包成 `Payload/` → zip → `.ipa`，上傳為 artifact
5. 下載到 Windows，用 Sideloadly 以免費 Apple ID 重簽並側載到 iPhone

安裝與實測步驟見 [`操作手冊.md`](操作手冊.md)。

## 免費 Apple ID 可以做背景定位

這點反直覺但已查證：`UIBackgroundModes` 是 Info.plist 屬性，**不是 entitlement**。
Apple DTS 工程師在[官方論壇](https://developer.apple.com/forums/thread/787026)明言
「It does not require any specific entitlement and never has」。
免費帳號的限制全在 entitlement 層（Apple Pay／iCloud／推播／IAP 等），該清單裡沒有 Background Modes。

CI 的打包步驟會實際檢查產出的 Info.plist 內含 `UIBackgroundModes`，缺了就讓 build 失敗——
避免設定被靜默吃掉卻要走完一小時才發現。

## 已知未證實項

**Sideloadly 重簽時是否保留 `UIBackgroundModes`。** 理論上必然保留（重簽只替換
`embedded.mobileprovision` 與簽章，不重寫 Info.plist），但無官方明文。
對策：裝上去先做 5 分鐘短測確認有收到背景座標，再花一小時做完整測試。
