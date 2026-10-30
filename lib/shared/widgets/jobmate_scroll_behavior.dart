import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keeps scrolling enabled while hiding Flutter's desktop/web scrollbar.
class JobMateScrollBehavior extends MaterialScrollBehavior {
  const JobMateScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (kIsWeb) return child;

    return super.buildScrollbar(context, child, details);
  }
}
