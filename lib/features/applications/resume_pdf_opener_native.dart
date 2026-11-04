import 'package:url_launcher/url_launcher.dart';

import 'resume_pdf_opener_types.dart';

ResumePdfOpener createResumePdfOpener() => _NativePdfOpener();

class _NativePdfOpener implements ResumePdfOpener {
  @override
  bool get isWeb => false;
  @override
  ResumePdfWindow? reserve() => null;
  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
