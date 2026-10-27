import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/alarm_model.dart';
import '../providers/alarm_provider.dart';
import '../utils/app_colors.dart';

Color alarmColorFor(AlarmPriority priority) {
  switch (priority) {
    case AlarmPriority.high:
      return AppColors.alarmHigh;
    case AlarmPriority.medium:
      return AppColors.alarmMedium;
    case AlarmPriority.low:
      return AppColors.alarmLow;
  }
}

String alarmPriorityLabel(AlarmPriority priority) {
  switch (priority) {
    case AlarmPriority.high:
      return 'HIGH';
    case AlarmPriority.medium:
      return 'MEDIUM';
    case AlarmPriority.low:
      return 'LOW';
  }
}

/// Always-visible alarm banner, mounted once in MainScreen above the
/// PageView rather than inside any individual screen.
///
/// That placement is deliberate: the three screens each scroll
/// independently, so a banner placed inside one of them would scroll out
/// of view and would only exist on that tab. An alarm must not be
/// missable because the operator happened to be on the Monitoring tab or
/// had scrolled down. Collapses to zero height when nothing is raised,
/// so it costs no screen space on a display this small.
class AlarmBanner extends StatefulWidget {
  const AlarmBanner({super.key});

  @override
  State<AlarmBanner> createState() => _AlarmBannerState();
}

class _AlarmBannerState extends State<AlarmBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlarmProvider>().startMonitoring();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _showAlarmSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) => const AlarmDetailSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AlarmProvider>(
      builder: (context, provider, _) {
        final alarms = provider.alarms;
        if (alarms.isEmpty) return const SizedBox.shrink();

        final priority = alarms.highestPriority ?? AlarmPriority.low;
        final color = alarmColorFor(priority);
        // Backend sorts by descending priority, so the first item is the
        // most urgent one worth naming in the collapsed banner.
        final top = alarms.items.first;
        final extra = alarms.items.length - 1;

        // Only a still-sounding HIGH alarm pulses. A silenced or lower
        // priority alarm stays steady — once acknowledged it should remain
        // visible without continuing to grab the eye.
        final shouldPulse =
            alarms.sounding && alarms.soundingPriority == AlarmPriority.high;

        return SafeArea(
          bottom: false,
          child: Material(
            color: color,
            child: InkWell(
              onTap: () => _showAlarmSheet(context),
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) => Opacity(
                  opacity: shouldPulse ? 0.72 + _pulseController.value * 0.28 : 1.0,
                  child: child,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              extra > 0 ? '${top.label}  (+$extra more)' : top.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              alarms.sounding
                                  ? '${alarmPriorityLabel(priority)} · tap to acknowledge'
                                  : '${alarmPriorityLabel(priority)} · silenced',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (!alarms.sounding)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.volume_off_rounded,
                              color: Colors.white70, size: 18),
                        ),
                      const Icon(Icons.chevron_right_rounded,
                          color: Colors.white70, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Full alarm list, opened by tapping the banner. Shows every raised
/// alarm — including ones whose condition has already cleared but which
/// haven't been acknowledged yet — with per-alarm and bulk acknowledge.
class AlarmDetailSheet extends StatelessWidget {
  const AlarmDetailSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlarmProvider>();
    final items = provider.alarms.items;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
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
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Alarms',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (items.isNotEmpty)
                    TextButton.icon(
                      onPressed: provider.isAcknowledging
                          ? null
                          : () => provider.acknowledge(),
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: const Text('Acknowledge all'),
                    ),
                ],
              ),
              if (provider.lastErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    provider.lastErrorMessage!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'No alarms',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => _AlarmTile(
                          item: items[index],
                          onAcknowledge: provider.isAcknowledging
                              ? null
                              : () => provider.acknowledge(id: items[index].id),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AlarmTile extends StatelessWidget {
  final AlarmItem item;
  final VoidCallback? onAcknowledge;

  const _AlarmTile({required this.item, required this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    final color = alarmColorFor(item.priority);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 42,
            decoration: BoxDecoration(
              // A cleared alarm keeps its slot but loses its colour, so a
              // still-happening alarm is distinguishable at a glance from
              // one that's merely awaiting acknowledgement.
              color: item.active ? color : AppColors.offline,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      alarmPriorityLabel(item.priority),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 0.6,
                      ),
                    ),
                    if (!item.active)
                      const Text(
                        '  ·  CLEARED',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 0.6,
                        ),
                      ),
                    if (item.acknowledged) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.volume_off_rounded,
                          size: 13, color: AppColors.textSecondary),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.formattedValue}   ·   ${item.ageLabel}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!item.acknowledged)
            IconButton(
              tooltip: 'Acknowledge',
              onPressed: onAcknowledge,
              icon: const Icon(Icons.check_circle_outline_rounded),
              color: color,
            ),
        ],
      ),
    );
  }
}
