import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Small icon button that re-initializes a sensor's hardware driver on the
/// Pi (not just a data re-fetch) — for a card whose sensor is stuck or
/// unresponsive. Shows a spinner in place of the icon while the restart
/// request is in flight.
class SensorRestartButton extends StatelessWidget {
  final bool isRestarting;
  final VoidCallback onPressed;
  final Color color;

  const SensorRestartButton({
    super.key,
    required this.isRestarting,
    required this.onPressed,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Restart sensor',
      onPressed: isRestarting ? null : onPressed,
      icon: isRestarting
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(Icons.refresh_rounded, color: color),
    );
  }
}
