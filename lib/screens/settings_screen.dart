import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/alarm_limits_sheet.dart';
import '../widgets/custom_header.dart';
import '../widgets/scrollable_page.dart';
import '../utils/app_colors.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _launchUrl(BuildContext context, String url, String title, String message) async {
    final Uri uri = Uri.parse(url);

    // Show confirmation dialog
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text("Proceed"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not launch application")),
          );
        }
      }
    }
  }

  void _showAlarmLimits(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) => const AlarmLimitsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScrollablePage(
      child: Column(
        children: [
          const CustomHeader(
            title: "Settings",
            subtitle: "App Configuration & Support",
            icon: Icons.settings_rounded,
          ),

          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader("Alarms"),
                _buildSettingTile(
                  icon: Icons.tune_rounded,
                  title: "Alarm Limits",
                  subtitle: "Temperature, humidity and oxygen thresholds",
                  onTap: () => _showAlarmLimits(context),
                ),

                const SizedBox(height: 24),

                _buildSectionHeader("General"),
                _buildSettingTile(
                  icon: Icons.notifications_active_outlined,
                  title: "Notifications",
                  subtitle: "Manage alert preferences",
                  onTap: () {},
                ),
                _buildSettingTile(
                  icon: Icons.lock_outline_rounded,
                  title: "Privacy & Security",
                  subtitle: "Data and connectivity settings",
                  onTap: () {},
                ),

                const SizedBox(height: 24),

                _buildSectionHeader("Help & Support"),
                _buildSettingTile(
                  icon: Icons.email_outlined,
                  title: "Email Us",
                  subtitle: "kanojiarahul812006@gmail.com",
                  onTap: () => _launchUrl(
                    context,
                    'mailto:kanojiarahul812006@gmail.com',
                    "Send Email",
                    "Would you like to open your email app to contact support?",
                  ),
                ),
                _buildSettingTile(
                  icon: Icons.phone_outlined,
                  title: "Call Us",
                  subtitle: "+91 9812988752",
                  onTap: () => _launchUrl(
                    context,
                    'tel:9812988752',
                    "Make a Call",
                    "Would you like to open the dialer to call support?",
                  ),
                ),

                const SizedBox(height: 24),

                _buildSectionHeader("App Information"),
                _buildSettingTile(
                  icon: Icons.info_outline_rounded,
                  title: "Version",
                  subtitle: "1.0.0 (Build 1)",
                  onTap: null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        trailing: onTap != null
            ? const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.divider)
            : null,
        onTap: onTap,
      ),
    );
  }
}
