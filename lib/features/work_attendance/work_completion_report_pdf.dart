import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'work_completion_report_data.dart';
import 'work_completion_report_format.dart';

/// Export stops rather than replacing characters unsupported by bundled fonts.
class WorkReportPdfFontException implements Exception {
  const WorkReportPdfFontException();
}

Future<Uint8List> renderWorkCompletionReportPdf(
  WorkCompletionReportData data, {
  AssetBundle? assets,
}) async {
  final bundle = assets ?? rootBundle;
  final fonts = await Future.wait([
    _loadFont(bundle, 'assets/fonts/Outfit-Regular.ttf'),
    _loadFont(bundle, 'assets/fonts/DMSerifDisplay-Regular.ttf'),
    _loadFont(bundle, 'assets/fonts/Outfit-SemiBold.ttf'),
  ]);
  final body = TtfParser(fonts[0]);
  final fields = [
    data.jobTitle,
    data.companyName,
    data.workerName ?? '',
    data.workplaceLocation,
    ...data.submittedDescriptions,
  ];
  final unsupported = fields
      .expand((field) => field.runes)
      .where(
        (rune) =>
            !_isWhitespace(rune) && !body.charToGlyphIndexMap.containsKey(rune),
      )
      .toSet();
  ByteData? fallback;
  if (unsupported.isNotEmpty) {
    fallback = await _loadFont(bundle, 'assets/fonts/NotoSansSC-Variable.ttf');
    final glyphs = TtfParser(fallback).charToGlyphIndexMap;
    if (unsupported.any((rune) => !glyphs.containsKey(rune))) {
      throw const WorkReportPdfFontException();
    }
  }
  final document = pw.Document(
    title: WorkReportFormat.title,
    author: 'JobMate',
  );
  final layout = _ReportPdf(
    WorkReportFormat(data),
    pw.Font.ttf(fonts[0]),
    pw.Font.ttf(fonts[1]),
    fallback == null ? null : pw.Font.ttf(fallback),
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_ReportPdf.margin),
      maxPages: 150,
      theme: pw.ThemeData.withFont(
        base: layout.body,
        bold: pw.Font.ttf(fonts[2]),
        fontFallback: [?layout.fallback, layout.body],
      ),
      build: layout.build,
      footer: layout.footer,
    ),
  );
  return document.save();
}

Future<ByteData> _loadFont(AssetBundle bundle, String path) async {
  final bytes = await bundle.load(path);
  // The PDF parser reads parts of the backing buffer from offset zero.
  // Flutter's asset bundle may return a view into a larger buffer.
  return bytes.offsetInBytes == 0 &&
          bytes.lengthInBytes == bytes.buffer.lengthInBytes
      ? bytes
      : ByteData.sublistView(Uint8List.fromList(Uint8List.sublistView(bytes)));
}

bool _isWhitespace(int rune) => String.fromCharCode(rune).trim().isEmpty;

enum _Tone { ordinary, success, info }

class _ReportPdf {
  _ReportPdf(this.report, this.body, this.title, this.fallback);
  final WorkReportFormat report;
  final pw.Font body, title;
  final pw.Font? fallback;
  WorkCompletionReportData get data => report.data;

  static const margin = 18 * PdfPageFormat.mm;
  static final _width = PdfPageFormat.a4.width - 2 * margin;
  static const _size = 10.0;
  static const _navy = PdfColor.fromInt(0xFF0F172A);
  static const _slate = PdfColor.fromInt(0xFF475569);
  static const _teal = PdfColor.fromInt(0xFF0F766E);
  static const _border = PdfColor.fromInt(0xFFE2E8F0);
  static const _panel = PdfColor.fromInt(0xFFF8FAFC);
  static const _blue = PdfColor.fromInt(0xFF1E40AF);

  pw.Widget _text(
    String value, {
    double size = _size,
    PdfColor color = _navy,
    bool bold = false,
    pw.Font? font,
    pw.TextAlign? align,
  }) => pw.Text(
    value,
    textAlign: align,
    style: pw.TextStyle(
      color: color,
      fontSize: size,
      font: font,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      lineSpacing: 2,
    ),
  );

