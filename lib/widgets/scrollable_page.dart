import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Wraps [child] in a scrollable view with floating up/down arrow buttons
/// that scroll by tap.
///
/// Added for the Pi kiosk touchscreen: its drag/swipe gestures don't reach
/// Chromium (a labwc/Xwayland touch-forwarding issue — the kernel driver
/// reports clean motion events, but only tap-equivalent input arrives at
/// the browser), while taps work fine. These buttons make scrolling
/// possible using only taps, independent of whether that lower-level bug
/// ever gets fixed. See NEW_SCREEN_SETUP_GUIDE.md, Option B.
class ScrollablePage extends StatefulWidget {
  final Widget child;

  const ScrollablePage({super.key, required this.child});

  @override
  State<ScrollablePage> createState() => _ScrollablePageState();
}

class _ScrollablePageState extends State<ScrollablePage> {
  final ScrollController _controller = ScrollController();
  bool _canScrollUp = false;
  bool _canScrollDown = false;

  static const _scrollStep = 260.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrowVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrowVisibility());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateArrowVisibility);
    _controller.dispose();
    super.dispose();
  }

  void _updateArrowVisibility() {
    if (!_controller.hasClients) return;
    final canUp = _controller.offset > 0;
    final canDown = _controller.offset < _controller.position.maxScrollExtent;
    if (canUp != _canScrollUp || canDown != _canScrollDown) {
      setState(() {
        _canScrollUp = canUp;
        _canScrollDown = canDown;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + delta)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrowVisibility());
            return false;
          },
          child: SingleChildScrollView(
            controller: _controller,
            child: widget.child,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ScrollArrowButton(
                icon: Icons.keyboard_arrow_up_rounded,
                visible: _canScrollUp,
                onPressed: () => _scrollBy(-_scrollStep),
              ),
              const SizedBox(height: 10),
              _ScrollArrowButton(
                icon: Icons.keyboard_arrow_down_rounded,
                visible: _canScrollDown,
                onPressed: () => _scrollBy(_scrollStep),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScrollArrowButton extends StatelessWidget {
  final IconData icon;
  final bool visible;
  final VoidCallback onPressed;

  const _ScrollArrowButton({
    required this.icon,
    required this.visible,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: visible ? 1 : 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: FloatingActionButton(
          heroTag: null,
          mini: true,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          onPressed: onPressed,
          child: Icon(icon),
        ),
      ),
    );
  }
}
