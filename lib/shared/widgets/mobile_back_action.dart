import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navigation/app_routes.dart';

/// Keep PopScope/route-exit guards active; direct URLs have no previous route.
Future<void> returnToPage(BuildContext context, String fallback) async {
  if (Navigator.of(context).canPop()) {
    await Navigator.of(context).maybePop();
  } else {
    GoRouter.maybeOf(context)?.go(fallback);
  }
}

Future<bool> confirmDiscardChanges(
  BuildContext context,
  bool hasChanges,
) async {
  if (!hasChanges) return true;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Leave this page?'),
          content: const Text('Your unsaved input will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave page'),
            ),
          ],
        ),
      ) ??
      false;
}

/// Native auth content gets Back with a fallback for directly opened routes.
/// AuthLayout omits this widget entirely on Web (including its spacing).
class MobileBackAction extends StatelessWidget {
  const MobileBackAction({super.key, this.fallback = AppRoutes.home});

  final String fallback;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox.shrink();
    }

    return IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back),
      onPressed: () => returnToPage(context, fallback),
    );
  }
}

/// A standalone page still needs an in-app exit on Web. Text replaces the
/// native arrow, and the same guarded return handles a direct URL safely.
class ResponsivePageAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const ResponsivePageAppBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.fallback = AppRoutes.home,
    this.returnLabel = 'Dashboard',
    this.enabled = true,
    this.showReturnAction = true,
    this.hasUnsavedChanges,
  });

  final Widget title;
  final List<Widget> actions;
  final String fallback;
  final String returnLabel;
  final bool enabled;
  final bool showReturnAction;
  final bool Function()? hasUnsavedChanges;

  Future<void> _return(BuildContext context) async {
    final leave = await confirmDiscardChanges(
      context,
      hasUnsavedChanges?.call() ?? false,
    );
    if (leave && context.mounted) await returnToPage(context, fallback);
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    leading: kIsWeb || !showReturnAction
        ? null
        : IconButton(
            tooltip: 'Back',
            onPressed: enabled ? () => _return(context) : null,
            icon: const Icon(Icons.arrow_back),
          ),
    title: title,
    actions: [
      ...actions,
      if (kIsWeb && showReturnAction)
        TextButton(
          onPressed: enabled ? () => _return(context) : null,
          child: Text(
            returnLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
  );
}

/// Returns a back button only when this native app route can go back.
Widget? mobileBackLeading(BuildContext context) {
  if (kIsWeb) {
    return const SizedBox.shrink();
  }

  if (!Navigator.of(context).canPop()) {
    return null;
  }

  return const MobileBackAction();
}
