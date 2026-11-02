import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, String> parseJobFormatting(Object? data) {
  if (data is! Map ||
      data['role_overview'] is! String ||
      (data['role_overview'] as String).trim().isEmpty) {
    throw const FormatException('Invalid AI response.');
  }
  final result = <String, String>{
    'role_overview': (data['role_overview'] as String).trim(),
  };
  for (final key in ['responsibilities', 'requirements', 'benefits']) {
    final items = data[key];
    if (items is! List || items.any((item) => item is! String)) {
      throw const FormatException('Invalid AI response.');
    }
    result[key] = items
        .cast<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join('\n');
  }
  return result;
}

String jobFormattingError(Object error) {
  if (error is FunctionException) {
    return switch (error.status) {
      401 => 'Your session has expired. Sign in again to use AI formatting.',
      403 => 'You do not have permission to format job descriptions.',
      429 => 'AI formatting is busy or the request limit was reached. Please try again later.',
      502 =>
        'The AI service is temporarily unavailable. Please try again later.',
      _ => 'AI formatting failed. Please try again. You can continue editing manually.',
    };
  }
  if (error is FormatException) {
    return 'AI returned an unexpected response. Your text has been preserved. Please try again.';
  }
  if (error is StateError) {
    // Only known user-facing session messages may cross this boundary.
    switch (error.message) {
      case 'Sign in to use AI formatting.':
      case 'Your session changed. Sign in again to use AI formatting.':
        return error.message.toString();
    }
  }
  return 'Unable to connect to AI formatting. Your text has been preserved. You can continue editing manually.';
}
