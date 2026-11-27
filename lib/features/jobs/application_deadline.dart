/// Date-only deadline values are compared as calendar dates, independent of
/// the device time zone. Malaysia observes UTC+08:00 throughout the year.
enum ApplicationDeadlineState { open, expired, unavailable }

const _malaysiaOffset = Duration(hours: 8);

DateTime malaysiaApplicationDate(DateTime instant) {
  final local = instant.toUtc().add(_malaysiaOffset);
  return DateTime.utc(local.year, local.month, local.day);
}

DateTime applicationDeadlineClosesAt(DateTime deadlineDate) =>
    deadlineDate.add(const Duration(days: 1)).subtract(_malaysiaOffset);

DateTime? parseApplicationDeadline(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null ||
      parsed.year < 1 ||
      parsed.toIso8601String().substring(0, 10) != value) {
    return null;
  }
  return parsed;
}

ApplicationDeadlineState applicationDeadlineState(Object? value, DateTime now) {
  final deadline = parseApplicationDeadline(value);
  if (deadline == null) return ApplicationDeadlineState.unavailable;
  return deadline.isBefore(malaysiaApplicationDate(now))
      ? ApplicationDeadlineState.expired
      : ApplicationDeadlineState.open;
}

const expiredApplicationMessage = 'Application deadline has passed.';
const noNewApplicationsMessage =
    'This job is no longer accepting new applications.';
