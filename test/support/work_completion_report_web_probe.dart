// Compile with dart compile js and load the output in a local HTML page.
// Allow 66 seconds of browser virtual time to exercise object-URL expiry.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:jobmate/features/work_attendance/work_completion_report_export.dart';
import 'package:web/web.dart' as web;

@JS('URL')
external JSObject get _url;
@JS('HTMLAnchorElement.prototype')
external JSObject get _anchorPrototype;

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}

Future<void> main() async {
  try {
    await _probe();
    web.document.body!.textContent = 'PASS: branded PDF tab and export cleanup';
  } catch (error) {
    web.document.body!.textContent = 'FAIL: $error';
    rethrow;
  }
}

Future<void> _probe() async {
  final JSObject browser = web.window;
  final priorOpen = browser['open'];
  final create = _url['createObjectURL'] as JSFunction;
  final revoke = _url['revokeObjectURL'] as JSFunction;
  final priorClick = _anchorPrototype['click'];
  var opens = 0;
  var closes = 0;
  var blocked = false;
  var domUnavailable = false;
  var closed = false;
  String? navigated;
  String? downloaded;
  String? downloadedUrl;
  final blobs = <String>[];
  final revoked = <String>[];
  final documents = <web.Document>[];
  final bytes = Uint8List.fromList([37, 80, 68, 70, 45]);
  late JSObject lastTab;
  browser['open'] = ((JSString path, JSString target) {
    _expect(
      path.toDart == 'about:blank' && target.toDart == '_blank',
      'blank reservation',
    );
    if (blocked) return null;
    opens++;
    closed = false;
    final tab = JSObject();
    tab['opener'] = browser;
    tab['closed'] = false.toJS;
    tab['close'] = (() {
      closes++;
      closed = true;
      tab['closed'] = true.toJS;
    }).toJS;
    tab['location'] = JSObject()
      ..['replace'] = ((JSString value) => navigated = value.toDart).toJS;
    if (!domUnavailable) {
      final document = web.document.implementation.createHTMLDocument('');
      documents.add(document);
      tab['document'] = document;
    }
    lastTab = tab;
    return tab;
  }).toJS;
  _url['createObjectURL'] = ((JSObject blob) {
    final value = blob as web.Blob;
    _expect(
      value.type == 'application/pdf' && value.size == bytes.length,
      'PDF Blob',
    );
    final url = create.callAsFunction(_url, blob) as JSString;
    blobs.add(url.toDart);
    return url;
  }).toJS;
  _url['revokeObjectURL'] = ((JSString url) {
    revoked.add(url.toDart);
    revoke.callAsFunction(_url, url);
  }).toJS;
  _anchorPrototype['click'] = ((JSObject self) {
    final anchor = self as web.HTMLAnchorElement;
    downloaded = anchor.download;
    downloadedUrl = anchor.href;
  }).toJSCaptureThis;

  try {
    final pending = reportPdfPlatform.reserve(ReportPdfAction.open)!;
    final loading = documents.single;
    _expect(
      opens == 1 && lastTab['opener'] == null && blobs.isEmpty,
      'synchronous detached reservation',
    );
    _expect(loading.title == 'Preparing PDF — JobMate', 'title');
    _expect(
      loading.querySelector('main')?.textContent == 'JobMatePreparing your PDF...Please wait while your report is being generated.',
      'static text only',
    );
    _expect(
      loading.querySelector('script, link, img, iframe') == null,
      'self-contained preparation page',
    );
    pending.cancel();
    _expect(
      closed && closes == 1 && navigated == null,
      'blank tab cancellation',
    );

    final viewer = reportPdfPlatform.reserve(ReportPdfAction.open)!;
    await viewer.deliver(bytes, 'report.pdf', () => false);
    _expect(blobs.isEmpty && navigated == null, 'invalidated request');
    await viewer.deliver(bytes, 'report.pdf', () => true);
    viewer.cancel();
    _expect(
      opens == 2 && !closed && navigated == blobs.single,
      'reuse the reserved tab',
    );
    lastTab['closed'] = true.toJS;
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    _expect(revoked.single == blobs.single, 'viewer URL cleanup after close');

    domUnavailable = true;
    final fallback = reportPdfPlatform.reserve(ReportPdfAction.open)!;
    await fallback.deliver(bytes, 'report.pdf', () => true);
    _expect(
      opens == 3 && navigated == blobs.last,
      'blank-tab fallback still delivers',
    );
    lastTab['closed'] = true.toJS;
    await Future<void>.delayed(const Duration(milliseconds: 2100));

    final closedTarget = reportPdfPlatform.reserve(ReportPdfAction.open)!;
    lastTab['closed'] = true.toJS;
    try {
      await closedTarget.deliver(bytes, 'report.pdf', () => true);
      throw ArgumentError('Closed tab accepted PDF');
    } on StateError {
      _expect(blobs.length == 2, 'closed tab produces no object URL');
    }
    final download = reportPdfPlatform.reserve(ReportPdfAction.download)!;
    await download.deliver(bytes, 'report.pdf', () => true);
    _expect(
      downloaded == 'report.pdf' && downloadedUrl == blobs.last,
      'direct download dispatch',
    );
    blocked = true;
    _expect(
      reportPdfPlatform.reserve(ReportPdfAction.open) == null,
      'popup-blocked fallback',
    );
    await Future<void>.delayed(const Duration(seconds: 61));
    _expect(
      revoked.length == 3 && revoked.last == downloadedUrl,
      'download URL cleanup',
    );
  } finally {
    browser['open'] = priorOpen;
    _url['createObjectURL'] = create;
    _url['revokeObjectURL'] = revoke;
    _anchorPrototype['click'] = priorClick;
  }
}
