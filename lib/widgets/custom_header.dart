import 'package:flutter/material.dart';
import '../services/system_service.dart';
import '../utils/api_constants.dart';
import '../utils/app_colors.dart';
import 'sos_button.dart';

class CustomHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const CustomHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  // Deliberately hidden rather than a visible button: this is a clinical
  // device, and an obvious "exit app" control risks an accidental tap from
  // staff or a visitor. A long-press on the header icon (present on every
  // screen, since CustomHeader is shared) is unlikely to happen by
  // accident, and still requires an explicit confirmation before it does
  // anything.
  Future<void> _handleExitKioskLongPress(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit to Raspberry Pi Desktop?'),
        content: const Text(
          'This closes the monitoring app and shows the Pi\'s desktop '
          '(e.g. to change Wi-Fi). Sensors and camera keep running in the '
          'background. To come back, use the "Return to Syncubator Kiosk" '
          'icon on the Pi\'s desktop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    if (ApiConstants.useMockData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not available in demo mode')),
      );
      return;
    }

    final service = SystemService();
    try {
      await service.exitKiosk();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not exit kiosk: $e')),
        );
      }
    } finally {
      service.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            // Kiosk-only: on the public site or the phone app a long-press
            // does nothing (see ApiConstants.isKioskDisplay).
            onLongPress: ApiConstants.isKioskDisplay
                ? () => _handleExitKioskLongPress(context)
                : null,
            child: CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: Icon(
                icon,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),

          const SizedBox(width: 18),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Replaces a notifications icon that had no action. Hold-to-send,
          // see SosHeaderButton.
          const SosHeaderButton(),
        ],
      ),
    );
  }
}