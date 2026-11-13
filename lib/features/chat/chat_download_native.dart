import 'package:url_launcher/url_launcher.dart';

Future<void> downloadChatFile(Future<Uri> Function() authorize) async {
  final uri = await authorize();
  if (uri.scheme != 'https' ||
      !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw StateError('Download unavailable');
  }
}

bool chatDocumentVisible() => true;
