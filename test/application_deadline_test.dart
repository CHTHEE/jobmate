import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/jobs/application_deadline.dart';
import 'package:jobmate/features/jobs/job_validation.dart';

void main() {
  test('a date-only deadline includes the entire Malaysia calendar day', () {
    const deadline = '2026-11-27';
    final start = DateTime.utc(2026, 11, 26, 16);
    final end = DateTime.utc(2026, 11, 27, 16);
    expect(malaysiaApplicationDate(start), DateTime.utc(2026, 11, 27));
    expect(
      applicationDeadlineClosesAt(parseApplicationDeadline(deadline)!),
      end,
    );
    expect(
      applicationDeadlineState(deadline, start),
      ApplicationDeadlineState.open,
    );
    expect(
      applicationDeadlineState(
        deadline,
        end.subtract(const Duration(microseconds: 1)),
      ),
      ApplicationDeadlineState.open,
    );
    expect(
      applicationDeadlineState(deadline, end),
      ApplicationDeadlineState.expired,
    );
    expect(
      applicationDeadlineState('2026-11-26', start),
      ApplicationDeadlineState.expired,
    );
    expect(
      applicationDeadlineState('2026-11-28', start),
      ApplicationDeadlineState.open,
    );
  });

  test('missing, normalized and timestamp values fail closed', () {
    final now = DateTime.utc(2026, 11, 27);
    for (final value in [
      null,
      '',
      '2026-02-30',
      '2026-11-7',
      '2027-01-01T00:00:00Z',
    ]) {
      expect(
        applicationDeadlineState(value, now),
        ApplicationDeadlineState.unavailable,
      );
    }
    for (final status in ['published', 'draft', 'closed']) {
      final job = BrowseJob.published({
        'status': status,
        'application_deadline': '2026-11-28',
      });
      expect(job.unavailable(now) == null, status == 'published');
      expect(job.text('status'), status);
    }
  });

  test('employer publication keeps the existing future-date rule in MYT', () {
    final now = DateTime.utc(2026, 11, 26, 16);
    String? error(String date) => jobFieldError(
      'application_deadline',
      {'application_deadline': date},
      publishing: true,
      now: now,
    );
    expect(error('2026-11-26'), isNotNull);
    expect(error('2026-11-27'), isNotNull);
    expect(error('2026-11-28'), isNull);
    expect(error('2027-02-29'), isNotNull);
  });
}
