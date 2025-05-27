// lib/models/mesh_device.dart

/// Representation of a provisioned mesh device.
class MeshDevice {
  /// Node address assigned by the provisioner.
  final int address;

  /// Universally unique identifier of the device.
  final String uuid;

  /// Optional human readable label.
  final String? label;

  MeshDevice({
    required this.address,
    required this.uuid,
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
}
