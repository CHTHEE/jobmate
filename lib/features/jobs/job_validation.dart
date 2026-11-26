import 'job_display.dart';

const jobCompensationPolicy = {
  'full_time': (periods: ['monthly', 'yearly'], defaultPeriod: 'monthly'),
  'part_time': (periods: ['hourly', 'daily'], defaultPeriod: 'hourly'),
  'contract': (periods: ['monthly', 'yearly'], defaultPeriod: 'monthly'),
  'internship': (periods: ['monthly'], defaultPeriod: 'monthly'),
  'temporary': (periods: ['hourly', 'daily'], defaultPeriod: 'daily'),
};

String jobSalaryPeriodHelp(String employmentType) {
  final periods = jobCompensationPolicy[employmentType]?.periods;
  if (periods == null) return 'Choose a supported employment type.';
  final rates = periods.map((period) => jobLabel(period).toLowerCase());
  return periods.length == 1
      ? '${jobLabel(employmentType)} jobs use a ${rates.single} compensation rate.'
      : '${jobLabel(employmentType)} jobs support ${rates.join(' or ')} pay.';
}

String? jobSalaryPeriodError(String employmentType, String salaryPeriod) {
  final policy = jobCompensationPolicy[employmentType];
  if (policy == null) return 'Choose a supported employment type.';
  if (salaryPeriod.isEmpty || policy.periods.contains(salaryPeriod)) {
    return null;
  }
  return 'Choose a compatible salary period. ${jobSalaryPeriodHelp(employmentType)}';
}

String? jobSalaryHint(String employmentType, String period, String field) {
  final examples = switch (period) {
    'hourly' => (12, 18),
    'daily' => (100, 150),
    'monthly' when employmentType == 'internship' => (800, 1200),
    'monthly' => (3000, 4500),
    'yearly' => (36000, 54000),
    _ => null,
  };
  return examples == null
      ? null
      : 'e.g. ${field == 'salary_min' ? examples.$1 : examples.$2}';
}

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

double? _validSalary(Object? amount) {
  final value = double.tryParse('${amount ?? ''}'.trim());
  return value != null && value.isFinite && value >= 0 ? value : null;
}

String? jobSalaryRangeError(Map<String, dynamic> job) {
  final min = _validSalary(job['salary_min']);
  final max = _validSalary(job['salary_max']);
  return min != null && max != null && max < min
      ? 'Maximum salary must be equal to or greater than minimum salary.'
      : null;
}

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
    if (_validSalary(text) == null) {
      return 'Enter a valid non-negative salary.';
    }
    if (key == 'salary_max') return jobSalaryRangeError(job);
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
