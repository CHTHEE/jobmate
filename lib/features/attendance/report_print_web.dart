import 'dart:js_interop';

@JS('window.open')
external JSObject? _open(JSString url, JSString target);

extension type _ReportWindow(JSObject _) implements JSObject {
  external _ReportDocument get document;
}

extension type _ReportDocument(JSObject _) implements JSObject {
  external void write(JSString content);
  external void close();
}

/// A user-triggered standalone HTML print view, independent of Flutter's canvas.
bool openReportPrint(String html) {
  final window = _open(''.toJS, '_blank'.toJS);
  if (window == null) return false;
  final document = _ReportWindow(window).document;
  document.write(html.toJS);
  document.close();
  return true;
}
