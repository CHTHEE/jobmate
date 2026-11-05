import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/mobile_back_action.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'notifications_repository.dart';

String notificationLocalTime(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final format = MaterialLocalizations.of(context);
  return '${format.formatMediumDate(local)}, ${format.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}

/// Opens the same compact Web panel from every dashboard header.
Future<void> showNotificationsPanel(BuildContext context) => showDialog<void>(
  context: context,
  builder: (dialogContext) => Dialog(
    alignment: Alignment.topRight,
    insetPadding: const EdgeInsets.all(12),
    backgroundColor: const Color(0xFF242628),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 440,
        maxHeight: MediaQuery.sizeOf(dialogContext).height - 24,
      ),
      child: SizedBox(
        width: 440,
        child: Theme(
          data: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.lightBlueAccent,
              brightness: Brightness.dark,
            ),
          ),
          child: const NotificationsPage(embedded: true),
        ),
      ),
    ),
  ),
);

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.source, this.embedded = false});
  final NotificationsSource? source;
  final bool embedded;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with WidgetsBindingObserver {
  late final repo = NotificationsRepository(
    widget.source ?? SupabaseNotificationsSource(Supabase.instance.client),
  );
  Listenable? routerChanges;
  bool wasCurrent = true;
  bool unreadOnly = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) repo.load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final changes = GoRouter.maybeOf(context)?.routerDelegate;
    if (!identical(changes, routerChanges)) {
      routerChanges?.removeListener(routeChanged);
      routerChanges = changes;
      routerChanges?.addListener(routeChanged);
      wasCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    }
  }

  void routeChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ModalRoute.of(context)?.isCurrent ?? true;
      if (current && !wasCurrent) repo.load();
      wasCurrent = current;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      repo.load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routerChanges?.removeListener(routeChanged);
    repo.dispose();
    super.dispose();
  }

  Future<void> markRead(JobMateNotification item) async {
    final generation = repo.sessionGeneration;
    final message = await repo.markRead(item.id);
    if (!mounted || !repo.currentSession(generation) || message == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final body = _notificationBody(context);
      if (widget.embedded) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close notifications',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: !unreadOnly,
                    onSelected: (_) => setState(() => unreadOnly = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Unread'),
                    selected: unreadOnly,
                    onSelected: (_) => setState(() => unreadOnly = true),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(child: body),
          ],
        );
      }
      return Scaffold(
        appBar: ResponsivePageAppBar(title: const Text('Notifications')),
        body: SafeArea(child: ResponsiveContent(maxWidth: 900, child: body)),
      );
    },
  );

  Widget _notificationBody(BuildContext context) {
    final visible = unreadOnly && widget.embedded
        ? repo.notifications.where((item) => !item.read).toList()
        : repo.notifications;
    return repo.loading
        ? const Center(child: CircularProgressIndicator())
        : repo.error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(repo.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: repo.load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          )
        : visible.isEmpty
        ? Center(
            child: Text(
              unreadOnly && widget.embedded
                  ? 'No unread notifications.'
                  : 'You do not have any notifications yet.',
            ),
          )
        : ListView.builder(
            padding: ResponsiveLayout.pagePadding(context),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final item = visible[index];
              return Card.outlined(
                key: ValueKey(item.id),
                child: ListTile(
                  leading: Icon(
                    item.read
                        ? Icons.notifications_none
                        : Icons.notifications_active_outlined,
                    color: item.read
                        ? null
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(item.title),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.message),
                        const SizedBox(height: 6),
                        Text(notificationLocalTime(context, item.createdAt)),
                      ],
                    ),
                  ),
                  trailing: repo.marking(item.id)
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : item.read
                      ? const Icon(Icons.check, size: 18)
                      : const Icon(Icons.circle, size: 10),
                  onTap: item.read || repo.marking(item.id)
                      ? null
                      : () => markRead(item),
                ),
              );
            },
          );
  }
}
