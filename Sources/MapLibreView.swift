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

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.styleURL = Self.osmRasterStyleURL()
        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator
        // 先對準台灣;第一次收到座標時再移到使用者位置。
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: 23.9, longitude: 121.0),
            zoomLevel: 6.5,
            animated: false
        )
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.update(mapView: mapView, coordinates: coordinates)
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
        private var hasCenteredOnUser = false

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

            // 第一次拿到座標時把鏡頭移到使用者處(只做一次,之後讓使用者自由平移)。
            if !hasCenteredOnUser, let last = coordinates.last {
                mapView.setCenter(last, zoomLevel: 16, animated: false)
                hasCenteredOnUser = true
            }
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
