import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/climate_provider.dart';
import '../utils/app_colors.dart';
import 'sensor_restart_button.dart';

class ClimateCard extends StatefulWidget {
  const ClimateCard({super.key});

  @override
  State<ClimateCard> createState() => _ClimateCardState();
}

class _ClimateCardState extends State<ClimateCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClimateProvider>().startMonitoring();
    });
  }

  void _showAdjustDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => const _ClimateAdjustDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClimateProvider>(
      builder: (context, climateProvider, _) {
        final climate = climateProvider.climate;
        
        if (climate == null) {
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
                            Icon(Icons.waves_rounded, color: AppColors.primary),
                            SizedBox(width: 10),
                            Text(
                              'Climate Status',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            SensorRestartButton(
                              isRestarting: climateProvider.isRestarting,
                              onPressed: climateProvider.restartSensors,
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: () => _showAdjustDialog(context),
                              icon: const Icon(Icons.tune_rounded, size: 20),
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                foregroundColor: AppColors.primary,
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
                            label: "Temp",
                            value: "${climate.currentTemp.toStringAsFixed(1)}°C",
                            icon: Icons.thermostat_rounded,
                            color: Colors.orange,
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: "Humidity",
                            value: "${climate.currentHumidity.toStringAsFixed(0)}%",
                            icon: Icons.water_drop_rounded,
                            color: Colors.blue,
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: "Pressure",
                            value: "${(climate.currentPressure / 100).toStringAsFixed(1)} hPa",
                            icon: Icons.compress_rounded,
                            color: Colors.purple,
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
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Icon(
                      climate.heaterStatus == "ON" ? Icons.heat_pump_rounded : Icons.mode_fan_off_rounded,
                      size: 16,
                      color: climate.heaterStatus == "ON" ? Colors.orange : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "System is ${climate.controlEnabled ? 'ACTIVE' : 'IDLE'}",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: climate.controlEnabled ? AppColors.primary : Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Target: ${climate.targetTemp}°C / ${climate.targetHumidity}%",
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
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

class _ClimateAdjustDialog extends StatefulWidget {
  const _ClimateAdjustDialog();

  @override
  State<_ClimateAdjustDialog> createState() => _ClimateAdjustDialogState();
}

class _ClimateAdjustDialogState extends State<_ClimateAdjustDialog> {
  late double _temp;
  late double _hum;
  late bool _enabled;
  late int _heater;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final climateProvider = context.watch<ClimateProvider>();
    final climate = climateProvider.climate;

    if (climate == null) return const SizedBox.shrink();

    if (!_initialized) {
      _temp = climate.targetTemp;
      _hum = climate.targetHumidity;
      _enabled = climate.controlEnabled;
      _heater = 1; // Default
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
                "Climate Settings",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              Switch(
                value: _enabled,
                onChanged: (val) => setState(() => _enabled = val),
                activeColor: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 25),
          _buildAdjuster(
            label: "Target Temperature",
            value: _temp,
            unit: "°C",
            min: 20.0,
            max: 40.0,
            color: Colors.orange,
            onChanged: (val) => setState(() => _temp = val),
          ),
          const SizedBox(height: 20),
          _buildAdjuster(
            label: "Target Humidity",
            value: _hum,
            unit: "%",
            min: 30.0,
            max: 90.0,
            color: Colors.blue,
            onChanged: (val) => setState(() => _hum = val),
          ),
          const SizedBox(height: 20),
          const Text("Active Heater", style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          Row(
            children: [
              Expanded(
                child: RadioListTile<int>(
                  title: const Text("Heater 1"),
                  value: 1,
                  groupValue: _heater,
                  onChanged: (val) => setState(() => _heater = val!),
                ),
              ),
              Expanded(
                child: RadioListTile<int>(
                  title: const Text("Heater 2"),
                  value: 2,
                  groupValue: _heater,
                  onChanged: (val) => setState(() => _heater = val!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                climateProvider.updateSettings(
                  targetTemp: _temp,
                  targetHum: _hum,
                  enabled: _enabled,
                  activeHeater: _heater,
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
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

  Widget _buildAdjuster({
    required String label,
    required double value,
    required String unit,
    required double min,
    required double max,
    int? divisions,
    required Color color,
    required Function(double) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            Text("${value.toStringAsFixed(divisions == null ? 1 : 0)}$unit", style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.2),
            inactiveTrackColor: color.withValues(alpha: 0.1),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
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