  pw.Widget _header() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 32,
                height: 32,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: _teal,
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.CustomPaint(
                  painter: (canvas, size) {
                    canvas
                      ..setStrokeColor(PdfColors.white)
                      ..setLineWidth(1.35)
                      ..drawRRect(1, 2, 18, 13, 2, 2)
                      ..strokePath()
                      ..drawRect(7, 15, 6, 3)
                      ..strokePath()
                      ..drawLine(2, 10, 18, 10)
                      ..strokePath();
                  },
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.RichText(
                    text: const pw.TextSpan(
                      style: pw.TextStyle(fontSize: 19),
                      children: [
                        pw.TextSpan(
                          text: 'Job',
                          style: pw.TextStyle(color: _navy),
                        ),
                        pw.TextSpan(
                          text: 'Mate',
                          style: pw.TextStyle(color: _teal),
                        ),
                      ],
                    ),
                  ),
                  _text('RECRUITMENT PLATFORM', color: _slate, size: 8),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _text(
                'SYSTEM-GENERATED REPORT',
                color: _slate,
                size: 8,
                bold: true,
              ),
              _text('Generated: ${report.generated}', color: _slate, size: 9),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 15),
      _text(WorkReportFormat.title, font: title, size: 25),
      pw.SizedBox(height: 5),
      _text(WorkReportFormat.introduction, color: _slate),
      pw.Divider(color: _teal, thickness: 1.4, height: 16),
    ],
  );

  List<pw.Widget> build(pw.Context context) => [
    _header(),
    ..._section('Job Information', _jobFacts(context)),
    ..._section(
      'Work Schedule',
      _table(context, [
        ('Scheduled Start', [report.start], _Tone.ordinary),
        ('Scheduled End', [report.end], _Tone.ordinary),
        ('Scheduled Duration', [report.scheduledDuration], _Tone.ordinary),
      ]),
    ),
    ..._section(
      'Attendance Information',
      _table(context, [
        (
          'Check-in Time',
          [report.checkIn, report.checkInTiming],
          _Tone.ordinary,
        ),
        (
          'Check-out Time',
          [report.checkOut, report.checkOutTiming],
          _Tone.ordinary,
        ),
        (
          'Recorded Attendance Duration',
          [report.recordedDuration],
          _Tone.ordinary,
        ),
        (
          'Attendance Status',
          [data.attendanceStatus],
          data.attendanceSource == ReportAttendanceSource.corrected
              ? _Tone.info
              : _Tone.success,
        ),
      ]),
    ),
    pw.SizedBox(height: 8),
    _cards([
      ['CHECK-IN LOCATION', ...WorkReportFormat.location(data.checkInLocation)],
      [
        'CHECK-OUT LOCATION',
        ...WorkReportFormat.location(data.checkOutLocation),
      ],
    ]),
    ..._section(
      'Work Verification',
      _table(context, [
        ('Work Completion Status', [report.completed], _Tone.success),
        ('Evidence Submission', [report.submission], _Tone.info),
        ('Evidence Files Submitted', [report.submittedFiles], _Tone.ordinary),
        (
          'Evidence Description',
          data.submittedDescriptions.isEmpty
              ? const ['Not recorded']
              : data.submittedDescriptions,
          _Tone.ordinary,
        ),
        ('Employer Verification', [report.verification], _Tone.success),
        ('Verification Date', [report.verified], _Tone.ordinary),
        ('Verified By', [report.verifier], _Tone.ordinary),
      ]),
    ),
    ..._section(
      'Job Assignment Information',
      _table(context, [
        ('Assignment Status', [report.completed], _Tone.success),
        ('Scheduled Assignment Start', [report.start], _Tone.ordinary),
        ('Scheduled Assignment End', [report.end], _Tone.ordinary),
        ('Marked Complete at Verification', [report.verified], _Tone.ordinary),
      ]),
    ),
    ..._section(
      'Report Summary',
      _cards([
        [
          'ATTENDANCE',
          data.attendanceStatus,
          '${report.recordedDuration} recorded',
        ],
        ['WORK COMPLETION', report.completed, report.submittedFiles],
        ['VERIFICATION', report.verification, report.verified],
      ]),
    ),
    pw.SizedBox(height: 8),
    pw.Container(
      color: const PdfColor.fromInt(0xFFEFF6FF),
      padding: const pw.EdgeInsets.all(9),
      child: _text(WorkReportFormat.notice, color: _blue),
    ),
  ];

  List<pw.Widget> _section(String title, pw.Widget content) => [
    pw.NewPage(freeSpace: 100),
    pw.SizedBox(height: 12),
    _text(title, size: 13, bold: true),
    pw.Divider(color: _border, height: 8),
    content,
  ];

  pw.Widget footer(pw.Context context) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Divider(color: _border, height: 10),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _text(WorkReportFormat.footer, size: 8, color: _slate),
          _text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            size: 8,
            color: _slate,
          ),
        ],
      ),
      _text(report.generated, size: 8, color: _slate),
    ],
  );

  pw.Widget _cards(List<List<String>> columns) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final (index, column) in columns.indexed) ...[
        if (index > 0) pw.SizedBox(width: 7),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: _panel,
              border: pw.Border.all(color: _border),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _text(column.first, color: _teal, size: 8, bold: true),
                pw.SizedBox(height: 4),
                for (final value in column.skip(1)) _text(value, size: 9),
              ],
            ),
          ),
        ),
      ],
    ],
  );

  pw.Widget _jobFacts(pw.Context context) {
    final facts = [
      [('Job Title', data.jobTitle), ('Employer', data.companyName)],
      [
        ('Employment Type', data.employmentTypeLabel ?? 'Not available'),
        ('Job Seeker', data.workerName ?? 'Not available'),
      ],
      [
        ('Work Date', report.workDates),
        ('Scheduled Work Location', data.workplaceLocation),
      ],
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: .5),
      children: [for (final pair in facts) ..._pairedFacts(context, pair)],
    );
  }

  Iterable<pw.TableRow> _pairedFacts(
    pw.Context context,
    List<(String, String)> pair,
  ) sync* {
    final columns = pair
        .map((fact) => _wrap(context, fact.$2, _width / 2 - 21))
        .toList();
    final count = math.max(columns[0].length, columns[1].length);
    for (var start = 0; start < count; start += 4) {
      yield pw.TableRow(
        children: [
          for (final (index, lines) in columns.indexed)
            _cell([
              if (start == 0)
                _text(pair[index].$1, size: 8, color: _slate, bold: true),
              for (final line in lines.skip(start).take(4)) _text(line),
            ]),
        ],
      );
    }
  }

  pw.Widget _table(
    pw.Context context,
    List<(String, List<String>, _Tone)> rows,
  ) => pw.Table(
    columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(2)},
    border: pw.TableBorder.all(color: _border, width: .5),
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEDF2F7)),
        children: [
          _cell([_text('ITEM', size: 8, bold: true)]),
          _cell([_text('DETAILS', size: 8, bold: true)]),
        ],
      ),
      for (final (label, values, tone) in rows)
        ..._tableRows(context, label, values, tone),
    ],
  );

  Iterable<pw.TableRow> _tableRows(
    pw.Context context,
    String label,
    List<String> values,
    _Tone tone,
  ) sync* {
    final lines = [
      for (final value in values) ..._wrap(context, value, _width * 2 / 3 - 21),
    ];
    final color = switch (tone) {
      _Tone.success => const PdfColor.fromInt(0xFF166534),
      _Tone.info => _blue,
      _Tone.ordinary => _navy,
    };
    final background = switch (tone) {
      _Tone.success => const PdfColor.fromInt(0xFFF0FDF4),
      _Tone.info => const PdfColor.fromInt(0xFFEFF6FF),
      _Tone.ordinary => _panel,
    };
    for (var start = 0; start < lines.length; start += 4) {
      yield pw.TableRow(
        decoration: pw.BoxDecoration(color: background),
        children: [
          _cell([if (start == 0) _text(label, color: _slate)]),
          _cell([
            for (final line in lines.skip(start).take(4))
              _text(line, color: color),
          ]),
        ],
      );
    }
  }

  pw.Widget _cell(List<pw.Widget> children) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    ),
  );

  /// Bound each physical table row. Long tokens and CJK text can break on a
  /// grapheme boundary, while ordinary words wrap preferentially at spaces.
  List<String> _wrap(pw.Context context, String value, double width) {
    final base = body.getFont(context);
    final extra = fallback?.getFont(context);
    final lines = <String>[];
    for (final paragraph in value.split(RegExp(r'\r\n?|\n|\u2028|\u2029'))) {
      final glyphs = paragraph.characters
          .map((glyph) => glyph.trim().isEmpty ? ' ' : glyph)
          .toList();
      final widths = glyphs
          .map(
            (glyph) => glyph.runes.fold<double>(0, (sum, rune) {
              if (_isWhitespace(rune)) {
                return sum + base.glyphMetrics(32).advanceWidth * _size;
              }
              final font = base.isRuneSupported(rune) ? base : extra;
              if (font == null || !font.isRuneSupported(rune)) {
                throw const WorkReportPdfFontException();
              }
              return sum + font.glyphMetrics(rune).advanceWidth * _size;
            }),
          )
          .toList();
      if (glyphs.isEmpty) lines.add('');
      var start = 0;
      while (start < glyphs.length) {
        var end = start;
        var lastSpace = -1;
        var used = 0.0;
        while (end < glyphs.length && used + widths[end] <= width) {
          used += widths[end];
          if (glyphs[end].trim().isEmpty) lastSpace = end;
          end++;
        }
        if (end < glyphs.length && lastSpace > start) end = lastSpace + 1;
        if (end == start) end++;
        lines.add(glyphs.getRange(start, end).join().trimRight());
        start = end;
        while (start < glyphs.length && glyphs[start].trim().isEmpty) {
          start++;
        }
      }
    }
    return lines;
  }
}
