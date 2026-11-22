import 'module2_repository.dart';

// Display formatting only: no timezone conversion or eligibility calculation.
String marketplaceDate(Object? value) {
  final date = DateTime.tryParse('$value');
  if (date == null) return 'Not set';
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

const salaryNotDisclosed = 'Salary not disclosed';

String marketplaceSalary(BrowseJob job) {
  if (job.fields['salary_visible'] != true) return salaryNotDisclosed;
  final min = num.tryParse('${job.fields['salary_min']}');
  final max = num.tryParse('${job.fields['salary_max']}');
  if (min == null || max == null || !min.isFinite || !max.isFinite) {
    return salaryNotDisclosed;
  }
  String amount(num number) {
    final parts =
        (number == number.roundToDouble()
                ? number.toInt().toString()
                : number.toString())
            .split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    return parts.length == 1 ? whole : '$whole.${parts[1]}';
  }

  final period = switch (job.text('salary_period')) {
    'hourly' => 'hour',
    'daily' => 'day',
    'monthly' => 'month',
    'yearly' => 'year',
    final value => value,
  };
  final range = min == max ? amount(min) : '${amount(min)}–${amount(max)}';
  return 'RM $range${period.isEmpty ? '' : ' / $period'}';
}
