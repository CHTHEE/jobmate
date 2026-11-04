import 'dart:async';

import 'package:jobmate/features/notifications/notifications_repository.dart';

Map<String, dynamic> notificationRow({
  String id = 'notification-1',
  String? readAt,
}) => {
  'notification_id': id,
  'notification_type': 'application_submitted',
  'title': 'Application received',
  'message': 'Server notification content',
  'created_at': '2026-11-04T18:11:37+08:00',
  'read_at': readAt,
};

class FakeNotificationsSource implements NotificationsSource {
  String? actor = 'seeker';
  final changes = StreamController<String?>.broadcast(sync: true);
  List<Map<String, dynamic>> rows = [notificationRow()];
  Future<List<Map<String, dynamic>>> Function()? onList;
  Future<bool> Function()? onMark;
  int lists = 0, marks = 0;
  @override
  String? get userId => actor;
  @override
  Stream<String?> get accountChanges => changes.stream;
  void switchAccount(String? id) {
    actor = id;
    changes.add(id);
  }

  @override
  Future<List<Map<String, dynamic>>> list() {
    lists++;
    return onList?.call() ?? Future.value(rows);
  }

  @override
  Future<bool> markRead(String id) {
    marks++;
    return onMark?.call() ?? Future.value(true);
  }
}
