import 'package:flutter/foundation.dart';

import 'work_attendance_models.dart';

enum MockWorkflowRole { jobSeeker, employer, administrator }

enum MockWorkflowFailureKind {
  authentication,
  permission,
  invalidFixture,
  invalidEvidence,
  ineligible,
  busy,
  staleContext,
}

/// Safe typed failures contain no identities, descriptions or object paths.
class MockWorkflowFailure implements Exception {
  const MockWorkflowFailure(this.kind);
  final MockWorkflowFailureKind kind;
  @override
  String toString() => 'Mock workflow rejected: ${kind.name}';
}

@immutable
final class MockWorkflowUser {
  MockWorkflowUser({
    required String userId,
    required this.role,
    this.active = true,
    Iterable<String> managedCompanies = const [],
  }) : userId = workUuid(userId),
       managedCompanies = Set.unmodifiable(managedCompanies.map(workUuid));
  final String userId;
  final MockWorkflowRole role;
  final bool active;
  // Synthetic outcome of can_manage_company_jobs, NOT its deployed internals.
  final Set<String> managedCompanies;
}

/// Fixed initial presets only. There is no arbitrary status setter, existing
/// submission seed, request-more operation, verification or second-round API.
@immutable
final class MockWorkflowAssignmentFixture {
  MockWorkflowAssignmentFixture.awaitingEvidence({
    required String assignmentId,
    required String workerId,
    required String companyId,
    DateTime? checkInAt,
    DateTime? checkOutAt,
  }) : this._(
         assignmentId,
         workerId,
         companyId,
         WorkAssignmentStatus.awaitingVerification,
         checkInAt,
         checkOutAt,
       );
  MockWorkflowAssignmentFixture.scheduled({
    required String assignmentId,
    required String workerId,
    required String companyId,
  }) : this._(
         assignmentId,
         workerId,
         companyId,
         WorkAssignmentStatus.scheduled,
         null,
         null,
       );
  MockWorkflowAssignmentFixture._(
    String id,
    String worker,
    String company,
    this.status,
    DateTime? checkIn,
    DateTime? checkOut,
  ) : assignmentId = workUuid(id),
      workerId = workUuid(worker),
      companyId = workUuid(company),
      checkInAt = checkIn?.toUtc(),
      checkOutAt = checkOut?.toUtc() {
    // valid_attendance_order is a table constraint in the original migration.
    if (checkOutAt != null &&
        (checkInAt == null || checkOutAt!.isBefore(checkInAt!))) {
      throw const MockWorkflowFailure(MockWorkflowFailureKind.invalidFixture);
    }
  }
  final String assignmentId, workerId, companyId;
  final WorkAssignmentStatus status;
  final DateTime? checkInAt, checkOutAt;
}

/// Synthetic Storage metadata, never a file or a successful live upload claim.
/// Invalid metadata can be seeded to test rejection. Bytes are not accepted.
@immutable
final class MockWorkflowUploadedObject {
  MockWorkflowUploadedObject({
    required this.path,
    required String ownerId,
    required this.mimeType,
    required this.sizeBytes,
    this.bucket = 'work-evidence',
  }) : ownerId = workUuid(ownerId);
  final String path, ownerId, mimeType, bucket;
  final int? sizeBytes;
}

/// An explicitly simulated account session, scoped to its creating store.
/// This is not an authentication provider and cannot authorize Supabase access.
final class MockWorkflowSession {
  MockWorkflowSession._(this._store, this._userId);
  final MockWorkAttendanceWorkflow _store;
  String? _userId;
  int _generation = 0;
  String? get userId => _userId;
  void switchAccount(String? userId) {
    final next = _store._knownActor(userId);
    if (next == _userId) return;
    _userId = next;
    ++_generation;
  }
}

@immutable
final class MockWorkflowSubmission {
  MockWorkflowSubmission._(
    this.submittedBy,
    this.description,
    List<String> paths,
    this.submittedAt,
  ) : storagePaths = List.unmodifiable(paths);
  int get submissionRound => 1;
  int get fileCount => storagePaths.length;
  final String submittedBy, description;
  final List<String> storagePaths;
  final DateTime submittedAt;
}

