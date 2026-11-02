String jobLabel(String key) =>
    const {
      'title': 'Job title',
      'department': 'Department',
      'location': 'Job location',
      'salary_min': 'Minimum salary',
      'salary_max': 'Maximum salary',
      'vacancies': 'Vacancies',
      'application_deadline': 'Application deadline',
      'original_description': 'Original description',
      'role_overview': 'Role overview',
      'responsibilities': 'Responsibilities',
      'requirements': 'Requirements',
      'benefits': 'Benefits',
      'employment_type': 'Employment type',
      'work_arrangement': 'Work arrangement',
      'salary_period': 'Salary period',
      'full_time': 'Full-time',
      'part_time': 'Part-time',
      'on_site': 'On-site',
      'contract': 'Contract',
      'internship': 'Internship',
      'temporary': 'Temporary',
      'hybrid': 'Hybrid',
      'remote': 'Remote',
      'hourly': 'Hourly',
      'daily': 'Daily',
      'monthly': 'Monthly',
      'yearly': 'Yearly',
    }[key] ??
    key;

String jobDate(Object? value) {
  final date = DateTime.tryParse('$value');
  if (date == null) return 'Not set';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String jobSalary(Map<String, dynamic> job) =>
    '${job['salary_min'] ?? 'Not specified'} – ${job['salary_max'] ?? 'Not specified'} / ${jobLabel('${job['salary_period'] ?? ''}')}';

const jobExamples = {
  'title': 'e.g. Part-Time Retail Assistant',
  'department': 'e.g. Retail Operations',
  'location': 'e.g. Shah Alam, Selangor, Malaysia',
  'salary_min': 'e.g. 12',
  'salary_max': 'e.g. 18',
  'vacancies': 'e.g. 3',
  'application_deadline': 'YYYY-MM-DD',
  'original_description': 'e.g. We need a friendly retail assistant to help customers and keep our store organised on weekends.',
  'role_overview': 'e.g. Join our retail team to help customers find the right products. You will support daily store operations and work with a friendly team.',
  'responsibilities': 'e.g. Assist customers with product enquiries',
  'requirements': 'e.g. Good communication skills',
  'benefits': 'e.g. Flexible working hours',
};
