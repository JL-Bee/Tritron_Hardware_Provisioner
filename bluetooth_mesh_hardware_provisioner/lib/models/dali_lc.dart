// lib/models/dali_lc.dart

import 'fade_time.dart';

/// Idle configuration for DALI light controller.
class DaliIdleConfig {
  /// Desired arc level in idle state.
  final int arc;

  /// Fade time used when transitioning to idle.
  final FadeTime fade;

  DaliIdleConfig(this.arc, this.fade);
}

/// Trigger configuration for DALI light controller.
class DaliTriggerConfig {
  /// Arc level used in trigger state.
  final int arc;

  /// Fade time to reach the trigger arc level.
  final FadeTime fadeIn;

  /// Fade time to return to idle arc level.
  final FadeTime fadeOut;
  final int holdTime;

  DaliTriggerConfig(this.arc, this.fadeIn, this.fadeOut, this.holdTime);
}

/// Override state for DALI light controller.
class DaliOverrideState {
  /// Arc level during the override period.
  final int arc;

  /// Fade time used when applying the override.
  final FadeTime fade;
  final int duration;

  DaliOverrideState(this.arc, this.fade, this.duration);
}

/// Complete DALI LC information cached for a node.
class DaliLcInfo {
  final DaliIdleConfig idle;
  final DaliTriggerConfig trigger;
  final int identifyRemaining;
  final DaliOverrideState override;

  DaliLcInfo({
    required this.idle,
    required this.trigger,
    required this.identifyRemaining,
    required this.override,
  });
}
