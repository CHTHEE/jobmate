import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'work_completion_report_export.dart';

ReportPdfPlatform createReportPdfPlatform() => const _NativePlatform();

class _NativePlatform implements ReportPdfPlatform {
  const _NativePlatform();

  @override
  List<ReportPdfAction> get actions => const [
    ReportPdfAction.share,
    ReportPdfAction.print,
  ];

  @override
  ReportPdfTarget reserve(ReportPdfAction action) => _NativeTarget(action);
}

class _NativeTarget implements ReportPdfTarget {
  _NativeTarget(this.action);
  final ReportPdfAction action;

  @override
  Future<void> deliver(
    Uint8List bytes,
    String filename,
    bool Function() isCurrent,
  ) async {
    final capabilities = await Printing.info();
    if (!isCurrent()) return;
    if (action == ReportPdfAction.share && capabilities.canShare) {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } else if (action == ReportPdfAction.print && capabilities.canPrint) {
      await Printing.layoutPdf(
        name: filename,
        format: PdfPageFormat.a4,
        dynamicLayout: false,
        onLayout: (_) {
          if (!isCurrent()) throw StateError('Print request expired');
          return bytes;
        },
      );
    } else {
      throw UnsupportedError('PDF action unavailable');
    }
  }

  @override
  void cancel() {}
}
