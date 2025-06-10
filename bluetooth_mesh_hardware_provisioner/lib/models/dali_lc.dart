// lib/models/dali_lc.dart

/// Idle configuration for DALI light controller.
class DaliIdleConfig {
  final int arc;
  final int fade;

  DaliIdleConfig(this.arc, this.fade);
}

/// Trigger configuration for DALI light controller.
class DaliTriggerConfig {
  final int arc;
  final int fadeIn;
  final int fadeOut;
  final int holdTime;

  DaliTriggerConfig(this.arc, this.fadeIn, this.fadeOut, this.holdTime);
}

/// Override state for DALI light controller.
class DaliOverrideState {
  final int arc;
  final int fade;
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
