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

String marketplaceSalary(BrowseJob job) {
  if (job.fields['salary_visible'] != true ||
      job.fields['salary_min'] == null ||
      job.fields['salary_max'] == null) {
    return 'Not disclosed';
  }
  String amount(Object value) {
    final raw = '$value';
    final number = num.tryParse(raw);
    if (number == null || !number.isFinite) return raw;
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
  return '${amount(job.fields['salary_min'])}–${amount(job.fields['salary_max'])}${period.isEmpty ? '' : ' / $period'}';
}
