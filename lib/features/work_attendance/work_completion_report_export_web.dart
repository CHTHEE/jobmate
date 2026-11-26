import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'work_completion_report_export.dart';

ReportPdfPlatform createReportPdfPlatform() => const _WebPlatform();

class _WebPlatform implements ReportPdfPlatform {
  const _WebPlatform();

  @override
  List<ReportPdfAction> get actions => const [
    ReportPdfAction.open,
    ReportPdfAction.download,
  ];

  @override
  ReportPdfTarget? reserve(ReportPdfAction action) {
    if (action == ReportPdfAction.download) return _WebTarget(null);
    final tab = web.window.open('about:blank', '_blank');
    if (tab == null) return null;
    try {
      tab.opener = null;
      _showPreparation(tab);
      return _WebTarget(tab);
    } catch (_) {
      tab.close();
      rethrow;
    }
  }
}

/// Only static content is written to the reserved same-origin document.
/// An unavailable DOM leaves the original blank-tab export path usable.
void _showPreparation(web.Window tab) {
  try {
    final document = tab.document;
    final body = document.body;
    if (body == null) return;
    document.title = 'Preparing PDF — JobMate';
    document.documentElement?.setAttribute('lang', 'en');
    final viewport = document.createElement('meta')
      ..setAttribute('name', 'viewport')
      ..setAttribute('content', 'width=device-width, initial-scale=1');
    document.head?.appendChild(viewport);
    final style = document.createElement('style')
      ..textContent = '''
body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f5f7f9;color:#0f172a;font:16px/1.5 system-ui,sans-serif}
main{text-align:center;padding:24px}
.brand{display:flex;align-items:center;justify-content:center;gap:9px;font-size:24px;font-weight:700}
.mark{display:grid;place-items:center;width:38px;height:38px;border-radius:9px;background:#0f766e}
.mate{color:#0f766e}
.spinner{display:block;width:25px;height:25px;margin:24px auto 14px;border:3px solid #ccfbf1;border-top-color:#0f766e;border-radius:50%;animation:spin .9s linear infinite}
h1{margin:0;font-size:20px}p{margin:4px 0 0;color:#475569}
@keyframes spin{to{transform:rotate(1turn)}}
@media(prefers-reduced-motion:reduce){.spinner{animation:none}}
''';
    document.head?.appendChild(style);
    final main = document.createElement('main')..setAttribute('role', 'status');
    final brand = document.createElement('div')..className = 'brand';
    final mark = document.createElement('span')
      ..className = 'mark'
      ..setAttribute('aria-hidden', 'true');
    const svg = 'http://www.w3.org/2000/svg';
    final icon = document.createElementNS(svg, 'svg')
      ..setAttribute('viewBox', '0 0 24 24')
      ..setAttribute('width', '22')
      ..setAttribute('height', '22')
      ..setAttribute('fill', 'none')
      ..setAttribute('stroke', 'white')
      ..setAttribute('stroke-width', '1.7');
    icon.appendChild(
      document.createElementNS(svg, 'rect')
        ..setAttribute('x', '3')
        ..setAttribute('y', '7')
        ..setAttribute('width', '18')
        ..setAttribute('height', '13')
        ..setAttribute('rx', '2'),
    );
    icon.appendChild(
      document.createElementNS(svg, 'path')
        ..setAttribute('d', 'M8 7V5a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2M3 12h18'),
    );
    mark.appendChild(icon);
    final wordmark = document.createElement('span')..textContent = 'Job';
    wordmark.appendChild(
      document.createElement('span')
        ..className = 'mate'
        ..textContent = 'Mate',
    );
    brand
      ..appendChild(mark)
      ..appendChild(wordmark);
    main
      ..appendChild(brand)
      ..appendChild(
        document.createElement('span')
          ..className = 'spinner'
          ..setAttribute('aria-hidden', 'true'),
      )
      ..appendChild(
        document.createElement('h1')..textContent = 'Preparing your PDF...',
      )
      ..appendChild(
        document.createElement('p')
          ..textContent = 'Please wait while your report is being generated.',
      );
    body.appendChild(main);
  } catch (_) {
    // Some browsers restrict access to the initial tab document.
  }
}

class _WebTarget implements ReportPdfTarget {
  _WebTarget(this.tab);
  final web.Window? tab;
  bool _delivered = false;

  @override
  Future<void> deliver(
    Uint8List bytes,
    String filename,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return;
    final target = tab;
    if (target?.closed ?? false) throw StateError('PDF tab closed');
    final url = web.URL.createObjectURL(
      web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf')),
    );
    try {
      if (target != null) {
        target.location.replace(url);
        _expireViewerUrl(target, url);
      } else {
        final anchor = web.HTMLAnchorElement()
          ..href = url
          ..download = filename;
        web.document.body?.appendChild(anchor);
        try {
          anchor.click();
        } finally {
          anchor.remove();
        }
        Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
      }
      _delivered = true;
    } catch (_) {
      web.URL.revokeObjectURL(url);
      rethrow;
    }
  }

  static void _expireViewerUrl(web.Window target, String url) {
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (target.closed || timer.tick >= 150) {
        timer.cancel();
        web.URL.revokeObjectURL(url);
      }
    });
  }

  @override
  void cancel() {
    final target = tab;
    if (!_delivered && target != null && !target.closed) target.close();
  }
}