/// Domain snapshot, not an invented RPC projection. Includes only synthetic
/// assignment/attendance and formally submitted evidence, never upload fixtures.
@immutable
final class MockWorkflowSnapshot {
  MockWorkflowSnapshot._(
    this._store,
    this._session,
    this._generation,
    this.revision,
    _MockAssignment row,
  ) : assignmentId = row.fixture.assignmentId,
      workerId = row.fixture.workerId,
      companyId = row.fixture.companyId,
      assignmentStatus = row.fixture.status,
      verificationStatus = row.submission == null
          ? WorkVerificationStatus.notSubmitted
          : WorkVerificationStatus.pendingReview,
      checkInAt = row.fixture.checkInAt,
      checkOutAt = row.fixture.checkOutAt,
      updatedAt = row.updatedAt,
      submissions = List.unmodifiable([
        if (row.submission != null) row.submission!,
      ]);
  final MockWorkAttendanceWorkflow _store;
  final MockWorkflowSession _session;
  final int _generation;
  final int revision;
  final String assignmentId, workerId, companyId;
  final WorkAssignmentStatus assignmentStatus;
  final WorkVerificationStatus verificationStatus;
  final DateTime? checkInAt, checkOutAt, updatedAt;
  final List<MockWorkflowSubmission> submissions;
}

/// Fake-only, instance-owned authority. No SDK, network, file I/O, callbacks,
/// global state, ledger manipulation or production repository/UI integration.
/// A synchronous validation/commit after one async boundary simulates an atomic
/// transaction in one Dart isolate; it does NOT test PostgreSQL locks or RLS.
final class MockWorkAttendanceWorkflow {
  MockWorkAttendanceWorkflow({
    required Iterable<MockWorkflowUser> users,
    required Iterable<MockWorkflowAssignmentFixture> assignments,
    Iterable<MockWorkflowUploadedObject> uploadedObjects = const [],
    DateTime? simulatedStart,
  }) : _nextTimestamp = (simulatedStart ?? DateTime.utc(2026, 1, 1)).toUtc() {
    for (final user in users) {
      if (_users.containsKey(user.userId)) _badFixture();
      _users[user.userId] = user;
    }
    for (final fixture in assignments) {
      if (_assignments.containsKey(fixture.assignmentId) ||
          !_users.containsKey(fixture.workerId)) {
        _badFixture();
      }
      _assignments[fixture.assignmentId] = _MockAssignment(fixture);
    }
    for (final object in uploadedObjects) {
      final key = (object.bucket, object.path);
      if (_objects.containsKey(key)) _badFixture();
      _objects[key] = object;
    }
  }
  final _users = <String, MockWorkflowUser>{};
  final _assignments = <String, _MockAssignment>{};
  final _objects = <(String, String), MockWorkflowUploadedObject>{};
  final _usedPaths = <String>{};
  final _pending = <String>{};
  DateTime _nextTimestamp;

  static Never _badFixture() =>
      throw const MockWorkflowFailure(MockWorkflowFailureKind.invalidFixture);
  String? _knownActor(String? id) {
    if (id == null) return null;
    final actor = workUuid(id);
    if (!_users.containsKey(actor)) {
      throw const MockWorkflowFailure(MockWorkflowFailureKind.permission);
    }
    return actor;
  }

  MockWorkflowSession openSession(String? userId) =>
      MockWorkflowSession._(this, _knownActor(userId));

  MockWorkflowUser _authenticated(MockWorkflowSession session) {
    if (!identical(session._store, this)) {
      throw const MockWorkflowFailure(MockWorkflowFailureKind.permission);
    }
    if (session.userId == null) {
      throw const MockWorkflowFailure(MockWorkflowFailureKind.authentication);
    }
    return _users[session.userId]!;
  }

  MockWorkflowSnapshot _snapshot(
    MockWorkflowSession session,
    _MockAssignment row,
  ) => MockWorkflowSnapshot._(
    this,
    session,
    session._generation,
    row.revision,
    row,
  );

  /// Mirrors list_my_work_assignments' active worker filtering. Other roles and
  /// inactive accounts get no worker rows; unauthenticated callers are rejected.
  List<MockWorkflowSnapshot> readWorkerAssignments(
    MockWorkflowSession session,
  ) {
    final actor = _authenticated(session);
    if (!actor.active || actor.role != MockWorkflowRole.jobSeeker) {
      return const [];
    }
    return List.unmodifiable(
      _assignments.values
          .where((row) => row.fixture.workerId == actor.userId)
          .map((row) => _snapshot(session, row)),
    );
  }

