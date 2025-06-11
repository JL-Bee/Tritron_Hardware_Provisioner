// lib/models/fade_time.dart

/// Fade durations supported by DALI light control.
enum FadeTime {
  zero(0, '0s'),
  halfSecond(1, '0.5s'),
  oneSecond(2, '1s'),
  oneAndHalf(3, '1.5s'),
  twoSeconds(4, '2s'),
  threeSeconds(5, '3s'),
  fourSeconds(6, '4s'),
  sixSeconds(7, '6s'),
  eightSeconds(8, '8s'),
  tenSeconds(9, '10s'),
  fifteenSeconds(10, '15s'),
  twentySeconds(11, '20s'),
  thirtySeconds(12, '30s'),
  fortyFiveSeconds(13, '45s'),
  sixtySeconds(14, '60s'),
  ninetySeconds(15, '90s'),
  twoMinutes(16, '2m'),
  threeMinutes(17, '3m'),
  fourMinutes(18, '4m'),
  fiveMinutes(19, '5m'),
  sixMinutes(20, '6m'),
  sevenMinutes(21, '7m'),
  eightMinutes(22, '8m'),
  nineMinutes(23, '9m'),
  tenMinutes(24, '10m'),
  elevenMinutes(25, '11m'),
  twelveMinutes(26, '12m'),
  thirteenMinutes(27, '13m'),
  fourteenMinutes(28, '14m'),
  fifteenMinutes(29, '15m'),
  sixteenMinutes(30, '16m'),
  invalid(255, 'invalid');

  /// Integer value used by the hardware protocol.
  final int value;

  /// Human readable label for the fade duration.
  final String label;

  const FadeTime(this.value, this.label);

  /// Get the enum from its numeric value.
  static FadeTime fromValue(int value) {
    return FadeTime.values.firstWhere(
      (e) => e.value == value,
      orElse: () => FadeTime.invalid,
    );
  }

  @override
  String toString() => label;
}
