import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_data.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_format.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_pdf.dart';
import 'package:pdf/pdf.dart';

import 'work_completion_report_data_test.dart' as fixture;

class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    final backing = Uint8List(bytes.length + 8)
      ..setRange(4, bytes.length + 4, bytes);
    return ByteData.sublistView(backing, 4, bytes.length + 4);
  }
}

WorkCompletionReportData _longReport() {
  final base = fixture.report();
  return WorkCompletionReportData(
    generatedAt: base.generatedAt,
    jobTitle: 'Warehouse inventory ${'longTitleToken' * 95}',
    companyName: 'Operasi Gudang Malaysia · Société',
    workerName: '陈美玲 · Nur Aïsha',
    workplaceLocation: 'Jalan Tun Razak ${'receiving bay ' * 80}',
    scheduledStart: base.scheduledStart,
    scheduledEnd: base.scheduledEnd,
    checkInAt: base.checkInAt.subtract(
      const Duration(seconds: 5, milliseconds: 400),
    ),
    checkOutAt: base.checkOutAt.add(
      const Duration(seconds: 4, milliseconds: 700),
    ),
    attendanceSource: ReportAttendanceSource.corrected,
    checkInLocation: (
      status: ReportLocationStatus.denied,
      originalEventAt: base.checkInAt,
    ),
    checkOutLocation: base.checkOutLocation,
    verifiedRound: 2,
    submittedFileCount: 1,
    submittedDescriptions: [
      for (var n = 0; n < 100; n++)
        'Entry $n — Pemeriksaan selesai · 库存更新. Items counted and listed.',
      'FinalEvidenceMarker',
    ],
    verifiedAt: base.verifiedAt,
  );
}

void main() {
  final fonts = _FileBundle();

  test('PDF emits A4 portrait pages with selectable report text', () async {
    final base = fixture.report();
    final bytes = await renderWorkCompletionReportPdf(base, assets: fonts);
    final raw = latin1.decode(bytes);
    expect(raw, startsWith('%PDF-'));
    final pages = RegExp(r'/Type\s*/Page\b').allMatches(raw).length;
    final boxes = RegExp(r'/MediaBox\s*\[([^\]]+)\]').allMatches(raw);
    expect(pages, greaterThanOrEqualTo(1));
    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      final points = box
          .group(1)!
          .trim()
          .split(RegExp(r'\s+'))
          .map(double.parse)
          .toList();
      expect(points[2] - points[0], closeTo(PdfPageFormat.a4.width, .01));
      expect(points[3] - points[1], closeTo(PdfPageFormat.a4.height, .01));
    }
    final rendered = _extractText(raw);
    for (final text in [
      WorkReportFormat.title,
      'Job Information',
      'Work Schedule',
      'Attendance Information',
      'Work Verification',
      'Job Assignment Information',
      'Report Summary',
      'Recorded Attendance Duration',
      'Not available',
      'Not recorded',
      'Marked Complete at Verification',
      '2 files submitted',
      WorkReportFormat.notice,
      WorkReportFormat.footer,
      'Page 1 of $pages',
    ]) {
      expect(rendered, contains(text), reason: text);
    }
    for (final text in [
      'Private.pdf',
      'signedUrl',
      'Report preview',
      'Download PDF',
    ]) {
      expect(rendered, isNot(contains(text)));
    }
  });

  test(
    'PDF paginates full long evidence, unbroken strings and supported Unicode',
    () async {
      final data = _longReport();
      final raw = latin1.decode(
        await renderWorkCompletionReportPdf(data, assets: fonts),
      );
      final pages = RegExp(r'/Type\s*/Page\b').allMatches(raw).length;
      expect(pages, greaterThan(2));
      final rendered = _extractText(raw);
      for (final text in [
        'Entry 0',
        'Entry 99',
        'FinalEvidenceMarker',
        'Nur Aïsha',
        'Employer-corrected attendance',
        '1 file submitted',
        WorkReportFormat(data).checkIn,
        WorkReportFormat(data).checkInTiming,
        WorkReportFormat(data).workDates,
      ]) {
        expect(rendered, contains(text), reason: text);
      }
      final compact = rendered.replaceAll(RegExp(r'\s'), '');
      expect(compact, contains('库存更新'));
      expect(compact, contains('陈美玲'));
      // The first row includes the neighboring Employer cell in paint order.
      expect(
        compact.replaceFirst('EmployerOperasiGudangMalaysia·Société', ''),
        contains('longTitleToken' * 95),
      );
      for (var i = 1; i <= pages; i++) {
        expect(rendered, contains('Page $i of $pages'));
      }
      expect(RegExp('DETAILS').allMatches(rendered).length, greaterThan(4));
    },
  );

  test(
    'unsupported glyphs fail explicitly without a substituted PDF',
    () async {
      final data = fixture.report(descriptions: ['Unsupported 🧪']);
      await expectLater(
        renderWorkCompletionReportPdf(data, assets: fonts),
        throwsA(isA<WorkReportPdfFontException>()),
      );
    },
  );
}

