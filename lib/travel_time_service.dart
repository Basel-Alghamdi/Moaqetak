import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';

import 'main.dart' show LatLng, haversineKm, utcToRiyadhLocal; // reuse simple LatLng + util

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
    // Check local settings to see if online traffic should be used
    try {
      if (Hive.isBoxOpen('settings')) {
        final settings = Hive.box('settings');
        final online = settings.get('online_traffic_enabled') == true;
        final provider = (settings.get('traffic_provider') as String?) ?? 'google';
        if (online) {
          if (provider == 'google') {
            final key = (settings.get('google_api_key') as String?)?.trim();
            if (key != null && key.isNotEmpty) {
              final res = await _googleDistanceMatrix(
                origin: origin,
                destination: destination,
                departureUtc: departureUtc,
                apiKey: key,
              );
              if (res != null) return res;
            }
          } else if (provider == 'here') {
            final key = (settings.get('here_api_key') as String?)?.trim();
            if (key != null && key.isNotEmpty) {
              final res = await _hereRouting(
                origin: origin,
                destination: destination,
                departureUtc: departureUtc,
                apiKey: key,
              );
              if (res != null) return res;
            }
          } else if (provider == 'mapbox') {
            final token = (settings.get('mapbox_access_token') as String?)?.trim();
            if (token != null && token.isNotEmpty) {
              final res = await _mapboxDirections(
                origin: origin,
                destination: destination,
                departureUtc: departureUtc,
                accessToken: token,
              );
              if (res != null) return res;
            }
          }
        }
      }
    } catch (_) {}

    if (_endpoint == null) {
      // Local, dynamic estimate using distance + time-of-day traffic factor.
      return _estimateDynamic(origin, destination, departureUtc);
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

  // Simple dynamic estimator: base minutes from straight-line distance,
  // then apply a time-of-day factor to reflect typical traffic in Riyadh.
  TravelTimeResult _estimateDynamic(LatLng origin, LatLng dest, DateTime departureUtc) {
    final km = haversineKm(origin, dest);
    // Base minutes: conservative urban driving
    final base = (km * 1.6 + 6).clamp(1, 9999); // 1.6 min/km + 6 min overhead
    final factor = _trafficFactorFor(departureUtc);
    final minutes = (base * factor).round().clamp(1, 9999);
    return TravelTimeResult(minutes, usedTraffic: true, source: 'haversine+tod');
  }

  // Traffic factor by local time (UTC+3 for Riyadh). Rough profiles:
  // - Weekdays (Sun–Thu): heavy 7–9 and 16–19, moderate 12–15, light late night
  // - Fri: light most of day, moderate around 17–20
  // - Sat: closer to weekday midday pattern
  double _trafficFactorFor(DateTime departureUtc) {
    final local = utcToRiyadhLocal(departureUtc);
    final dow = local.weekday; // 1=Mon .. 7=Sun
    final h = local.hour;

    final bool isFri = dow == DateTime.friday;    // 5
    final bool isThu = dow == DateTime.thursday;  // 4
    final bool isSat = dow == DateTime.saturday;  // 6
    final bool isSunToWed = dow == DateTime.sunday ||
        dow == DateTime.monday ||
        dow == DateTime.tuesday ||
        dow == DateTime.wednesday; // 7 or 1..3

    // Base factors
    double factor = 1.0;

    if (isSunToWed || isThu) {
      if (h >= 7 && h < 9) {
        factor = 1.45; // morning peak
      } else if (h >= 16 && h < 19) {
        factor = 1.55; // evening peak
      } else if (h >= 12 && h < 15) {
        factor = 1.20; // midday busy
      } else if (h >= 19 && h < 22) {
        factor = 1.15; // post-peak
      } else if (h >= 22 || h < 6) {
        factor = 0.95; // late night
      }
      // Slightly higher Thursday evening
      if (isThu && h >= 17 && h < 21) {
        factor += 0.1;
      }
    } else if (isFri) {
      if (h >= 11 && h < 14) {
        factor = 1.10; // midday
      } else if (h >= 17 && h < 20) {
        factor = 1.25; // evening crowding
      } else {
        factor = 0.95; // generally lighter
      }
    } else if (isSat) {
      if (h >= 12 && h < 15) {
        factor = 1.15;
      } else if (h >= 17 && h < 20) {
        factor = 1.25;
      } else if (h >= 22 || h < 7) {
        factor = 0.95;
      }
    }

    // Clamp softly to avoid extremes
    if (factor < 0.8) {
      factor = 0.8;
    }
    if (factor > 1.9) {
      factor = 1.9;
    }
    return factor;
  }

  Future<TravelTimeResult?> _googleDistanceMatrix({
    required LatLng origin,
    required LatLng destination,
    required DateTime departureUtc,
    required String apiKey,
  }) async {
    try {
      final dep = departureUtc.millisecondsSinceEpoch ~/ 1000; // seconds
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/distancematrix/json',
        {
          'origins': '${origin.lat},${origin.lng}',
          'destinations': '${destination.lat},${destination.lng}',
          'mode': 'driving',
          'departure_time': dep.toString(),
          'traffic_model': 'best_guess',
          'key': apiKey,
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final rows = data['rows'] as List?;
          if (rows != null && rows.isNotEmpty) {
            final els = (rows[0] as Map<String, dynamic>)['elements'] as List?;
            if (els != null && els.isNotEmpty) {
              final el = els[0] as Map<String, dynamic>;
              if (el['status'] == 'OK') {
                final dinTraffic = ((el['duration_in_traffic'] as Map?)?.cast<String, dynamic>())?['value'] as num?;
                final seconds = (dinTraffic ?? ((el['duration'] as Map?)?['value'] as num?))?.toInt();
                if (seconds != null && seconds > 0) {
                  final minutes = (seconds / 60).round();
                  return TravelTimeResult(minutes, usedTraffic: true, source: 'google');
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<TravelTimeResult?> _hereRouting({
    required LatLng origin,
    required LatLng destination,
    required DateTime departureUtc,
    required String apiKey,
  }) async {
    try {
      final depIso = departureUtc.toIso8601String();
      final uri = Uri.https(
        'router.hereapi.com',
        '/v8/routes',
        {
          'transportMode': 'car',
          'origin': '${origin.lat},${origin.lng}',
          'destination': '${destination.lat},${destination.lng}',
          'return': 'summary',
          'departureTime': depIso,
          'apikey': apiKey,
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final sections = (routes[0] as Map<String, dynamic>)['sections'] as List?;
          if (sections != null && sections.isNotEmpty) {
            int totalSec = 0;
            for (final s in sections) {
              final sum = (s as Map<String, dynamic>)['summary'] as Map<String, dynamic>?;
              final sec = (sum?['duration'] as num?)?.toInt() ?? 0;
              totalSec += sec;
            }
            if (totalSec > 0) {
              return TravelTimeResult((totalSec / 60).round(), usedTraffic: true, source: 'here');
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<TravelTimeResult?> _mapboxDirections({
    required LatLng origin,
    required LatLng destination,
    required DateTime departureUtc,
    required String accessToken,
  }) async {
    try {
      // Mapbox traffic reflects current conditions; depart_at may not be honored across all tiers.
      final path = '${origin.lng},${origin.lat};${destination.lng},${destination.lat}';
      final uri = Uri.https(
        'api.mapbox.com',
        '/directions/v5/mapbox/driving-traffic/$path',
        {
          'access_token': accessToken,
          'overview': 'false',
          'geometries': 'geojson',
          'alternatives': 'false',
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final dur = ((routes[0] as Map<String, dynamic>)['duration'] as num?)?.toDouble();
          if (dur != null && dur > 0) {
            return TravelTimeResult((dur / 60).round(), usedTraffic: true, source: 'mapbox');
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
