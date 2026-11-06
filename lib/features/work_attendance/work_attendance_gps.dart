import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'work_attendance_models.dart';

/// Read-only projection. GPS is device-reported, not proof of attendance.
class WorkAttendanceGpsPoint {
  WorkAttendanceGpsPoint.fromJson(Map<String, dynamic> row, String prefix)
    : recordedAt = _timestamp(row['${prefix}_at']),
      status = row['${prefix}_location_status'] as String?,
      latitude = _coordinate(row['${prefix}_latitude'], 90),
      longitude = _coordinate(row['${prefix}_longitude'], 180) {
    if (![null, 'granted', 'denied', 'unavailable'].contains(status) ||
        (latitude == null) != (longitude == null) ||
        (status != 'granted' && latitude != null) ||
        (recordedAt == null && (status != null || latitude != null))) {
      throw const FormatException('Invalid attendance GPS data');
    }
  }
  final DateTime? recordedAt;
  final String? status;
  final double? latitude, longitude;
  Uri? get mapsLink => latitude == null
      ? null
      : Uri.https('www.google.com', '/maps/search/', {
          'api': '1',
          'query': '$latitude,$longitude',
        });
  String get label => recordedAt == null
      ? 'Not recorded yet'
      : switch (status) {
          'granted' =>
            latitude == null ? 'Granted — coordinates unavailable' : 'Captured',
          'denied' => 'Permission denied',
          'unavailable' => 'Unavailable',
          _ => 'Location status not recorded',
        };

  static double? _coordinate(Object? raw, int limit) {
    if (raw == null) return null;
    final value = raw is num
        ? raw.toDouble()
        : raw is String
        ? double.tryParse(raw)
        : null;
    if (value == null || !value.isFinite || value.abs() > limit) {
      throw const FormatException('Invalid GPS coordinate');
    }
    return value;
  }

  static DateTime? _timestamp(Object? raw) {
    if (raw == null) return null;
    if (raw is! String ||
        !RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(raw)) {
      throw const FormatException('Invalid attendance timestamp');
    }
    final time = DateTime.tryParse(raw);
    if (time == null) {
      throw const FormatException('Invalid attendance timestamp');
    }
    return time.toUtc();
  }
}

class WorkAttendanceGpsRecord {
  WorkAttendanceGpsRecord.fromJson(Map<String, dynamic> row)
    : assignmentId = workUuid(row['assignment_id']),
      companyId = workUuid(row['company_id']),
      checkIn = WorkAttendanceGpsPoint.fromJson(row, 'check_in'),
      checkOut = WorkAttendanceGpsPoint.fromJson(row, 'check_out') {
    // Missing columns must not masquerade as a valid empty legacy projection.
    for (final prefix in ['check_in', 'check_out']) {
      for (final suffix in ['at', 'location_status', 'latitude', 'longitude']) {
        if (!row.containsKey('${prefix}_$suffix')) {
          throw const FormatException('Incomplete GPS projection');
        }
      }
    }
    if (checkOut.recordedAt != null &&
        (checkIn.recordedAt == null ||
            checkOut.recordedAt!.isBefore(checkIn.recordedAt!))) {
      throw const FormatException('Invalid attendance order');
    }
  }
  final String assignmentId, companyId;
  final WorkAttendanceGpsPoint checkIn, checkOut;
}

abstract class WorkAttendanceGpsSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<List<Map<String, dynamic>>> read(
    String companyId,
    String assignmentId,
  );
}

