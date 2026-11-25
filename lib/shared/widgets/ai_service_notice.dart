import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/jobmate_theme.dart';

class AiServiceNotice extends StatelessWidget {
  const AiServiceNotice({
    super.key,
    required this.title,
    required this.message,
    this.actions,
  });

  final String title, message;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JobMateTheme.space12),
      decoration: BoxDecoration(
        color: JobMateTheme.teal50,
        border: Border.all(color: JobMateTheme.teal100),
        borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  LucideIcons.info,
                  size: 18,
                  color: JobMateTheme.teal800,
                ),
                const SizedBox(width: JobMateTheme.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: JobMateTheme.space4),
                      Text(message, style: text.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (actions case final controls?) ...[
            const SizedBox(height: JobMateTheme.space8),
            controls,
          ],
        ],
      ),
    );
  }
}
