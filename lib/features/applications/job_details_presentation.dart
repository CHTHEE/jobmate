import 'package:flutter/material.dart';

import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../jobs/job_display.dart';
import 'job_marketplace_format.dart';
import 'module2_repository.dart';
import 'my_applications_repository.dart';

class JobInformationGrid extends StatelessWidget {
  const JobInformationGrid(this.job, {super.key});
  final BrowseJob job;
  @override
  Widget build(BuildContext context) => ResponsiveGrid(
    maxColumns: 2,
    minItemWidth: 240,
    spacing: 10,
    children: [
      for (final item in [
        (
          Icons.work_outline,
          'Employment type',
          jobLabel(job.text('employment_type')),
        ),
        (Icons.payments_outlined, 'Salary', marketplaceSalary(job)),
        (Icons.location_on_outlined, 'Location', job.text('location')),
        (
          Icons.business_center_outlined,
          'Work arrangement',
          jobLabel(job.text('work_arrangement')),
        ),
        (Icons.people_outline, 'Vacancies', job.text('vacancies')),
        (
          Icons.event_outlined,
          'Application deadline',
          marketplaceDate(job.fields['application_deadline']),
        ),
      ])
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: JobMateTheme.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.$1, size: 19, color: JobMateTheme.darkTeal),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$2,
                      style: const TextStyle(
                        fontSize: 12,
                        color: JobMateTheme.body,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.$3.isEmpty ? 'Not provided' : item.$3,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class JobApplicationBanner extends StatelessWidget {
  const JobApplicationBanner(this.status, {super.key});
  final MyApplicationStatus? status;
  @override
  Widget build(BuildContext context) {
    final hired = status == MyApplicationStatus.hired;
    final negative = status == MyApplicationStatus.rejected;
    final color = hired
        ? const Color(0xFF15803D)
        : negative
        ? const Color(0xFF9F1239)
        : JobMateTheme.darkTeal;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            hired
                ? Icons.check_circle_outline
                : negative
                ? Icons.info_outline
                : Icons.assignment_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hired
                      ? 'You were hired for this job'
                      : status == null
                      ? 'Application submitted'
                      : 'Application status: ${status!.label}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
                if (hired)
                  Text(
                    'Application status: ${status!.label}',
                    style: TextStyle(color: color, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lists remain lists; plain paragraphs are never split on sentence punctuation.
class JobContent extends StatelessWidget {
  const JobContent(this.value, {super.key});
  final Object? value;
  static bool hasContent(Object? value) => value is List
      ? value.whereType<String>().any((text) => text.trim().isNotEmpty)
      : value is String && value.trim().isNotEmpty;
  @override
  Widget build(BuildContext context) {
    final items = value is List
        ? (value as List)
              .whereType<String>()
              .where((text) => text.trim().isNotEmpty)
              .toList()
        : <String>[];
    if (items.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final text in items) _bullet(text)],
      );
    }
    final text = value is String ? value as String : '';
    final lines = text.split('\n');
    final marker = RegExp(r'^\s*([•●▪*-])\s+');
    if (lines.any((line) => marker.hasMatch(line))) {
      final children = <Widget>[];
      final paragraph = <String>[];
      void flushParagraph() {
        if (paragraph.any((line) => line.trim().isNotEmpty)) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                paragraph.join('\n'),
                style: const TextStyle(height: 1.6),
              ),
            ),
          );
        }
        paragraph.clear();
      }

      for (final line in lines) {
        if (marker.hasMatch(line)) {
          flushParagraph();
          children.add(_bullet(line.replaceFirst(marker, '')));
        } else {
          paragraph.add(line);
        }
      }
      flushParagraph();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return Text(text, style: const TextStyle(height: 1.6));
  }

  Widget _bullet(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7),
          child: Icon(Icons.circle, size: 5, color: JobMateTheme.darkTeal),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.6))),
      ],
    ),
  );
}

class JobDetailCard extends StatelessWidget {
  const JobDetailCard({super.key, required this.child, this.title});
  final Widget child;
  final String? title;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: JobMateTheme.divider),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
        ],
        child,
      ],
    ),
  );
}
