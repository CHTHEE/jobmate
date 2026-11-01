import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/mobile_back_action.dart';
import '../../shared/widgets/responsive_layout.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _supabase = Supabase.instance.client;
  final _actorId = Supabase.instance.client.auth.currentUser?.id;
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_actorId == null || _supabase.auth.currentUser?.id != _actorId) {
        throw StateError('Your signed-in account has changed.');
      }
      final result = await _supabase.rpc(
        'list_my_notifications',
        params: {'p_limit': 101, 'p_offset': 0},
      );
      if (!mounted) return;
      if (_supabase.auth.currentUser?.id != _actorId) {
        throw StateError('Your signed-in account has changed.');
      }
      if (result is! List) {
        throw const FormatException('Unexpected notifications response.');
      }
      setState(() {
        _notifications = result
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      debugPrint('Notifications load failed: $error');
      if (!mounted) return;
      setState(() {
        _error = error is StateError
            ? error.message.toString()
            : 'Unable to load notifications. Please retry.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(Map<String, dynamic> notification) async {
    if (notification['read_at'] != null) return;
    final actorId = _actorId;
    if (actorId == null || _supabase.auth.currentUser?.id != actorId) return;
    try {
      await _supabase.rpc(
        'mark_my_notification_read',
        params: {'p_notification_id': notification['notification_id']},
      );
      if (!mounted || _supabase.auth.currentUser?.id != actorId) return;
      await _loadNotifications();
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: mobileBackLeading(context),
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadNotifications,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 900,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadNotifications,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _notifications.isEmpty
              ? const Center(child: Text('You do not have any notifications yet.'))
              : ListView.builder(
                  padding: ResponsiveLayout.pagePadding(context),
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final item = _notifications[index];
                    final read = item['read_at'] != null;
                    final createdAt = item['created_at']?.toString();
                    return Card.outlined(
                      child: ListTile(
                        leading: Icon(
                          read
                              ? Icons.notifications_none
                              : Icons.notifications_active_outlined,
                          color: read
                              ? null
                              : Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(item['title'] as String? ?? 'Notification'),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['message'] as String? ?? ''),
                              if (createdAt != null) ...[
                                const SizedBox(height: 6),
                                Text(createdAt.replaceFirst('T', ' ').split('.').first),
                              ],
                            ],
                          ),
                        ),
                        trailing: read
                            ? const Icon(Icons.check, size: 18)
                            : const Icon(Icons.circle, size: 10),
                        onTap: read ? null : () => _markRead(item),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
