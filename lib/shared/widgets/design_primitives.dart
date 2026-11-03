import 'package:flutter/material.dart';

import '../theme/jobmate_theme.dart';
import 'responsive_layout.dart';

/// A visual summary only: callers own the score, provenance and explanation.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.value,
    required this.label,
    this.size = 96,
  });
  final int value;
  final String label;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value out of 100',
    child: SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: value.clamp(0, 100) / 100,
              strokeWidth: 7,
              backgroundColor: JobMateTheme.teal100,
              color: JobMateTheme.teal,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontFamily: 'DM Mono',
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: JobMateTheme.body),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.title,
    required this.description,
    this.eyebrow,
    this.actions = const [],
    this.fontSize = 20,
  });
  final String title, description;
  final String? eyebrow;
  final List<Widget> actions;
  final double fontSize;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: LayoutBuilder(
      builder: (context, box) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              Text(
                eyebrow!.toUpperCase(),
                style: const TextStyle(
                  color: JobMateTheme.darkTeal,
                  fontSize: 11,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontSize: fontSize, height: 1.4),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(color: JobMateTheme.body, height: 1.6),
              ),
            ],
          ],
        );
        if (ResponsiveLayout.isCompactWidth(box.maxWidth)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(spacing: 12, runSpacing: 12, children: actions),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heading),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 24),
              Flexible(
                child: Wrap(spacing: 12, runSpacing: 12, children: actions),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.note,
    this.color = JobMateTheme.darkTeal,
    this.valueSize = 24,
  });
  final String label, value;
  final IconData icon;
  final String? note;
  final Color color;
  final double valueSize;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 220;
      return Container(
        padding: EdgeInsets.all(compact ? 16 : 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JobMateTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!compact)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                if (!compact) const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: JobMateTheme.body,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (compact) ...[
                  const SizedBox(width: 6),
                  Icon(icon, color: color, size: 18),
                ],
              ],
            ),
            SizedBox(height: compact ? 10 : 16),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'DM Mono',
                fontFamilyFallback: const ['Consolas', 'monospace'],
                fontSize: valueSize,
                fontWeight: FontWeight.w600,
                color: JobMateTheme.heading,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(
                note!,
                style: const TextStyle(color: JobMateTheme.body, fontSize: 12),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      ResponsiveGrid(minItemWidth: 140, maxColumns: 4, children: children);
}

class BrandPanel extends StatelessWidget {
  const BrandPanel({
    super.key,
    required this.title,
    required this.description,
    this.child,
    this.icon = Icons.auto_awesome_outlined,
  });
  final String title, description;
  final Widget? child;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF134E4A), Color(0xFF0F766E)],
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF5EEAD4)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'DM Serif Display',
                      fontFamilyFallback: ['Georgia', 'serif'],
                      fontSize: 20,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFFCCFBF1),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (child != null) ...[
          const SizedBox(height: 20),
          Theme(
            data: Theme.of(context).copyWith(
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF5EEAD4)),
                ),
              ),
            ),
            child: child!,
          ),
        ],
      ],
    ),
  );
}

class FormSectionHeading extends StatelessWidget {
  const FormSectionHeading(
    this.title,
    this.description, {
    super.key,
    this.icon = Icons.notes_outlined,
  });
  final String title, description;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(icon, color: JobMateTheme.darkTeal, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(color: JobMateTheme.body, height: 1.5),
        ),
      ],
    ),
  );
}

class ProfileHeading extends StatelessWidget {
  const ProfileHeading({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.trailing,
    this.avatar,
  });
  final String title, description;
  final IconData icon;
  final Widget? trailing;
  final Widget? avatar;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 24),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: JobMateTheme.divider),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  avatar ?? Icon(icon, color: JobMateTheme.darkTeal, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      color: JobMateTheme.body,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (trailing != null) ...[const SizedBox(height: 16), trailing!],
      ],
    ),
  );
}

class PreviewNotice extends StatelessWidget {
  const PreviewNotice(
    this.message, {
    super.key,
    this.note = 'Session only • resets on refresh/account change. No server persistence or uploads.',
  });
  final String message, note;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFDE68A)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.science_outlined, color: Color(0xFF92400E), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'DEMO / PREVIEW',
                style: TextStyle(
                  color: Color(0xFF92400E),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF78350F),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                note,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: Color(0xFF92400E),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
