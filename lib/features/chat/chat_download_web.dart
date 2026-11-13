import 'dart:js_interop';

@JS('window')
external _Window get _window;
@JS('document')
external _Document get _document;

extension type _Document(JSObject _) implements JSObject {
  external String get visibilityState;
}

extension type _Window(JSObject _) implements JSObject {
  external _Window? open(String url, String target);
  external set opener(JSAny? value);
  external _Location get location;
  external bool get closed;
  external void close();
}

extension type _Location(JSObject _) implements JSObject {
  external set href(String value);
}

// Open synchronously during the user's gesture; no async window.open or wildcard
// origin navigation. The signed URL is obtained only through the current gateway.
Future<void> downloadChatFile(Future<Uri> Function() authorize) async {
  final target = _window.open('about:blank', '_blank');
  if (target == null) throw StateError('Allow downloads for JobMate');
  target.opener = null;
  try {
    final uri = await authorize();
    if (uri.scheme != 'https' || target.closed) {
      throw StateError('Download unavailable');
    }
    target.location.href = uri.toString();
  } catch (_) {
    target.close();
    rethrow;
  }
}

bool chatDocumentVisible() => _document.visibilityState == 'visible';
