import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/alarm_provider.dart';
import '../utils/app_colors.dart';

/// How long SOS (and cancelling it) must be held. Long enough that a brush
/// against the touchscreen or a pocketed phone cannot trigger it, short
/// enough for someone who needs help now.
const Duration sosHoldDuration = Duration(seconds: 2);

const Color _sosRed = Color(0xFFB71C1C);

/// Runs [onConfirmed] only after the press has been held for [holdFor].
/// Releasing early resets it and shows [hint], so a plain tap explains
/// itself instead of seeming to do nothing.
class HoldToConfirm extends StatefulWidget {
  final Duration holdFor;
  final VoidCallback? onConfirmed;
  final String hint;
  final Widget Function(BuildContext context, double progress) builder;

  const HoldToConfirm({
    super.key,
    this.holdFor = sosHoldDuration,
    required this.onConfirmed,
    required this.hint,
    required this.builder,
  });

  @override
  State<HoldToConfirm> createState() => _HoldToConfirmState();
}

class _HoldToConfirmState extends State<HoldToConfirm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold;

  @override
  void initState() {
    super.initState();
    _hold = AnimationController(vsync: this, duration: widget.holdFor)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          HapticFeedback.heavyImpact();
          widget.onConfirmed?.call();
          _hold.reset();
        }
      });
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _release() {
    if (!_hold.isAnimating) return;
    _hold.reset();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(widget.hint),
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onConfirmed != null;
    // Tap callbacks (not raw pointer events) so that a scroll that starts on
    // the button cancels the hold instead of counting towards it.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _hold.forward(from: 0) : null,
      onTapUp: enabled ? (_) => _release() : null,
      onTapCancel: enabled ? _release : null,
      child: AnimatedBuilder(
        animation: _hold,
        builder: (context, _) => widget.builder(context, _hold.value),
      ),
    );
  }
}

Future<void> _sendSos(BuildContext context, bool active) async {
  final provider = context.read<AlarmProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final ok = await provider.setSos(active);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: ok ? null : _sosRed,
      content: Text(ok
          ? (active
              ? 'SOS sent. The incubator is sounding and every screen shows it.'
              : 'SOS cancelled.')
          : (provider.lastErrorMessage ?? 'Could not reach the incubator.')),
      duration: Duration(seconds: ok ? 4 : 8),
    ));
}

/// Round red SOS button for the shared header, so it is on every screen.
/// Hold for [sosHoldDuration] to raise SOS; once raised it shows as sent,
/// and is cancelled from the SOS banner.
class SosHeaderButton extends StatelessWidget {
  const SosHeaderButton({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlarmProvider>();
    final active = provider.alarms.sosActive;
    final busy = provider.isSendingSos;

    return Semantics(
      button: true,
      label: active ? 'SOS sent' : 'SOS. Hold for two seconds to call for help',
      child: HoldToConfirm(
        onConfirmed: active || busy ? null : () => _sendSos(context, true),
        hint: 'Hold SOS for 2 seconds to call for help.',
        builder: (context, progress) => SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? Colors.white : _sosRed,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(
                        active ? 'SENT' : 'SOS',
                        style: TextStyle(
                          color: active ? _sosRed : Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: active ? 12 : 16,
                          letterSpacing: 1,
                        ),
                      ),
              ),
              if (progress > 0)
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width SOS banner, mounted in MainScreen above the alarm banner so
/// it shows on every tab and cannot be scrolled away. Anyone on any screen
/// can cancel it, with the same hold as raising it.
class SosBanner extends StatefulWidget {
  const SosBanner({super.key});

  @override
  State<SosBanner> createState() => _SosBannerState();
}

class _SosBannerState extends State<SosBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static String _ago(DateTime? since) {
    if (since == null) return '';
    final m = DateTime.now().difference(since).inMinutes;
    if (m < 1) return 'just now';
    if (m < 60) return '$m min ago';
    return '${m ~/ 60} h ${m % 60} min ago';
  }

  static String _where(String? from) {
    switch (from) {
      case 'kiosk':
        return 'from the incubator screen';
      case 'phone':
        return 'from a phone';
      case 'web':
        return 'from the website';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlarmProvider>();
    final alarms = provider.alarms;
    if (!alarms.sosActive) return const SizedBox.shrink();

    final detail = [_where(alarms.sosFrom), _ago(alarms.sosSince)]
        .where((s) => s.isNotEmpty)
        .join(' · ');

    return SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Container(
          color: Color.lerp(_sosRed, AppColors.alarmHigh, _pulse.value),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              const Icon(Icons.sos_rounded, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'SOS: help needed at the incubator',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        'Raised $detail',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              HoldToConfirm(
                onConfirmed: provider.isSendingSos
                    ? null
                    : () => _sendSos(context, false),
                hint: 'Hold "Cancel SOS" for 2 seconds to cancel it.',
                builder: (context, progress) => ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: const [Colors.white, Colors.white, Colors.white70, Colors.white70],
                        stops: [0, progress, progress, 1],
                      ),
                    ),
                    child: const Text(
                      'Hold to cancel',
                      style: TextStyle(
                        color: _sosRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
