import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import '../utils/app_colors.dart';

/// Phototherapy light: one button switches the light's relay on or off.
class PhotoCard extends StatefulWidget {
  const PhotoCard({super.key});

  @override
  State<PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<PhotoCard> {
  static const Color _accent = Colors.blue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PhotoProvider>().startMonitoring();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PhotoProvider>(
      builder: (context, provider, _) {
        final on = provider.photo.isOn;
        final busy = provider.isSending;
        final statusColor = on ? _accent : Colors.grey;

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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.light_mode_rounded, color: _accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Phototherapy',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      on ? 'ON' : 'OFF',
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: busy ? null : (on ? provider.turnOff : provider.turnOn),
                  icon: Icon(on ? Icons.power_settings_new_rounded : Icons.light_mode_rounded, size: 22),
                  label: Text(
                    on ? 'TURN OFF' : 'TURN ON',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: on ? _accent : AppColors.background,
                    foregroundColor: on ? Colors.white : _accent,
                    disabledForegroundColor: AppColors.offline,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'The light stays off after a restart. Turn it on once the baby is under it.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              if (provider.lastErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    provider.lastErrorMessage!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
