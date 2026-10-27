import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/alarm_provider.dart';
import '../utils/app_colors.dart';

/// Editor for the alarm thresholds stored on the Pi.
///
/// Each measurement is a low/high pair, so these use a [RangeSlider]
/// rather than two independent sliders — it makes the alarm *band*
/// visible as one thing and stops the low limit being dragged above the
/// high one, which the backend would otherwise accept as a permanently
/// unsatisfiable pair.
class AlarmLimitsSheet extends StatefulWidget {
  const AlarmLimitsSheet({super.key});

  @override
  State<AlarmLimitsSheet> createState() => _AlarmLimitsSheetState();
}

class _AlarmLimitsSheetState extends State<AlarmLimitsSheet> {
  Map<String, double>? _draft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlarmProvider>().loadLimits();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlarmProvider>();
    final limits = provider.limits;

    if (limits == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Seeded once so the sliders don't jump under the operator's finger
    // when a poll refreshes the underlying values mid-edit.
    _draft ??= Map<String, double>.from(limits);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
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
            const Text(
              'Alarm Limits',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'An alarm is raised once a reading stays outside these bands '
              'for 10 continuous seconds.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            _buildBand(
              title: 'Air Temperature',
              unit: '°C',
              lowKey: 'air_temp_low',
              highKey: 'air_temp_high',
              min: 15,
              max: 45,
              color: Colors.orange,
            ),
            const SizedBox(height: 18),
            _buildBand(
              title: 'Humidity',
              unit: '%',
              lowKey: 'humidity_low',
              highKey: 'humidity_high',
              min: 0,
              max: 100,
              color: Colors.blue,
            ),
            const SizedBox(height: 18),
            _buildBand(
              title: 'Oxygen Concentration',
              unit: '%',
              lowKey: 'o2_low',
              highKey: 'o2_high',
              min: 10,
              max: 60,
              color: Colors.teal,
            ),
            const SizedBox(height: 18),
            _buildBand(
              title: 'SpO2',
              unit: '%',
              lowKey: 'spo2_low',
              highKey: 'spo2_high',
              min: 70,
              max: 100,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 18),
            _buildBand(
              title: 'Pulse Rate',
              unit: 'bpm',
              lowKey: 'pulse_low',
              highKey: 'pulse_high',
              min: 40,
              max: 250,
              color: Colors.pink,
            ),
            const SizedBox(height: 18),
            _buildBand(
              title: 'Skin Temperature',
              unit: '°C',
              lowKey: 'skin_temp_low',
              highKey: 'skin_temp_high',
              min: 32,
              max: 40,
              color: Colors.deepOrange,
            ),
            const SizedBox(height: 6),
            const Text(
              'SpO2, pulse and skin temperature alarms only sound while Alarms is switched on in their card.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (provider.lastErrorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                provider.lastErrorMessage!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  provider.updateLimits(_draft!);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Limits',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBand({
    required String title,
    required String unit,
    required String lowKey,
    required String highKey,
    required double min,
    required double max,
    required Color color,
  }) {
    final low = (_draft![lowKey] ?? min).clamp(min, max);
    final high = (_draft![highKey] ?? max).clamp(min, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              '${low.toStringAsFixed(1)} – ${high.toStringAsFixed(1)} $unit',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 14,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.2),
            inactiveTrackColor: color.withValues(alpha: 0.12),
            rangeThumbShape:
                const RoundRangeSliderThumbShape(enabledThumbRadius: 9),
          ),
          child: RangeSlider(
            values: RangeValues(low, high),
            min: min,
            max: max,
            onChanged: (values) => setState(() {
              _draft![lowKey] =
                  double.parse(values.start.toStringAsFixed(1));
              _draft![highKey] =
                  double.parse(values.end.toStringAsFixed(1));
            }),
          ),
        ),
      ],
    );
  }
}