class SupabaseWorkAttendanceGpsSource implements WorkAttendanceGpsSource {
  SupabaseWorkAttendanceGpsSource(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  @override
  Future<List<Map<String, dynamic>>> read(
    String companyId,
    String assignmentId,
  ) async {
    final actor = userId;
    if (actor == null) throw const AuthException('Authentication required');
    final data = await client.rpc(
      'read_employer_work_attendance_gps',
      params: {
        'p_company_id': workUuid(companyId),
        'p_assignment_id': workUuid(assignmentId),
      },
    );
    if (userId != actor) throw const AuthException('Account changed');
    if (data is! List || data.any((row) => row is! Map)) {
      throw const FormatException('Invalid GPS response');
    }
    return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }
}

/// Owned by a single dialog. A session change permanently invalidates this view,
/// including switching away and back while a request is in flight.
class WorkAttendanceGpsRepository extends ChangeNotifier {
  WorkAttendanceGpsRepository(this.source, this.companyId, this.assignmentId)
    : _actor = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id != _actor || source.userId != _actor) {
        _invalidated = true;
        ++_request;
        _record = null;
        loading = false;
        error = 'Your account changed. Close this GPS view and reopen it.';
        if (!_disposed) notifyListeners();
      }
    });
  }
  final WorkAttendanceGpsSource source;
  final String companyId, assignmentId;
  final String? _actor;
  late final StreamSubscription<String?> _subscription;
  bool _disposed = false, _invalidated = false;
  int _request = 0;
  bool loading = false;
  String? error;
  WorkAttendanceGpsRecord? _record;
  bool get current =>
      !_disposed && !_invalidated && _actor != null && source.userId == _actor;
  WorkAttendanceGpsRecord? get record => current ? _record : null;

  Future<void> load() async {
    if (!current) return;
    final request = ++_request;
    _record = null;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final rows = await source.read(
        workUuid(companyId),
        workUuid(assignmentId),
      );
      if (!current || request != _request) return;
      if (rows.length != 1) throw const FormatException('Ambiguous GPS record');
      final value = WorkAttendanceGpsRecord.fromJson(rows.single);
      if (value.companyId != companyId || value.assignmentId != assignmentId) {
        throw const FormatException('GPS scope mismatch');
      }
      _record = value;
    } catch (failure) {
      if (!current || request != _request) return;
      error = failure is PostgrestException && failure.code == '42501'
          ? 'You are not authorized to view this assignment’s GPS.'
          : failure is AuthException
          ? 'Sign in again to view attendance GPS.'
          : 'Attendance GPS could not be loaded. Check access and connectivity, then retry.';
    }
    if (!current || request != _request) return;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_request;
    _record = null;
    _subscription.cancel();
    super.dispose();
  }
}

class WorkAttendanceGpsDialog extends StatefulWidget {
  const WorkAttendanceGpsDialog({
    super.key,
    required this.repository,
    this.openMap,
  });
  final WorkAttendanceGpsRepository repository;
  final Future<bool> Function(Uri)? openMap;
  @override
  State<WorkAttendanceGpsDialog> createState() =>
      _WorkAttendanceGpsDialogState();
}

class _WorkAttendanceGpsDialogState extends State<WorkAttendanceGpsDialog> {
  @override
  void initState() {
    super.initState();
    widget.repository.load();
  }

  Future<void> _open(WorkAttendanceGpsPoint point) async {
    if (!widget.repository.current ||
        widget.repository.record == null ||
        point.mapsLink == null) {
      return;
    }
    final uri = point.mapsLink!;
    try {
      final opened =
          await (widget.openMap?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened) throw StateError('Map unavailable');
    } catch (_) {
      if (mounted && widget.repository.current) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open Google Maps.')),
        );
      }
    }
  }

  Widget _point(String title, WorkAttendanceGpsPoint point) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title GPS: ${point.label}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (point.recordedAt != null)
          Text('Recorded: ${_myt(point.recordedAt!)}'),
        if (point.latitude != null) ...[
          SelectableText(
            'Latitude: ${point.latitude}\nLongitude: ${point.longitude}',
          ),
          TextButton.icon(
            onPressed: () => _open(point),
            icon: const Icon(Icons.open_in_new),
            label: Text('Open $title in Google Maps'),
          ),
        ],
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repository,
    builder: (context, _) {
      final repository = widget.repository;
      final record = repository.record;
      return AlertDialog(
        title: const Text('Attendance GPS'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!repository.current)
                  const Text(
                    'Your account changed. Close this GPS view and reopen it.',
                  )
                else if (repository.loading)
                  const Center(child: CircularProgressIndicator())
                else if (repository.error != null)
                  Text(repository.error!)
                else if (record != null) ...[
                  const Text(
                    'Device-reported location does not prove attendance. Opening a map shares these coordinates with Google.',
                  ),
                  _point('Check-in', record.checkIn),
                  _point('Check-out', record.checkOut),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (repository.current)
            TextButton(
              onPressed: repository.loading ? null : repository.load,
              child: const Text('Refresh GPS'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

String _myt(DateTime time) {
  final value = time.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)} MYT';
}
