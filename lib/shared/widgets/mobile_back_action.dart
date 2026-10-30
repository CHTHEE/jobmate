import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shows a back action in native mobile apps when a route can pop.
class MobileBackAction extends StatelessWidget {
  const MobileBackAction({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Navigator.of(context).canPop()) {
      return const SizedBox.shrink();
    }

    return IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }
}

/// Returns a back button only when this native app route can go back.
Widget? mobileBackLeading(BuildContext context) {
  if (kIsWeb || !Navigator.of(context).canPop()) {
    return null;
  }

  return const MobileBackAction();
}
