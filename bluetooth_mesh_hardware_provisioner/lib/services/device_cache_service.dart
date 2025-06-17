// lib/services/device_cache_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mesh_device.dart';

/// Simple local cache for provisioned devices.
class DeviceCacheService {
  static const _devicesKey = 'provisioned_devices';

  /// Save [devices] to persistent storage.
  Future<void> saveDevices(List<MeshDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    final list = devices.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_devicesKey, list);
  }

  /// Load devices from persistent storage.
  Future<List<MeshDevice>> loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_devicesKey);
    if (list == null) return [];
    return list
        .map((e) => MeshDevice.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }
}
