import 'dart:typed_data';

import 'work_completion_report_export_native.dart'
    if (dart.library.js_interop) 'work_completion_report_export_web.dart'
    as platform;

enum ReportPdfAction {
  open('Open PDF'),
  download('Download PDF'),
  share('Share PDF'),
  print('Print PDF');

  const ReportPdfAction(this.label);
  final String label;
}

abstract interface class ReportPdfTarget {
  Future<void> deliver(
    Uint8List bytes,
    String filename,
    bool Function() isCurrent,
  );
  void cancel();
}

abstract interface class ReportPdfPlatform {
  List<ReportPdfAction> get actions;

  /// Runs synchronously in the click handler. Null indicates a blocked popup.
  ReportPdfTarget? reserve(ReportPdfAction action);
}

final ReportPdfPlatform reportPdfPlatform = platform.createReportPdfPlatform();
