import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lid_provider.dart';
import '../utils/app_colors.dart';

/// Lid control: tap Open (the lid opens for 6 s) or Close (closes for 6 s).
/// Open stays disabled until the lid has been closed again, so the lid can
/// never be opened further than one Open step.
class LidCard extends StatefulWidget {
  const LidCard({super.key});

  @override
  State<LidCard> createState() => _LidCardState();
}

class _LidCardState extends State<LidCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LidProvider>().startMonitoring();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LidProvider>(
      builder: (context, provider, _) {
        final lid = provider.lid;
        final busy = provider.isSending;

        String status;
        Color statusColor;
        if (lid.isOpening) {
          status = 'OPENING';
          statusColor = Colors.green;
        } else if (lid.isClosing) {
          status = 'CLOSING';
          statusColor = Colors.orange;
        } else if (lid.isOpen) {
          status = 'OPEN';
          statusColor = AppColors.primary;
        } else {
          status = 'CLOSED';
          statusColor = Colors.grey;
        }

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
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.unfold_more_rounded, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Lid',
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
                      status,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _LidButton(
                      icon: Icons.keyboard_double_arrow_up_rounded,
                      label: 'OPEN',
                      onPressed: lid.canOpen && !busy ? provider.open : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LidButton(
                      icon: Icons.keyboard_double_arrow_down_rounded,
                      label: 'CLOSE',
                      onPressed: lid.canClose && !busy ? provider.close : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                lid.isOpen && !lid.isMoving
                    ? 'Close the lid before opening it again.'
                    : 'Tap once. The lid moves by itself and stops.',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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

class _LidButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _LidButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.offline,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
        ],
      ),
    );
  }
}
