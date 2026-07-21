import SwiftUI
import CoreLocation
import MapLibre

/// MapLibre 地圖的 SwiftUI 包裝。
///
/// 這一版**刻意只顯示線上地圖、不畫軌跡**：目的是單獨驗證「MapLibre 這個第三方依賴
/// 能不能透過 SPM 在無 Mac 的純 CI 環境裝起來並編譯」。這是整條路第一個、也最可能卡的坎。
/// 若這一版 build 過,就證明 SPM 整合成立;軌跡 polyline 的 API 用法留到下一輪再加,
/// 免得「裝不起來」和「API 寫錯」兩種失敗混在一起分不清。
///
/// 底圖用 MapLibre 官方 demo tiles(線上)。Wayink 真正用的離線 pmtiles 是後面的事——
/// 6.27.0 起 MapLibre iOS 原生支援 PMTiles source,屆時再接。
struct MapLibreView: UIViewRepresentable {

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.styleURL = URL(string: "https://demotiles.maplibre.org/style.json")
        // 先對準台灣,方便一眼看出地圖有沒有渲染出來。
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: 23.9, longitude: 121.0),
            zoomLevel: 6.5,
            animated: false
        )
        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {
        // 尚無動態內容;軌跡疊加下一輪加。
    }
}
