import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Small reusable loading indicator used inside cards while their
/// first data fetch is in flight.
class LoadingWidget extends StatelessWidget {
  final double size;

  const LoadingWidget({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(
        strokeWidth: 3,
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
      ),
    );
  }
}