import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

class MapPickerWidget extends StatefulWidget {
  final Function(double lat, double lng) onLocationSelected;

  const MapPickerWidget({super.key, required this.onLocationSelected});

  @override
  State<MapPickerWidget> createState() => _MapPickerWidgetState();
}

class _MapPickerWidgetState extends State<MapPickerWidget> {
  late String viewId;

  @override
  void initState() {
    super.initState();
    viewId = 'map-picker-${DateTime.now().millisecondsSinceEpoch}';
    _initializeMap();
  }

  void _initializeMap() {
    final mapHtml = '''
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <title>位置選択</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            body { margin: 0; padding: 0; }
            #map { height: 100vh; width: 100vw; }
        </style>
    </head>
    <body>
        <div id="map"></div>
        <script>
            // 地図の初期化（東京を中心に）
            var map = L.map('map').setView([35.6762, 139.6503], 10);
            
            // 国土地理院の標準地図タイル
            L.tileLayer('https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png', {
                attribution: '<a href="https://maps.gsi.go.jp/development/ichiran.html">国土地理院</a>',
                maxZoom: 18
            }).addTo(map);
            
            var selectedMarker = null;
            
            map.on('click', function(e) {
                if (selectedMarker) {
                    map.removeLayer(selectedMarker);
                }
                
                selectedMarker = L.marker([e.latlng.lat, e.latlng.lng])
                    .addTo(map)
                    .bindPopup('選択された位置<br>緯度: ' + e.latlng.lat.toFixed(4) + '<br>経度: ' + e.latlng.lng.toFixed(4))
                    .openPopup();
                
                // Flutterに位置情報を送信
                window.parent.postMessage({
                    type: 'locationSelected',
                    lat: e.latlng.lat,
                    lng: e.latlng.lng
                }, '*');
            });
        </script>
    </body>
    </html>
    ''';

    ui_web.platformViewRegistry.registerViewFactory(
      viewId,
      (int id) {
        final iframe = html.IFrameElement()
          ..width = '100%'
          ..height = '100%'
          ..srcdoc = mapHtml
          ..style.border = 'none';
        
        // メッセージリスナーを追加
        html.window.addEventListener('message', (event) {
          final data = (event as html.MessageEvent).data;
          if (data != null && data['type'] == 'locationSelected') {
            widget.onLocationSelected(data['lat'], data['lng']);
          }
        });
        
        return iframe;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: viewId);
  }
}