import SwiftUI
import CoreLocation
import MapLibre

/// MapLibre 地圖的 SwiftUI 包裝:顯示線上底圖、把記錄到的軌跡畫成線、顯示使用者藍點。
///
/// 底圖仍用 MapLibre 官方 demo tiles(線上)。Wayink 真正用的離線 pmtiles 是後面的事——
/// 6.27.0 起 MapLibre iOS 原生支援 PMTiles source,屆時再接。
///
/// 效能備註:`updateUIView` 每次座標更新都會移除並重畫整條 polyline,長時間記錄(上千筆)
/// 下會退化。這一版先求「看得到軌跡」,節流/抽稀留到之後。
struct MapLibreView: UIViewRepresentable {

    var coordinates: [CLLocationCoordinate2D]

    /// 每次 +1 代表使用者按了「回到我的位置」。用遞增整數而非 Bool,是因為連按兩次
    /// 都要能各自觸發一次重新跟隨——Bool 停在 true 時第二次按不會有變化。
    var recenterToken: Int

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.styleURL = Self.osmRasterStyleURL()
        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator
        // 先給街道級 zoom 對準台灣;定位一到,userTrackingMode 會接管、把鏡頭移到使用者處
        // 並持續跟隨(走路時地圖自動跟著移動,像導航)。用 .follow 不轉向,避免走路時地圖亂轉。
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: 23.9, longitude: 121.0),
            zoomLevel: 16,
            animated: false
        )
        mapView.userTrackingMode = .follow
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.update(mapView: mapView, coordinates: coordinates)

        // 使用者按了「回到我的位置」:重新進入跟隨模式。拖動地圖時 MapLibre 會自動把
        // trackingMode 設回 .none,這個按鈕是唯一的復位入口。
        if context.coordinator.lastRecenterToken != recenterToken {
            context.coordinator.lastRecenterToken = recenterToken
            mapView.setUserTrackingMode(.follow, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// 產生一個指向 OSM 街道圖磚的 raster style,寫進暫存檔後回傳 file URL。
    ///
    /// 前一版用 MapLibre 官方 demotiles,但它只有低倍率的世界輪廓,拉到街道級(zoom 16)
    /// 就沒有圖磚、只剩背景色——看起來像「地圖沒渲染」,其實是圖源沒資料。改用 OSM raster
    /// 後全 zoom 都有街道細節,能真正確認渲染管線與軌跡疊加。
    ///
    /// ⚠️ OSM 官方 tile server 有使用政策,**僅供這個 spike 測試**,正式版不可直接用;
    /// Wayink 真正要接的是自己的離線 pmtiles(6.27 起 MapLibre iOS 原生支援)。
    private static func osmRasterStyleURL() -> URL? {
        let styleJSON = """
        {
          "version": 8,
          "sources": {
            "osm": {
              "type": "raster",
              "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
              "tileSize": 256,
              "attribution": "© OpenStreetMap contributors"
            }
          },
          "layers": [
            { "id": "osm", "type": "raster", "source": "osm" }
          ]
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("osm-raster-style.json")
        do {
            try styleJSON.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {

        private var polyline: MLNPolyline?
        /// 最後一次處理過的 recenter token。置中/跟隨改由 userTrackingMode 負責,
        /// 不再手動 setCenter。
        var lastRecenterToken = 0

        func update(mapView: MLNMapView, coordinates: [CLLocationCoordinate2D]) {
            if let existing = polyline {
                mapView.removeAnnotation(existing)
                polyline = nil
            }
            guard coordinates.count >= 2 else { return }

            var coords = coordinates
            let line = MLNPolyline(coordinates: &coords, count: UInt(coords.count))
            mapView.addAnnotation(line)
            polyline = line
        }

        // 軌跡線樣式。Wayink 正式版的軌跡顏色由 AutoTrackColors 決定,這裡先用系統藍。
        func mapView(
            _ mapView: MLNMapView,
            strokeColorForShapeAnnotation annotation: MLNShape
        ) -> UIColor {
            UIColor.systemBlue
        }

        func mapView(
            _ mapView: MLNMapView,
            lineWidthForPolylineAnnotation annotation: MLNPolyline
        ) -> CGFloat {
            4.0
        }
    }
}
