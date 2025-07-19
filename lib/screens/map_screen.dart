import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import '../models/post_models.dart';
import '../services/firestore_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late String viewId;
  List<PostModel> allPosts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    viewId = 'map-view-${DateTime.now().millisecondsSinceEpoch}';
    _initializeMap();
    _loadPosts();
  }

  void _initializeMap() {
    // 国土地理院の地図HTMLを作成
    final mapHtml = '''
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <title>地図</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            body { margin: 0; padding: 0; }
            #map { height: 100vh; width: 100vw; }
            .custom-popup {
                max-width: 300px;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            }
            .popup-title {
                font-weight: bold;
                font-size: 16px;
                margin-bottom: 8px;
                color: #333;
            }
            .popup-content {
                font-size: 14px;
                margin-bottom: 8px;
                color: #666;
            }
            .popup-location {
                font-size: 12px;
                color: #888;
                display: flex;
                align-items: center;
            }
            .popup-author {
                font-size: 12px;
                color: #888;
                margin-top: 4px;
            }
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
            
            // 投稿データを表示するためのマーカーグループ
            var markersGroup = L.layerGroup().addTo(map);
            
            // Flutterからのメッセージを受信
            window.addEventListener('message', function(event) {
                if (event.data.type === 'addMarkers') {
                    markersGroup.clearLayers();
                    event.data.posts.forEach(function(post) {
                        if (post.latitude && post.longitude) {
                            var marker = L.marker([post.latitude, post.longitude])
                                .bindPopup(createPopupContent(post));
                            markersGroup.addLayer(marker);
                        }
                    });
                }
            });
            
            function createPopupContent(post) {
                var title = post.title || post.content.substring(0, 50) + '...';
                var content = post.content;
                var author = post.authorName || 'Unknown';
                var location = '';
                
                if (post.municipality) {
                    location = '📍 ' + post.municipality;
                } else if (post.latitude && post.longitude) {
                    if (post.detectedLocation) {
                        location = '📍 ' + post.detectedLocation + ' (詳細位置)';
                    } else {
                        location = '📍 ' + post.latitude.toFixed(4) + ', ' + post.longitude.toFixed(4);
                    }
                }
                
                return '<div class="custom-popup">' +
                       '<div class="popup-title">' + title + '</div>' +
                       '<div class="popup-content">' + content + '</div>' +
                       '<div class="popup-location">' + location + '</div>' +
                       '<div class="popup-author">投稿者: ' + author + '</div>' +
                       '</div>';
            }
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
        
        return iframe;
      },
    );
  }

  Future<void> _loadPosts() async {
    try {
      final posts = await FirestoreService.getPostsWithLocation();
      setState(() {
        allPosts = posts;
        isLoading = false;
      });
      
      print('地図に表示する投稿数: ${posts.length}');
      
      // 地図にマーカーを追加するためのメッセージを送信
      Future.delayed(const Duration(milliseconds: 500), () {
        final iframe = html.document.getElementById(viewId) as html.IFrameElement?;
        if (iframe?.contentWindow != null) {
          iframe!.contentWindow!.postMessage({
            'type': 'addMarkers',
            'posts': posts.map((post) => {
              'title': post.title,
              'content': post.content,
              'authorName': post.authorName,
              'latitude': post.latitude,
              'longitude': post.longitude,
              'municipality': post.municipality,
              'detectedLocation': post.detectedLocation,
            }).toList(),
          }, '*');
        }
      });
    } catch (e) {
      print('投稿データの読み込みエラー: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HtmlElementView(viewType: viewId),
        if (isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
        if (!isLoading && allPosts.isEmpty)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_off, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      '位置情報付きの投稿がありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}