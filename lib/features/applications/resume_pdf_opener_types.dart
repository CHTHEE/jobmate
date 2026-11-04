abstract class ResumePdfWindow {
  bool navigate(Uri uri);
  void close();
}

abstract class ResumePdfOpener {
  bool get isWeb;
  ResumePdfWindow? reserve();
  Future<bool> open(Uri uri);
}
