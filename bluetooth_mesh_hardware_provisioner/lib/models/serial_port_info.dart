// lib/models/serial_port_info.dart

class SerialPortInfo {
  final String portName;
  final String? description;
  final String? manufacturer;
  final String? serialNumber;
  final int? vendorId;
  final int? productId;

  SerialPortInfo({
    required this.portName,
    this.description,
    this.manufacturer,
    this.serialNumber,
    this.vendorId,
    this.productId,
  });

  // Check if this might be an NRF52 device based on known identifiers
  bool get isNRF52Device {
    // Nordic Semiconductor USB Vendor ID
    if (vendorId == 0x1366) return true;

    // Check description and manufacturer strings
    final desc = description?.toLowerCase() ?? '';
    final mfg = manufacturer?.toLowerCase() ?? '';

    return desc.contains('nrf52') ||
           desc.contains('nordic') ||
           mfg.contains('nordic') ||
           mfg.contains('segger'); // J-Link devices often used with NRF52
  }

  // Generate a display name for the port
  String get displayName {
    if (description != null && description!.isNotEmpty) {
      return description!;
    }
    return portName;
  }

  // Generate a subtitle for display
  String get displaySubtitle {
    final parts = <String>[];

    if (manufacturer != null) {
      parts.add('Manufacturer: $manufacturer');
    }

    if (vendorId != null || productId != null) {
      final vid = vendorId?.toRadixString(16).padLeft(4, '0').toUpperCase() ?? '????';
      final pid = productId?.toRadixString(16).padLeft(4, '0').toUpperCase() ?? '????';
      parts.add('VID:PID = $vid:$pid');
    }

    if (serialNumber != null) {
      parts.add('S/N: $serialNumber');
    }

    return parts.join(' • ');
  }
}
