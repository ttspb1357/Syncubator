import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bed_provider.dart';
import '../models/bed_model.dart';
import '../utils/app_colors.dart';
import 'sensor_restart_button.dart';

class BedControlCard extends StatefulWidget {
  const BedControlCard({super.key});

  @override
  State<BedControlCard> createState() => _BedControlCardState();
}

class _BedControlCardState extends State<BedControlCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BedProvider>().startMonitoring();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BedProvider>(
      builder: (context, bedProvider, _) {
        final distance = bedProvider.bed.distance;
        final action = bedProvider.bed.action;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.airline_seat_flat_angled_rounded, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Bed Positioning',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const Spacer(),
                    SensorRestartButton(
                      isRestarting: bedProvider.isRestarting,
                      onPressed: bedProvider.restartSensor,
                    ),
                    const SizedBox(width: 4),
                    _StatusIndicator(action: action),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      // Visual Distance Representation
                      Expanded(
                        flex: 2,
                        child: _DistanceVisualizer(distance: distance),
                      ),
                      const VerticalDivider(width: 40, indent: 10, endIndent: 10),
                      // Controls
                      Expanded(
                        flex: 3,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _BedActionButton(
                              icon: Icons.expand_less_rounded,
                              label: "RAISE",
                              isActive: action == BedAction.raising,
                              onPressed: bedProvider.raise,
                            ),
                            const SizedBox(height: 12),
                            _BedActionButton(
                              icon: Icons.expand_more_rounded,
                              label: "LOWER",
                              isActive: action == BedAction.lowering,
                              onPressed: bedProvider.lower,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (bedProvider.lastErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    bedProvider.lastErrorMessage!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DistanceVisualizer extends StatelessWidget {
  final double distance;
  const _DistanceVisualizer({required this.distance});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "${distance.toStringAsFixed(2)}",
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const Text("cm", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _BedActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  const _BedActionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isActive ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? AppColors.primary : AppColors.background,
        foregroundColor: isActive ? Colors.white : AppColors.primary,
        elevation: isActive ? 4 : 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1),
          ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final BedAction action;
  const _StatusIndicator({required this.action});

  @override
  Widget build(BuildContext context) {
    String text = "IDLE";
    Color color = Colors.grey;
    if (action == BedAction.raising) {
      text = "RAISING";
      color = Colors.green;
    } else if (action == BedAction.lowering) {
      text = "LOWERING";
      color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
