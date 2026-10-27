import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/skin_model.dart';
import '../providers/skin_provider.dart';
import '../utils/app_colors.dart';

/// Live skin temperature from the YSI-400 probe on the Pi's ADS1115.
class SkinCard extends StatefulWidget {
  const SkinCard({super.key});

  @override
  State<SkinCard> createState() => _SkinCardState();
}

class _SkinCardState extends State<SkinCard> {
  static const Color _accent = Colors.deepOrange;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SkinProvider>().startMonitoring();
    });
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => const _SkinSettingsSheet(),
    );
  }

  static String _statusText(SkinModel s) {
    switch (s.status) {
      case 'OK':
        return 'Reading';
      case 'PROBE_OFF':
        return 'Probe not plugged in';
      case 'SHORT':
        return 'Probe wire shorted';
      case 'RANGE':
        return 'Reading out of range';
      default:
        return 'Sensor board not responding';
    }
  }

  static Color _statusColor(SkinModel s) {
    switch (s.status) {
      case 'OK':
        return Colors.green;
      case 'PROBE_OFF':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SkinProvider>(
      builder: (context, provider, _) {
        final s = provider.skin;

        if (s == null) {
          return Container(
            height: 120,
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.thermostat_rounded, color: _accent),
                          const SizedBox(width: 10),
                          const Text(
                            'Skin Temperature',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                          const Spacer(),
                          Text(
                            s.hasReading ? s.temp!.toStringAsFixed(1) : '--',
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: _accent),
                          ),
                          const SizedBox(width: 3),
                          const Text('°C', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => _showSettings(context),
                      icon: const Icon(Icons.tune_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: _accent.withValues(alpha: 0.1),
                        foregroundColor: _accent,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: _statusColor(s)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusText(s),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor(s)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      s.monitoringEnabled ? 'Alarms: ON' : 'Alarms: OFF',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: s.monitoringEnabled ? _accent : Colors.grey[600],
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

class _SkinSettingsSheet extends StatelessWidget {
  const _SkinSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SkinProvider>();
    final s = provider.skin;
    if (s == null) return const SizedBox.shrink();

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
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Skin Temperature Alarms',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              Switch(
                value: s.monitoringEnabled,
                onChanged: (val) => provider.setMonitoring(val),
                activeThumbColor: Colors.deepOrange,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.monitoringEnabled
                ? 'On: alarms sound for low or high skin temperature, and when the probe is unplugged or its wire is faulty.'
                : 'Off: the reading is still shown, but no skin temperature or probe alarms are raised. Turn this on once the probe is on the baby.',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text(
            'The alarm limits are set in Alarm Limits. The skin temperature is for display and alarms only; it does not control the heater.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
