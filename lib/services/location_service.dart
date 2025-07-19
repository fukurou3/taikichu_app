import 'dart:html' as html;
import 'dart:convert';

class LocationService {
  // 逆ジオコーディング: 座標から市区町村を特定
  static Future<String> getLocationFromCoordinates(double lat, double lng) async {
    try {
      // 国土地理院の逆ジオコーディングAPIを使用
      final url = 'https://mreversegeocoder.gsi.go.jp/reverse-geocoder/LonLatToAddress?lat=$lat&lon=$lng';
      
      final response = await html.HttpRequest.request(url);
      if (response.status == 200) {
        final data = json.decode(response.responseText!);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          final pref = result['prefecture'] ?? '';
          final city = result['city'] ?? '';
          final town = result['town'] ?? '';
          
          if (pref.isNotEmpty && city.isNotEmpty) {
            return '$pref$city${town.isNotEmpty ? town : ''}';
          }
        }
      }
    } catch (e) {
      print('逆ジオコーディングエラー: $e');
    }
    
    // フォールバック: 簡易的な地域判定
    return _getApproximateLocation(lat, lng);
  }

  // 簡易的な地域判定（フォールバック用）
  static String _getApproximateLocation(double lat, double lng) {
    // 北海道
    if (lat >= 41.0) return '北海道';
    
    // 沖縄
    if (lat <= 26.5) return '沖縄県';
    
    // 東北地方
    if (lat >= 38.0) {
      if (lng <= 140.0) return '秋田県';
      if (lng <= 141.0) return '岩手県';
      return '宮城県';
    }
    
    // 関東地方
    if (lat >= 35.5) {
      if (lng <= 139.0) return '群馬県';
      if (lng <= 140.0) return '埼玉県';
      return '千葉県';
    }
    
    // 中部地方
    if (lat >= 34.5) {
      if (lng <= 137.0) return '石川県';
      if (lng <= 138.0) return '長野県';
      if (lng <= 139.0) return '静岡県';
      return '神奈川県';
    }
    
    // 関西地方
    if (lat >= 33.5) {
      if (lng <= 135.0) return '兵庫県';
      if (lng <= 136.0) return '大阪府';
      return '三重県';
    }
    
    // 中国・四国地方
    if (lat >= 32.5) {
      if (lng <= 132.0) return '山口県';
      if (lng <= 134.0) return '愛媛県';
      return '香川県';
    }
    
    // 九州地方
    if (lng <= 130.0) return '熊本県';
    if (lng <= 131.0) return '大分県';
    return '福岡県';
  }
}