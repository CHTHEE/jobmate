import 'job_display.dart';

const jobBulletFields = ['responsibilities', 'requirements', 'benefits'];
const jobRequiredFields = [
  'title',
  'department',
  'employment_type',
  'work_arrangement',
  'location',
  'salary_min',
  'salary_max',
  'salary_period',
  'vacancies',
  'application_deadline',
  'original_description',
  'role_overview',
  ...jobBulletFields,
];

String? jobFieldError(
  String key,
  Map<String, dynamic> job, {
  required bool publishing,
}) {
  final text = '${job[key] ?? ''}'.trim();
  if (publishing && jobBulletFields.contains(key)) {
    final value = job[key];
    if (value is! List ||
        !value.any((v) => v is String && v.trim().isNotEmpty)) {
      return 'Add at least one ${jobLabel(key).toLowerCase()} bullet point.';
    }
    return null;
  }
  if (text.isEmpty) {
    if (publishing || key == 'title') {
      return 'Enter ${jobLabel(key).toLowerCase()}.';
    }
    return null;
  }
  if (key == 'vacancies' &&
      (int.tryParse(text) == null || int.parse(text) <= 0)) {
    return 'Enter a positive whole number of vacancies.';
  }
  if (key == 'salary_min' || key == 'salary_max') {
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value < 0) {
      return 'Enter a valid non-negative salary.';
    }
    final min = double.tryParse('${job['salary_min']}');
    if (key == 'salary_max' && min != null && value < min) {
      return 'Maximum salary must be at least the minimum.';
    }
  }
  if (key == 'application_deadline') {
    final date = DateTime.tryParse(text);
    if (date == null || jobDate(date) != text) {
      return 'Use a valid date in YYYY-MM-DD format.';
    }
    final now = DateTime.now();
    if (publishing && !date.isAfter(DateTime(now.year, now.month, now.day))) {
      return 'Choose a future application deadline.';
    }
  }
  return null;
}

Map<String, String> jobPublicationErrors(Map<String, dynamic> job) => {
  for (final key in jobRequiredFields)
    if (jobFieldError(key, job, publishing: true) case final String error)
      key: error,
  if (job['salary_visible'] is! bool)
    'salary_visible': 'Choose whether to show salary.',
};

String? jobPublishError(Map<String, dynamic> job) =>
    jobPublicationErrors(job).values.firstOrNull;
