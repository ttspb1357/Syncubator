import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/oxygen_provider.dart';
import '../utils/app_colors.dart';
import 'sensor_restart_button.dart';

class OxygenCard extends StatefulWidget {
  const OxygenCard({super.key});

  @override
  State<OxygenCard> createState() => _OxygenCardState();
}

class _OxygenCardState extends State<OxygenCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OxygenProvider>().startMonitoring();
    });
  }

  void _showAdjustDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => const _OxygenAdjustDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OxygenProvider>(
      builder: (context, provider, _) {
        final oxygen = provider.oxygen;
        
        if (oxygen == null) {
          return Container(
            height: 150,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.air_rounded, color: Colors.teal),
                            SizedBox(width: 10),
                            Text(
                              'Oxygen Monitor',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            SensorRestartButton(
                              isRestarting: provider.isRestarting,
                              onPressed: provider.restartSensor,
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: () => _showAdjustDialog(context),
                              icon: const Icon(Icons.tune_rounded, size: 20),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.teal.withValues(alpha: 0.1),
                                foregroundColor: Colors.teal,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: _Metric(
                            label: "O2 Conc.",
                            value: "${oxygen.measuredPercent.toStringAsFixed(1)}%",
                            icon: Icons.bubble_chart_rounded,
                            color: Colors.teal,
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: "Valve Level",
                            value: "Lvl ${oxygen.level}",
                            icon: Icons.settings_input_component_rounded,
                            color: Colors.indigo,
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: "Sensor Status",
                            value: oxygen.sensorStatus,
                            icon: Icons.check_circle_outline_rounded,
                            color: oxygen.sensorStatus == 'OK' ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Icon(
                      oxygen.moving ? Icons.sync : Icons.info_outline,
                      size: 16,
                      color: oxygen.moving ? Colors.teal : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        oxygen.moving ? "Adjusting Valve..." : "Sensor Voltage: ${oxygen.voltage.toStringAsFixed(3)}V",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: oxygen.moving ? Colors.teal : Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      oxygen.controlEnabled
                          ? "Auto: Target ${oxygen.targetPercent.toStringAsFixed(0)}%"
                          : "Auto: OFF",
                      style: TextStyle(
                        fontSize: 12,
                        color: oxygen.controlEnabled ? Colors.teal : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OxygenAdjustDialog extends StatefulWidget {
  const _OxygenAdjustDialog();

  @override
  State<_OxygenAdjustDialog> createState() => _OxygenAdjustDialogState();
}

class _OxygenAdjustDialogState extends State<_OxygenAdjustDialog> {
  int? _level;
  double? _targetPercent;
  bool? _autoEnabled;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OxygenProvider>();
    final oxygen = provider.oxygen;

    if (oxygen == null) return const SizedBox.shrink();
    _level ??= oxygen.level;
    if (!_initialized) {
      _targetPercent = oxygen.targetPercent;
      _autoEnabled = oxygen.controlEnabled;
      _initialized = true;
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Oxygen Control",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              Switch(
                value: _autoEnabled!,
                onChanged: (val) => setState(() => _autoEnabled = val),
                activeColor: Colors.teal,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _autoEnabled!
                ? "Auto: the valve opens to max when the reading drops 1.5% below target, and closes once it rises 1.5% above — same hysteresis band as climate control."
                : "Auto control is off — only the manual valve level below applies.",
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Target O2 Level", style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              Text("${_targetPercent!.toStringAsFixed(0)}%", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.teal,
              thumbColor: Colors.teal,
              overlayColor: Colors.teal.withValues(alpha: 0.2),
              inactiveTrackColor: Colors.teal.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: _targetPercent!.clamp(15.0, 50.0),
              min: 15,
              max: 50,
              onChanged: (val) => setState(() => _targetPercent = val),
            ),
          ),
          const Divider(height: 30),
          const Text(
            "Manual valve level (0 closed – 7 max). Still works even with auto control on; auto will override it on its next transition.",
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Valve Level", style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              Text("Lvl $_level", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 18)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.teal,
              thumbColor: Colors.teal,
              overlayColor: Colors.teal.withValues(alpha: 0.2),
              inactiveTrackColor: Colors.teal.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: _level!.toDouble(),
              min: 0,
              max: 7,
              divisions: 7,
              onChanged: (val) => setState(() => _level = val.toInt()),
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                provider.updateSettings(targetPercent: _targetPercent, enabled: _autoEnabled);
                provider.setLevel(_level!);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Apply Changes", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
