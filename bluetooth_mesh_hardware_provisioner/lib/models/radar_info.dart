// lib/models/radar_info.dart

/// Configuration and state of the radar sensor.
class RadarInfo {
  final int bandThreshold;
  final int crossCount;
  final int sampleInterval;
  final int bufferDepth;
  final bool enabled;

  RadarInfo({
    required this.bandThreshold,
    required this.crossCount,
    required this.sampleInterval,
    required this.bufferDepth,
    required this.enabled,
  });
}
