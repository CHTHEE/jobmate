import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'work_completion_report_data.dart';
import 'work_completion_report_format.dart';

const _navy = Color(0xFF0F172A);
const _body = Color(0xFF1E293B);
const _slate = Color(0xFF475569);
const _teal = Color(0xFF0F766E);
const _border = Color(0xFFE2E8F0);
const _panel = Color(0xFFF8FAFC);
const _blue = Color(0xFF1E40AF);
const _bluePanel = Color(0xFFEFF6FF);
const _strong = TextStyle(fontWeight: FontWeight.w600);
const _secondary = TextStyle(color: _slate);

/// A continuous, report-only document. The toolbar and workspace live outside it.
class WorkCompletionReportDocument extends StatelessWidget {
  const WorkCompletionReportDocument({super.key, required this.data});

  final WorkCompletionReportData data;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('work-report-document'),
    decoration: const BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Color(0x180F172A),
          blurRadius: 20,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth >= 820
            ? 54.0
            : constraints.maxWidth >= 560
            ? 32.0
            : 16.0;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'Outfit',
              color: _body,
              fontSize: 14,
              height: 1.45,
            ),
            child: _content(constraints.maxWidth >= 620),
          ),
        );
      },
    ),
  );

  Widget _content(bool wide) {
    final report = WorkReportFormat(data);
    final start = report.start;
    final end = report.end;
    final verified = report.verified;
    final generated = report.generated;
    final completed = report.completed;
    final verification = report.verification;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Columns(
          children: [
            const _Brand(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SYSTEM-GENERATED REPORT',
                  textAlign: wide ? TextAlign.end : TextAlign.start,
                  style: _secondary.merge(_strong),
                ),
                Text(
                  'Generated: $generated',
                  textAlign: wide ? TextAlign.end : TextAlign.start,
                  style: _secondary,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(
            WorkReportFormat.title,
            style: TextStyle(
              color: _navy,
              fontFamily: 'DM Serif Display',
              fontSize: wide ? 38 : 28,
              height: 1.12,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(WorkReportFormat.introduction, style: _secondary),
        const SizedBox(height: 18),
        const Divider(height: 2, thickness: 2, color: _teal),
        _Section(
          'Job Information',
          LucideIcons.fileText,
          _Columns(
            children: [
              _Facts([
                ('Job Title', data.jobTitle),
                (
                  'Employment Type',
                  data.employmentTypeLabel ?? 'Not available',
                ),
                ('Work Date', report.workDates),
              ]),
              _Facts([
                ('Employer', data.companyName),
                ('Job Seeker', data.workerName ?? 'Not available'),
                ('Scheduled Work Location', data.workplaceLocation),
              ]),
            ],
          ),
        ),
        _Section(
          'Work Schedule',
          LucideIcons.clock,
          _Details([
            ('Scheduled Start', Text(start)),
            ('Scheduled End', Text(end)),
            ('Scheduled Duration', Text(report.scheduledDuration)),
          ]),
        ),
        _Section(
          'Attendance Information',
          LucideIcons.clock,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Details([
                (
                  'Check-in Time',
                  _lines([report.checkIn, report.checkInTiming]),
                ),
                (
                  'Check-out Time',
                  _lines([report.checkOut, report.checkOutTiming]),
                ),
                (
                  'Recorded Attendance Duration',
                  Text(report.recordedDuration, style: _strong),
                ),
                (
                  'Attendance Status',
                  _Status(
                    data.attendanceStatus,
                    information:
                        data.attendanceSource ==
                        ReportAttendanceSource.corrected,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _Columns(
                children: [
                  _Location('Check-in location', data.checkInLocation),
                  _Location('Check-out location', data.checkOutLocation),
                ],
              ),
            ],
          ),
        ),
        _Section(
          'Work Verification',
          LucideIcons.shieldCheck,
          _Details([
            ('Work Completion Status', _Status(completed)),
            (
              'Evidence Submission',
              _Status(report.submission, information: true),
            ),
            ('Evidence Files Submitted', Text(report.submittedFiles)),
            (
              'Evidence Description',
              _lines(
                data.submittedDescriptions.isEmpty
                    ? const ['Not recorded']
                    : data.submittedDescriptions,
              ),
            ),
            ('Employer Verification', _Status(verification)),
            ('Verification Date', Text(verified)),
            ('Verified By', Text(report.verifier)),
          ]),
        ),
        _Section(
          'Job Assignment Information',
          LucideIcons.calendar,
          _Details([
            ('Assignment Status', _Status(completed)),
            ('Scheduled Assignment Start', Text(start)),
            ('Scheduled Assignment End', Text(end)),
            ('Marked Complete at Verification', Text(verified)),
          ]),
        ),
        _Section(
          'Report Summary',
          LucideIcons.circleCheck,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Surface(
                color: _panel,
                child: _Columns(
                  minimum: 166,
                  separated: true,
                  children: [
                    _summary(
                      'Attendance',
                      _Status(
                        data.attendanceStatus,
                        information:
                            data.attendanceSource ==
                            ReportAttendanceSource.corrected,
                      ),
                      '${report.recordedDuration} recorded',
                    ),
                    _summary(
                      'Work completion',
                      _Status(completed),
                      report.submittedFiles,
                    ),
                    _summary('Verification', _Status(verification), verified),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const _Surface(
                color: _bluePanel,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.info, size: 18, color: _blue),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        WorkReportFormat.notice,
                        style: TextStyle(color: _blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Divider(height: 1, color: _border),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _BrandMark(size: 28),
            const SizedBox(width: 10),
            Expanded(child: _lines([WorkReportFormat.footer, generated])),
          ],
        ),
      ],
    );
  }

  static Widget _summary(String title, Widget status, String detail) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title.toUpperCase(), style: _secondary.merge(_strong)),
      const SizedBox(height: 6),
      status,
      const SizedBox(height: 6),
      Text(detail),
    ],
  );
}

Widget _lines(List<String> values) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (final (index, value) in values.indexed)
      Padding(
        padding: EdgeInsets.only(top: index == 0 ? 0 : 4),
        child: Text(value),
      ),
  ],
);

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _teal,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(LucideIcons.briefcase, color: Colors.white, size: size * .54),
  );
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      _BrandMark(size: 40),
      SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: 'Job',
                children: [
                  TextSpan(
                    text: 'Mate',
                    style: TextStyle(color: _teal),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 23,
                color: _navy,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'RECRUITMENT PLATFORM',
              style: TextStyle(color: _slate, fontSize: 11, letterSpacing: .8),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.icon, this.child);
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: _teal),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 16, color: _border),
        child,
      ],
    ),
  );
}

