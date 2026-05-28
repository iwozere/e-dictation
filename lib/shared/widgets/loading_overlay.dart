import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Wraps [child] and shows a semi-transparent loading overlay when [isLoading].
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key, required this.child, required this.isLoading});

  final Widget child;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          const ModalBarrier(dismissible: false, color: Colors.black26),
        if (isLoading)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          ),
      ],
    );
  }
}
