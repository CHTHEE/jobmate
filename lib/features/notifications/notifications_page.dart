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

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.source});
  final NotificationsSource? source;
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
    builder: (context, _) => Scaffold(
      appBar: ResponsivePageAppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: repo.loading ? null : repo.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 900,
          child: repo.loading
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
              : repo.notifications.isEmpty
              ? const Center(
                  child: Text('You do not have any notifications yet.'),
                )
              : ListView.builder(
                  padding: ResponsiveLayout.pagePadding(context),
                  itemCount: repo.notifications.length,
                  itemBuilder: (context, index) {
                    final item = repo.notifications[index];
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
                              Text(
                                notificationLocalTime(context, item.createdAt),
                              ),
                            ],
                          ),
                        ),
                        trailing: repo.marking(item.id)
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                ),
        ),
      ),
    ),
  );
}
