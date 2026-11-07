import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/notifications/notifications_page.dart';
import '../../features/search/universal_search_page.dart';
import '../navigation/app_routes.dart';
import 'auth_style.dart';

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

/// Standalone pages use the brand as a Web dashboard link and native Back.
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

  Future<void> _goDashboard(BuildContext context) async {
    final leave = await confirmDiscardChanges(
      context,
      hasUnsavedChanges?.call() ?? false,
    );
    if (leave && context.mounted) GoRouter.of(context).go(AppRoutes.home);
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final dashboardLogo =
        kIsWeb && showReturnAction && returnLabel == 'Dashboard';
    final hasSession = _hasAuthenticatedSession();
    return AppBar(
      automaticallyImplyLeading: false,
      leadingWidth: kIsWeb
          ? MediaQuery.sizeOf(context).width >= 600
                ? 146
                : 56
          : null,
      leading: kIsWeb
          ? Tooltip(
              message: showReturnAction ? 'Go to dashboard' : 'JobMate',
              child: InkWell(
                onTap: enabled && showReturnAction
                    ? () => _goDashboard(context)
                    : null,
                child: Center(
                  child: MediaQuery.sizeOf(context).width >= 600
                      ? const AuthWordmark(compact: true)
                      : const Icon(
                          Icons.work_outline_rounded,
                          color: AuthStyle.teal,
                        ),
                ),
              ),
            )
          : kIsWeb || !showReturnAction
          ? null
          : IconButton(
              tooltip: 'Back',
              onPressed: enabled ? () => _return(context) : null,
              icon: const Icon(Icons.arrow_back),
            ),
      title: title,
      actions: [
        ...actions,
        if (hasSession) ...[
          IconButton(
            tooltip: 'Search jobs and companies',
            onPressed: enabled ? () => showJobMateSearchPanel(context) : null,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: !enabled
                ? null
                : () => kIsWeb
                    ? showNotificationsPanel(context)
                    : context.push<void>(AppRoutes.notifications),
            icon: const Icon(Icons.notifications_none_outlined),
          ),
        ],
        if (kIsWeb && showReturnAction && !dashboardLogo)
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
}

bool _hasAuthenticatedSession() {
  try {
    return Supabase.instance.client.auth.currentUser != null;
  } catch (_) {
    return false;
  }
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
