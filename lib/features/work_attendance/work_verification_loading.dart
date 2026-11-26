import 'package:flutter/material.dart';

import '../../shared/theme/jobmate_theme.dart';

class WorkVerificationLoading extends StatelessWidget {
  const WorkVerificationLoading({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: JobMateTheme.darkTeal,
            semanticsLabel: 'Loading work verification',
          ),
          const SizedBox(height: 16),
          Text(
            'Loading work verification...',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
