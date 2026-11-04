import 'dart:js_interop';

import 'package:url_launcher/url_launcher.dart';

import 'resume_pdf_opener_types.dart';

@JS('window.open')
external JSObject? _open(JSString url, JSString target);

extension type _PdfWindow(JSObject _) implements JSObject {
  external bool get closed;
  external set opener(JSAny? value);
  external _PdfLocation get location;
  external void close();
}

extension type _PdfLocation(JSObject _) implements JSObject {
  external void replace(JSString url);
}

class _ReservedWindow implements ResumePdfWindow {
  _ReservedWindow(this.window);
  final _PdfWindow window;
  @override
  bool navigate(Uri uri) {
    try {
      if (window.closed) return false;
      window.location.replace(uri.toString().toJS);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void close() {
    try {
      window.close();
    } catch (_) {}
  }
}

ResumePdfOpener createResumePdfOpener() => _WebPdfOpener();

class _WebPdfOpener implements ResumePdfOpener {
  @override
  bool get isWeb => true;
  @override
  ResumePdfWindow? reserve() {
    _PdfWindow? window;
    try {
      final handle = _open('about:blank'.toJS, '_blank'.toJS);
      if (handle == null) return null;
      window = _PdfWindow(handle);
      window.opener = null;
      return _ReservedWindow(window);
    } catch (_) {
      if (window != null) _ReservedWindow(window).close();
      return null;
    }
  }

  @override
  Future<bool> open(Uri uri) => launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_blank',
  );
}
