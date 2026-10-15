import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether background polling should slow down: metered network or the OS
/// battery saver. Android and iOS answer over a platform channel; desktop
/// and any channel failure answer "no".
class SyncThrift {
  SyncThrift._();

  static const _channel = MethodChannel('abelnotes/sync_thrift');
  static const _maxAge = Duration(seconds: 30);

  static bool _thrifty = false;
  static DateTime _checkedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _inFlight = false;

  /// Last known answer. Call [refresh] to update it.
  static bool get thrifty => _thrifty;

  static Future<void> refresh() async {
    if (_inFlight) return;
    if (DateTime.now().difference(_checkedAt) < _maxAge) return;
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return;
    }
    _inFlight = true;
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('state');
      _thrifty = r?['metered'] == true || r?['lowPower'] == true;
    } catch (_) {
      _thrifty = false;
    } finally {
      _checkedAt = DateTime.now();
      _inFlight = false;
    }
  }
}
