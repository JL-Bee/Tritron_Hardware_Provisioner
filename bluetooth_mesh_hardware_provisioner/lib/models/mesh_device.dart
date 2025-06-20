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

  /// Create a copy of this device with optional overrides.
  MeshDevice copyWith({
    int? nHops,
    int? rssi,
    int? timeSinceLastHb,
    String? label,
  }) {
    return MeshDevice(
      address: address,
      uuid: uuid,
      nHops: nHops ?? this.nHops,
      rssi: rssi ?? this.rssi,
      timeSinceLastHb: timeSinceLastHb ?? this.timeSinceLastHb,
      label: label ?? this.label,
    );
  }

  /// Serialize this device to JSON.
  Map<String, dynamic> toJson() => {
        'address': address,
        'uuid': uuid,
        'nHops': nHops,
        'rssi': rssi,
        'timeSinceLastHb': timeSinceLastHb,
        'label': label,
      };

  /// Construct a device instance from JSON.
  factory MeshDevice.fromJson(Map<String, dynamic> json) => MeshDevice(
        address: json['address'] as int,
        uuid: json['uuid'] as String,
        nHops: json['nHops'] as int?,
        rssi: json['rssi'] as int?,
        timeSinceLastHb: json['timeSinceLastHb'] as int?,
        label: json['label'] as String?,
      );

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
  /// heartbeat was missed (>6s) the status is [DeviceStatus.stale].
  DeviceStatus get status {
    if (timeSinceLastHb == null || timeSinceLastHb! < 0 || timeSinceLastHb! > 10000) {
      return DeviceStatus.offline;
    }
    if (timeSinceLastHb! > 6000) {
      return DeviceStatus.stale;
    }
    return DeviceStatus.online;
  }
}

/// Online state of a mesh device determined from heartbeat timing.
enum DeviceStatus { online, stale, offline }
