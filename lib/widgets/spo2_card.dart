import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/spo2_model.dart';
import '../providers/spo2_provider.dart';
import '../utils/app_colors.dart';

/// Live SpO2 / pulse from the CMS60C pulse oximeter on the Pi's USB port.
class Spo2Card extends StatefulWidget {
  const Spo2Card({super.key});

  @override
  State<Spo2Card> createState() => _Spo2CardState();
}

class _Spo2CardState extends State<Spo2Card> {
  static const Color _accent = Colors.redAccent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<Spo2Provider>().startMonitoring();
    });
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => const _Spo2SettingsSheet(),
    );
  }

  static String _statusText(Spo2Model s) {
    switch (s.status) {
      case 'OK':
        return 'Reading';
      case 'NO_FINGER':
        return 'No finger / probe off';
      case 'NO_DATA':
        return 'Oximeter not sending data';
      default:
        return 'Oximeter not connected';
    }
  }

  static Color _statusColor(Spo2Model s) {
    switch (s.status) {
      case 'OK':
        return Colors.green;
      case 'NO_FINGER':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<Spo2Provider>(
      builder: (context, provider, _) {
        final s = provider.spo2;

        if (s == null) {
          return Container(
            height: 150,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final valid = s.hasReading;
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
                            Icon(Icons.favorite_rounded, color: _accent),
                            SizedBox(width: 10),
                            Text(
                              'SpO2 & Pulse',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                          ],
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
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _BigValue(
                            label: 'SpO2',
                            value: valid ? '${s.spo2}' : '--',
                            unit: '%',
                            color: _accent,
                          ),
                        ),
                        Expanded(
                          child: _BigValue(
                            label: 'Pulse',
                            value: valid ? '${s.pulse}' : '--',
                            unit: 'bpm',
                            color: Colors.pink,
                          ),
                        ),
                        Expanded(
                          child: _BigValue(
                            label: 'PI',
                            value: (valid && s.pi != null) ? s.pi!.toStringAsFixed(1) : '--',
                            unit: '%',
                            color: Colors.deepPurple,
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
                    if (s.status == 'OK' || s.status == 'NO_FINGER') ...[
                      _SignalBars(level: s.signal),
                      const SizedBox(width: 12),
                    ],
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

class _BigValue extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _BigValue({required this.label, required this.value, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(width: 3),
              Text(unit, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// Signal strength 0-15 as four bars.
class _SignalBars extends StatelessWidget {
  final int level;
  const _SignalBars({required this.level});

  @override
  Widget build(BuildContext context) {
    final lit = (level.clamp(0, 15) / 15 * 4).ceil();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        return Container(
          width: 4,
          height: 5.0 + i * 3,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: i < lit ? Colors.green : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

class _Spo2SettingsSheet extends StatelessWidget {
  const _Spo2SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<Spo2Provider>();
    final s = provider.spo2;
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
                'SpO2 Alarms',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              Switch(
                value: s.monitoringEnabled,
                onChanged: (val) => provider.setMonitoring(val),
                activeColor: Colors.redAccent,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.monitoringEnabled
                ? 'On: alarms sound for low or high SpO2 and pulse, and when the probe comes off or the oximeter is unplugged.'
                : 'Off: readings are still shown, but no SpO2, pulse or probe alarms are raised. Turn this on once the probe is on the baby.',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text(
            'The alarm limits are set in Alarm Limits. SpO2 is for display and alarms only; it does not control the oxygen valve.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