// Inspect content streams and ToUnicode maps from the project's renderer.
// This helper understands the emitted PDF dialect and doesn't render pages.
String _extractText(String raw) {
  final objects = {
    for (final object in RegExp(
      r'(\d+) 0 obj\b([\s\S]*?)\bendobj',
    ).allMatches(raw))
      object.group(1)!: object.group(2)!,
  };
  String stream(String object) {
    final start = RegExp(r'\bstream\r?\n').firstMatch(object)!;
    final header = object.substring(0, start.start);
    final length = int.parse(
      RegExp(r'/Length\s+(\d+)').firstMatch(header)!.group(1)!,
    );
    final bytes = latin1.encode(
      object.substring(start.end, start.end + length),
    );
    return latin1.decode(
      header.contains('FlateDecode') ? zlib.decode(bytes) : bytes,
    );
  }

  final text = <String>[];
  for (final page in objects.values.where(
    (value) => RegExp(r'/Type\s*/Page\b').hasMatch(value),
  )) {
    final fontMaps = <String, Map<int, String>>{};
    final resources =
        RegExp(r'/Font\s*<<([\s\S]*?)>>').firstMatch(page)?.group(1) ?? '';
    for (final entry in RegExp(r'/(\w+)\s+(\d+) 0 R').allMatches(resources)) {
      final font = objects[entry.group(2)]!;
      final unicode = RegExp(r'/ToUnicode\s+(\d+) 0 R')
          .firstMatch(font)
          ?.group(1);
      if (unicode == null) continue;
      final cmap = stream(objects[unicode]!);
      fontMaps[entry.group(1)!] = {
        for (final range in RegExp(
          r'beginbfchar([\s\S]*?)endbfchar',
        ).allMatches(cmap))
          for (final pair in RegExp(
            r'<([\da-fA-F]+)>\s*<([\da-fA-F]+)>',
          ).allMatches(range.group(1)!))
            int.parse(pair.group(1)!, radix: 16): String.fromCharCodes([
              for (var index = 0; index < pair.group(2)!.length; index += 4)
                int.parse(
                  pair.group(2)!.substring(index, index + 4),
                  radix: 16,
                ),
            ]),
      };
    }
    final contentId = RegExp(r'/Contents\s+(\d+) 0 R')
        .firstMatch(page)!
        .group(1);
    final content = stream(objects[contentId]!);
    String? font;
    for (final token in RegExp(
      r'/(\w+)\s+[\d.]+\s+Tf|<([\da-fA-F]+)>\]\s*TJ|\(((?:\\.|[^\\)])*)\)\]\s*TJ',
    ).allMatches(content)) {
      if (token.group(1) != null) {
        font = token.group(1);
      } else if (token.group(2) case final value?) {
        final map = fontMaps[font] ?? {};
        text.add(
          [
            for (var index = 0; index < value.length; index += 4)
              map[int.parse(value.substring(index, index + 4), radix: 16)] ??
                  '',
          ].join(),
        );
      } else if (token.group(3) case final value?) {
        text.add(
          value.replaceAllMapped(RegExp(r'\\([0-7]{3}|.)'), (match) {
            final escape = match.group(1)!;
            return escape.length == 3
                ? String.fromCharCode(int.parse(escape, radix: 8))
                : escape;
          }),
        );
      }
    }
  }
  return text.join(' ').replaceAll(RegExp(r'\s+'), ' ');
}
