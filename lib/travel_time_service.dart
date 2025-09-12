import 'dart:convert';
import 'package:http/http.dart' as http;

import 'main.dart' show LatLng, haversineKm; // reuse simple LatLng + util

class TravelTimeResult {
  final int minutes;
  final bool usedTraffic;
  final String source; // 'distance_matrix' | 'directions' | 'dummy' | 'haversine'
  const TravelTimeResult(this.minutes, {this.usedTraffic = false, this.source = 'dummy'});
}

class TravelTimeService {
  TravelTimeService._();
  static final instance = TravelTimeService._();

  // Configure this to your backend endpoint if available.
  // Example: const String _endpoint = 'https://your.api/travel-time';
  static const String? _endpoint = null;

  Future<TravelTimeResult> fetch({
    required LatLng origin,
    required LatLng destination,
    required DateTime departureUtc,
  }) async {
    if (_endpoint == null) {
      // Fallback to a deterministic haversine-based estimate.
      return _estimate(origin, destination);
    }
    final uri = Uri.parse(_endpoint!).replace(queryParameters: {
      'origin_lat': origin.lat.toString(),
      'origin_lng': origin.lng.toString(),
      'dest_lat': destination.lat.toString(),
      'dest_lng': destination.lng.toString(),
      'mode': 'driving',
      'departure_at': departureUtc.toIso8601String(),
    });
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final m = (data['travel_duration_minutes'] as num?)?.toInt() ?? 0;
        final usedTraffic = data['used_traffic'] == true;
        final source = (data['source'] as String?) ?? 'distance_matrix';
        if (m > 0) return TravelTimeResult(m, usedTraffic: usedTraffic, source: source);
      }
    } catch (_) {}
    // Dummy fallback if backend fails
    return const TravelTimeResult(20, usedTraffic: false, source: 'dummy');
  }

  TravelTimeResult _estimate(LatLng origin, LatLng dest) {
    final km = haversineKm(origin, dest);
    final minutes = (km * 1.8 + 6).round().clamp(1, 9999); // a bit slower than before
    return TravelTimeResult(minutes, usedTraffic: false, source: 'haversine');
  }
}