class _Columns extends StatelessWidget {
  const _Columns({
    required this.children,
    this.minimum = 198,
    this.separated = false,
  });
  final List<Widget> children;
  final double minimum;
  final bool separated;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final horizontal =
          constraints.maxWidth >= (minimum * scale + 16) * children.length;
      if (!horizontal) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0)
                separated
                    ? const Divider(height: 24, color: _border)
                    : const SizedBox(height: 12),
              child,
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0)
              separated
                  ? const SizedBox(
                      height: 48,
                      width: 24,
                      child: VerticalDivider(color: _border),
                    )
                  : const SizedBox(width: 16),
            Expanded(child: child),
          ],
        ],
      );
    },
  );
}

class _Facts extends StatelessWidget {
  const _Facts(this.rows);
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (label, value) in rows) ...[
        Text(label, style: _secondary),
        Text(value, style: _strong),
        const Divider(height: 16, color: _border),
      ],
    ],
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: child,
  );
}

class _Details extends StatelessWidget {
  const _Details(this.rows);
  final List<(String, Widget)> rows;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Table(
      border: TableBorder(
        borderRadius: BorderRadius.circular(10),
        top: const BorderSide(color: _border),
        bottom: const BorderSide(color: _border),
        left: const BorderSide(color: _border),
        right: const BorderSide(color: _border),
        horizontalInside: const BorderSide(color: _border),
      ),
      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(2)},
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
          children: [
            _cell(const Text('ITEM', style: _strong)),
            _cell(const Text('DETAILS', style: _strong)),
          ],
        ),
        for (final (label, value) in rows)
          TableRow(
            decoration: const BoxDecoration(color: _panel),
            children: [
              _cell(Text(label, style: _secondary)),
              _cell(value),
            ],
          ),
      ],
    ),
  );
  Widget _cell(Widget value) =>
      Padding(padding: const EdgeInsets.all(10), child: value);
}

class _Status extends StatelessWidget {
  const _Status(this.label, {this.information = false});
  final String label;
  final bool information;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: information ? _bluePanel : const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: information ? _blue : const Color(0xFF166534),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class _Location extends StatelessWidget {
  const _Location(this.title, this.location);
  final String title;
  final ReportAttendanceLocation location;
  @override
  Widget build(BuildContext context) => _Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.mapPin, size: 16, color: _teal),
            const SizedBox(width: 8),
            Expanded(child: Text(title.toUpperCase(), style: _strong)),
          ],
        ),
        const SizedBox(height: 6),
        _lines(WorkReportFormat.location(location)),
      ],
    ),
  );
}