  List<MockWorkflowSnapshot> readCompanyAssignments(
    MockWorkflowSession session,
    String companyId,
  ) {
    final actor = _authenticated(session);
    final company = workUuid(companyId);
    if (!actor.active ||
        actor.role != MockWorkflowRole.employer ||
        !actor.managedCompanies.contains(company)) {
      throw const MockWorkflowFailure(MockWorkflowFailureKind.permission);
    }
    return List.unmodifiable(
      _assignments.values
          .where((row) => row.fixture.companyId == company)
          .map((row) => _snapshot(session, row)),
    );
  }

  bool isCurrent(MockWorkflowSnapshot snapshot, MockWorkflowSession session) =>
      identical(session._store, this) &&
      identical(snapshot._store, this) &&
      identical(snapshot._session, session) &&
      snapshot._generation == session._generation &&
      snapshot.revision == _assignments[snapshot.assignmentId]?.revision;

  /// ONLY not_submitted -> pending_review. No idempotent replay or round-2
  /// capability is implied. Typed Dart lists represent ordinary text[] inputs.
  Future<MockWorkflowSubmission> submitFirstEvidence({
    required MockWorkflowSession session,
    required String assignmentId,
    required String? description,
    required List<String?>? storagePaths,
  }) async {
    final actor = _authenticated(session);
    final id = workUuid(assignmentId);
    final row = _assignments[id];
    if (row == null ||
        row.fixture.workerId != actor.userId ||
        !actor.active ||
        actor.role != MockWorkflowRole.jobSeeker) {
      throw const MockWorkflowFailure(MockWorkflowFailureKind.permission);
    }
    if (!_pending.add(id)) {
      throw const MockWorkflowFailure(MockWorkflowFailureKind.busy);
    }
    final generation = session._generation;
    final selected = storagePaths == null
        ? null
        : List<String?>.of(storagePaths);
    try {
      await Future<void>.value();
      if (session._generation != generation || session.userId != actor.userId) {
        throw const MockWorkflowFailure(MockWorkflowFailureKind.staleContext);
      }
      if (row.fixture.status != WorkAssignmentStatus.awaitingVerification ||
          row.submission != null ||
          row.fixture.checkInAt == null ||
          row.fixture.checkOutAt == null) {
        throw const MockWorkflowFailure(MockWorkflowFailureKind.ineligible);
      }
      // SQL btrim(text) strips ordinary spaces, not Dart's broader trim set.
      final normalized = description?.replaceAll(RegExp(r'^ +| +$'), '');
      if (normalized == null ||
          normalized.runes.isEmpty ||
          normalized.runes.length > 2000 ||
          selected == null ||
          selected.isEmpty ||
          selected.length > 5 ||
          selected.any((path) => path == null) ||
          selected.toSet().length != selected.length) {
        throw const MockWorkflowFailure(
          MockWorkflowFailureKind.invalidEvidence,
        );
      }
      final pattern = RegExp(
        '^$id/'
        r'[A-Za-z0-9][A-Za-z0-9._-]{0,199}\.(jpg|jpeg|png|webp|pdf)$',
      );
      final paths = <String>[];
      for (final value in selected) {
        final path = value!;
        final object = _objects[('work-evidence', path)];
        if (!pattern.hasMatch(path) ||
            object == null ||
            object.ownerId != actor.userId ||
            object.sizeBytes == null ||
            object.sizeBytes! < 1 ||
            object.sizeBytes! > 10485760 ||
            !const [
              'image/jpeg',
              'image/png',
              'image/webp',
              'application/pdf',
            ].contains(object.mimeType) ||
            _usedPaths.contains(path)) {
          throw const MockWorkflowFailure(
            MockWorkflowFailureKind.invalidEvidence,
          );
        }
        paths.add(path);
      }
      // No awaits or user callbacks inside this commit. Failed validation has
      // consumed neither object registrations, a round, nor a simulated time.
      final submission = MockWorkflowSubmission._(
        actor.userId,
        normalized,
        paths,
        _nextTimestamp,
      );
      row.submission = submission;
      row.updatedAt = _nextTimestamp;
      row.revision++;
      _usedPaths.addAll(paths);
      _nextTimestamp = _nextTimestamp.add(const Duration(microseconds: 1));
      return submission;
    } finally {
      _pending.remove(id);
    }
  }
}

class _MockAssignment {
  _MockAssignment(this.fixture);
  final MockWorkflowAssignmentFixture fixture;
  MockWorkflowSubmission? submission;
  DateTime? updatedAt;
  int revision = 0;
}
