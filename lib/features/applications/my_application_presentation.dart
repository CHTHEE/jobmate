import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/theme/jobmate_theme.dart';
import 'compensation_offer.dart';
import 'module2_widgets.dart';
import 'my_applications_repository.dart';

String applicationStatusDescription(MyApplicationStatus status) =>
    switch (status) {
      MyApplicationStatus.submitted => 'Application submitted.',
      MyApplicationStatus.shortlisted =>
        'The employer shortlisted your application.',
      MyApplicationStatus.interview =>
        'Your application reached the interview stage.',
      MyApplicationStatus.offered =>
        'Open the application to review your offer.',
      MyApplicationStatus.hired => 'You have been hired for this job.',
      MyApplicationStatus.rejected =>
        'The employer did not move this application forward.',
      MyApplicationStatus.declined => 'You declined the offer.',
      MyApplicationStatus.withdrawn => 'You withdrew this application.',
    };

String applicationDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String applicationDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  return '${applicationDate(local)}, ${TimeOfDay.fromDateTime(local).format(context)}';
}

String applicationOfferAmount(CompensationOffer offer) {
  final currency = offer.currency == 'MYR' ? 'RM' : offer.currency;
  final min = offer.minimumSen;
  final max = offer.maximumSen;
  String amount(BigInt sen) {
    final digits = sen.toString().padLeft(3, '0');
    final point = digits.length - 2;
    return '${digits.substring(0, point)}.${digits.substring(point)}';
  }

  if (min == null) return 'Up to $currency ${amount(max!)}';
  if (max == null) return 'From $currency ${amount(min)}';
  if (min == max) return '$currency ${amount(min)}';
  return '$currency ${amount(min)} – ${amount(max)}';
}

String applicationOfferPeriod(String period) => switch (period) {
  'hourly' => 'Per hour',
  'daily' => 'Per day',
  'weekly' => 'Per week',
  'monthly' => 'Per month',
  'yearly' => 'Per year',
  _ => period,
};

class ApplicationIconTile extends StatelessWidget {
  const ApplicationIconTile(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: JobMateTheme.teal50,
      borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
    ),
    child: Icon(icon, color: JobMateTheme.darkTeal, size: 18),
  );
}

class MyApplicationIdentity extends StatelessWidget {
  const MyApplicationIdentity({
    super.key,
    required this.application,
    required this.titleStyle,
  });

  final MyJobApplication application;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ApplicationIconTile(LucideIcons.briefcase),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(application.jobTitle, style: titleStyle),
              const SizedBox(height: 4),
              Text(
                application.companyName,
                style: const TextStyle(color: JobMateTheme.body),
              ),
            ],
          ),
        ),
      ],
    );
    final badge = MyApplicationStatusBadge(application.status);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 320 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [identity, const SizedBox(height: 8), badge],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: identity),
            const SizedBox(width: 12),
            badge,
          ],
        );
      },
    );
  }
}
