// lib/models/mesh_device.dart

/// Representation of a provisioned mesh device.
class MeshDevice {
  /// Node address assigned by the provisioner.
  final int address;

  /// Universally unique identifier of the device.
  final String uuid;

  /// Number of hops reported for the last received heartbeat.
  final int? nHops;

  /// RSSI of the last received heartbeat.
  final int? rssi;

  /// Time in milliseconds since the last heartbeat.
  final int? timeSinceLastHb;

  /// Optional human readable label.
  final String? label;

  MeshDevice({
    required this.address,
    required this.uuid,
    this.nHops,
    this.rssi,
    this.timeSinceLastHb,
    this.label,
  });

  /// Hexadecimal representation of the node address.
  String get addressHex =>
      '0x${address.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  /// Own group address calculated from the node address.
  int get groupAddress => 0xC000 | address;

  /// Hexadecimal representation of [groupAddress].
  String get groupAddressHex =>
      '0x${groupAddress.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  /// Determine the device's online status based on [timeSinceLastHb].
  ///
  /// If no heartbeat has been received or two consecutive heartbeats were
  /// missed (>10s), the device is considered offline. If exactly one
  /// heartbeat was missed (>5s) the status is [DeviceStatus.stale].
  DeviceStatus get status {
    if (timeSinceLastHb == null || timeSinceLastHb == 0 || timeSinceLastHb! > 10000) {
      return DeviceStatus.offline;
    }
    if (timeSinceLastHb! > 5000) {
      return DeviceStatus.stale;
    }
    return DeviceStatus.online;
  }
}

/// Online state of a mesh device determined from heartbeat timing.
enum DeviceStatus { online, stale, offline }
