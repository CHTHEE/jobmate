import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_attendance_mock_workflow.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';

String uid(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

void main() {
  late MockWorkAttendanceWorkflow store;
  late MockWorkflowSession worker, manager;
  final workerId = uid(1), otherWorker = uid(2), managerId = uid(3);
  final company = uid(4), assignment = uid(5), otherAssignment = uid(6);
  final inactiveId = uid(7), outsiderManager = uid(8), adminId = uid(9);
  final start = DateTime.utc(2026, 11, 5, 10);
  String path([String name = 'proof.pdf']) => '$assignment/$name';
  MockWorkflowUploadedObject object({
    String? name,
    String? owner,
    String mime = 'application/pdf',
    int? size = 100,
    String bucket = 'work-evidence',
  }) => MockWorkflowUploadedObject(
    path: path(name ?? 'proof.pdf'),
    ownerId: owner ?? workerId,
    mimeType: mime,
    sizeBytes: size,
    bucket: bucket,
  );
  List<MockWorkflowUser> users() => [
    MockWorkflowUser(userId: workerId, role: MockWorkflowRole.jobSeeker),
    MockWorkflowUser(userId: otherWorker, role: MockWorkflowRole.jobSeeker),
    MockWorkflowUser(
      userId: managerId,
      role: MockWorkflowRole.employer,
      managedCompanies: [company],
    ),
    MockWorkflowUser(
      userId: inactiveId,
      role: MockWorkflowRole.jobSeeker,
      active: false,
    ),
    MockWorkflowUser(userId: outsiderManager, role: MockWorkflowRole.employer),
    MockWorkflowUser(userId: adminId, role: MockWorkflowRole.administrator),
  ];
  MockWorkflowAssignmentFixture fixture({
    String? id,
    String? owner,
    bool scheduled = false,
    bool missingIn = false,
    bool missingOut = false,
  }) => scheduled
      ? MockWorkflowAssignmentFixture.scheduled(
          assignmentId: id ?? assignment,
          workerId: owner ?? workerId,
          companyId: company,
        )
      : MockWorkflowAssignmentFixture.awaitingEvidence(
          assignmentId: id ?? assignment,
          workerId: owner ?? workerId,
          companyId: company,
          checkInAt: missingIn ? null : DateTime.utc(2026, 11, 5, 1),
          checkOutAt: missingOut ? null : DateTime.utc(2026, 11, 5, 9),
        );
  MockWorkAttendanceWorkflow build({
    List<MockWorkflowUploadedObject>? objects,
    List<MockWorkflowAssignmentFixture>? rows,
  }) => MockWorkAttendanceWorkflow(
    users: users(),
    assignments:
        rows ?? [fixture(), fixture(id: otherAssignment, owner: otherWorker)],
    uploadedObjects:
        objects ?? [object(), object(name: 'photo.png', mime: 'image/png')],
    simulatedStart: start,
  );
  Future<MockWorkflowSubmission> submit({
    MockWorkflowSession? session,
    String? id,
    String? description = '  Completed shift  ',
    List<String?>? paths,
  }) => store.submitFirstEvidence(
    session: session ?? worker,
    assignmentId: id ?? assignment,
    description: description,
    storagePaths: paths ?? [path()],
  );
  Matcher failure(MockWorkflowFailureKind kind) => throwsA(
    isA<MockWorkflowFailure>().having((error) => error.kind, 'kind', kind),
  );

  setUp(() {
    store = build();
    worker = store.openSession(workerId);
    manager = store.openSession(managerId);
  });

  test('authorized worker and company reads isolate synthetic assignments', () {
    final mine = store.readWorkerAssignments(worker);
    expect(mine.map((row) => row.assignmentId), [assignment]);
    expect(
      mine.single.assignmentStatus,
      WorkAssignmentStatus.awaitingVerification,
    );
    expect(mine.single.verificationStatus, WorkVerificationStatus.notSubmitted);
    expect(mine.single.submissions, isEmpty);
    expect(store.readCompanyAssignments(manager, company), hasLength(2));
    expect(
      store
          .readWorkerAssignments(store.openSession(otherWorker))
          .single
          .assignmentId,
      otherAssignment,
    );
    expect(store.readWorkerAssignments(manager), isEmpty);
    expect(store.readWorkerAssignments(store.openSession(inactiveId)), isEmpty);
    expect(store.readWorkerAssignments(store.openSession(adminId)), isEmpty);
  });

  test('first submission is published to both authorized views with round and UTC time', () async {
    final before = store.readWorkerAssignments(worker).single;
    final result = await submit(paths: [path('photo.png'), path()]);
    expect(result.submissionRound, 1);
    expect(result.description, 'Completed shift');
    expect(result.storagePaths, [path('photo.png'), path()]);
    expect(result.fileCount, 2);
    expect(result.submittedAt, start);
    expect(result.submittedAt.isUtc, isTrue);
    for (final (row, session) in [
      (store.readWorkerAssignments(worker).single, worker),
      (
        store
            .readCompanyAssignments(manager, company)
            .firstWhere((row) => row.assignmentId == assignment),
        manager,
      ),
    ]) {
      expect(row.verificationStatus, WorkVerificationStatus.pendingReview);
      expect(row.assignmentStatus, WorkAssignmentStatus.awaitingVerification);
      expect(row.updatedAt, start);
      expect(row.submissions.single, same(result));
      expect(store.isCurrent(row, session), isTrue);
    }
    expect(before.verificationStatus, WorkVerificationStatus.notSubmitted);
    expect(before.submissions, isEmpty);
    expect(store.isCurrent(before, worker), isFalse);
    expect(
      store.isCurrent(store.readWorkerAssignments(worker).single, worker),
      isTrue,
    );
  });

  test('snapshots, users and submission collections are immutable', () async {
    final rows = store.readWorkerAssignments(worker);
    expect(() => rows.clear(), throwsUnsupportedError);
    expect(() => rows.single.submissions.clear(), throwsUnsupportedError);
    final user = users().firstWhere((u) => u.userId == managerId);
    expect(() => user.managedCompanies.clear(), throwsUnsupportedError);
    final result = await submit();
    expect(
      () => result.storagePaths.add(path('other.pdf')),
      throwsUnsupportedError,
    );
  });

  test('duplicate and concurrent calls cannot create a second round', () async {
    final first = submit();
    await expectLater(submit(), failure(MockWorkflowFailureKind.busy));
    expect((await first).submissionRound, 1);
    await expectLater(submit(), failure(MockWorkflowFailureKind.ineligible));
    expect(
      store.readWorkerAssignments(worker).single.submissions,
      hasLength(1),
    );
  });

  test('late invalid file rolls back the whole batch and permits corrected first submission', () async {
    await expectLater(
      submit(paths: [path(), path('missing.pdf')]),
      failure(MockWorkflowFailureKind.invalidEvidence),
    );
    final after = store.readWorkerAssignments(worker).single;
    expect(after.submissions, isEmpty);
    expect(after.updatedAt, isNull);
    expect(after.revision, 0);
    expect(after.verificationStatus, WorkVerificationStatus.notSubmitted);
    final corrected = await submit();
    expect(corrected.submittedAt, start);
    expect(corrected.submissionRound, 1);
  });

  for (final actor in [null, uid(2), uid(3), uid(7), uid(8), uid(9)]) {
    test('unauthorized actor $actor cannot submit', () async {
      await expectLater(
        submit(session: store.openSession(actor)),
        failure(
          actor == null
              ? MockWorkflowFailureKind.authentication
              : MockWorkflowFailureKind.permission,
        ),
      );
      expect(store.readWorkerAssignments(worker).single.submissions, isEmpty);
    });
  }

  test(
    'foreign or nonexistent assignments and unknown actors are rejected',
    () async {
      await expectLater(
        submit(id: otherAssignment),
        failure(MockWorkflowFailureKind.permission),
      );
      await expectLater(
        submit(id: uid(999)),
        failure(MockWorkflowFailureKind.permission),
      );
      expect(
        () => store.openSession(uid(999)),
        failure(MockWorkflowFailureKind.permission),
      );
      expect(() => store.openSession('not-a-uuid'), throwsFormatException);
    },
  );

  test('company reads reject missing authorization and anonymous sessions', () {
    for (final actor in [workerId, outsiderManager, inactiveId, adminId]) {
      expect(
        () => store.readCompanyAssignments(store.openSession(actor), company),
        failure(MockWorkflowFailureKind.permission),
      );
    }
    expect(
      () => store.readCompanyAssignments(manager, uid(88)),
      failure(MockWorkflowFailureKind.permission),
    );
    expect(
      () => store.readWorkerAssignments(store.openSession(null)),
      failure(MockWorkflowFailureKind.authentication),
    );
  });

  for (final mode in ['scheduled', 'no attendance', 'no checkout']) {
    test('$mode rejects submission without changing state', () async {
      store = build(
        rows: [
          fixture(
            scheduled: mode == 'scheduled',
            missingIn: mode == 'no attendance',
            missingOut: mode != 'scheduled',
          ),
        ],
      );
      worker = store.openSession(workerId);
      await expectLater(submit(), failure(MockWorkflowFailureKind.ineligible));
      expect(store.readWorkerAssignments(worker).single.submissions, isEmpty);
    });
  }

  test('invalid attendance ordering is rejected at fixture boundary like table CHECK', () {
    expect(
      () => MockWorkflowAssignmentFixture.awaitingEvidence(
        assignmentId: assignment,
        workerId: workerId,
        companyId: company,
        checkInAt: DateTime.utc(2026, 11, 5, 9),
        checkOutAt: DateTime.utc(2026, 11, 5, 1),
      ),
      failure(MockWorkflowFailureKind.invalidFixture),
    );
    expect(
      () => fixture(missingIn: true),
      failure(MockWorkflowFailureKind.invalidFixture),
    );
  });

  for (final description in <String?>[
    null,
    '',
    '   ',
    List.filled(2001, 'x').join(),
  ]) {
    test(
      'invalid description length ${description?.length} rejects atomically',
      () async {
        await expectLater(
          submit(description: description),
          failure(MockWorkflowFailureKind.invalidEvidence),
        );
        expect(store.readWorkerAssignments(worker).single.submissions, isEmpty);
      },
    );
  }

  test(
    'SQL btrim space semantics and Unicode character limit are preserved',
    () async {
      final text = List.filled(2000, '😀').join();
      expect(
        (await submit(description: ' $text ')).description.runes.length,
        2000,
      );
      final fresh = build();
      final result = await fresh.submitFirstEvidence(
        session: fresh.openSession(workerId),
        assignmentId: assignment,
        description: '\t',
        storagePaths: [path()],
      );
      expect(result.description, '\t'); // PostgreSQL btrim does not strip tabs.
    },
  );

  for (final paths in <List<String?>?>[
    null,
    [],
    [null],
    ['', ''],
    ['duplicate', 'duplicate'],
    List.filled(6, 'file'),
  ]) {
    test(
      'null, empty, duplicate or over-count path selection ${paths?.length} rejects',
      () async {
        await expectLater(
          store.submitFirstEvidence(
            session: worker,
            assignmentId: assignment,
            description: 'Work',
            storagePaths: paths,
          ),
          failure(MockWorkflowFailureKind.invalidEvidence),
        );
      },
    );
  }

  for (final invalid in [
    '../proof.pdf',
    'folder/proof.pdf',
    'proof.exe',
    'proof.PDF',
    '.hidden.pdf',
    '',
  ]) {
    test(
      'invalid scoped filename $invalid rejects even with an object fixture',
      () async {
        store = build(objects: [object(name: invalid)]);
        worker = store.openSession(workerId);
        await expectLater(
          submit(paths: [path(invalid)]),
          failure(MockWorkflowFailureKind.invalidEvidence),
        );
      },
    );
  }

  for (final mode in [
    'missing',
    'foreign owner',
    'wrong bucket',
    'unsupported MIME',
    'empty',
    'oversized',
    'missing size',
  ]) {
    test('object metadata: $mode rejects before commit', () async {
      store = build(
        objects: mode == 'missing'
            ? []
            : [
                object(
                  owner: mode == 'foreign owner' ? otherWorker : null,
                  bucket: mode == 'wrong bucket'
                      ? 'public-bucket'
                      : 'work-evidence',
                  mime: mode == 'unsupported MIME'
                      ? 'text/plain'
                      : 'application/pdf',
                  size: mode == 'empty'
                      ? 0
                      : mode == 'oversized'
                      ? 10485761
                      : mode == 'missing size'
                      ? null
                      : 100,
                ),
              ],
      );
      worker = store.openSession(workerId);
      await expectLater(
        submit(),
        failure(MockWorkflowFailureKind.invalidEvidence),
      );
      expect(store.readWorkerAssignments(worker).single.submissions, isEmpty);
    });
  }

  test('1 byte and exact 10 MiB metadata accepted; MIME need not match extension in SQL', () async {
    store = build(
      objects: [
        object(size: 1),
        object(name: 'photo.jpg', size: 10485760),
      ],
    );
    worker = store.openSession(workerId);
    expect((await submit(paths: [path(), path('photo.jpg')])).fileCount, 2);
  });

  test('cross-assignment and previously submitted paths cannot be registered again', () async {
    await submit();
    await expectLater(
      submit(paths: [path()]),
      failure(MockWorkflowFailureKind.ineligible),
    );
    final secondWorker = store.openSession(otherWorker);
    await expectLater(
      submit(session: secondWorker, id: otherAssignment, paths: [path()]),
      failure(MockWorkflowFailureKind.invalidEvidence),
    );
  });

  test(
    'switch account away and back invalidates pending commit and old snapshots',
    () async {
      final before = store.readWorkerAssignments(worker).single;
      final pending = submit();
      worker.switchAccount(otherWorker);
      worker.switchAccount(workerId);
      await expectLater(pending, failure(MockWorkflowFailureKind.staleContext));
      expect(store.isCurrent(before, worker), isFalse);
      expect(store.readWorkerAssignments(worker).single.submissions, isEmpty);
      expect((await submit()).submittedAt, start);
    },
  );

  test(
    'caller mutation of path list cannot change captured operation',
    () async {
      final selected = <String?>[path()];
      final pending = submit(paths: selected);
      selected[0] = path('missing.pdf');
      expect((await pending).storagePaths, [path()]);
    },
  );

  test(
    'fresh stores have no shared state and reject foreign session provenance',
    () async {
      final fresh = build();
      await submit();
      final freshSession = fresh.openSession(workerId);
      expect(
        fresh.readWorkerAssignments(freshSession).single.submissions,
        isEmpty,
      );
      expect(
        () => fresh.readWorkerAssignments(worker),
        failure(MockWorkflowFailureKind.permission),
      );
      expect(
        fresh.isCurrent(
          store.readWorkerAssignments(worker).single,
          freshSession,
        ),
        isFalse,
      );
    },
  );

  test(
    'independent assignments get store-allocated monotonic timestamps',
    () async {
      store = build(
        objects: [
          object(),
          MockWorkflowUploadedObject(
            path: '$otherAssignment/other.pdf',
            ownerId: otherWorker,
            mimeType: 'application/pdf',
            sizeBytes: 100,
          ),
        ],
      );
      worker = store.openSession(workerId);
      final first = await submit();
      final second = await submit(
        session: store.openSession(otherWorker),
        id: otherAssignment,
        paths: ['$otherAssignment/other.pdf'],
      );
      expect(first.submissionRound, 1);
      expect(second.submissionRound, 1);
      expect(
        second.submittedAt,
        first.submittedAt.add(const Duration(microseconds: 1)),
      );
    },
  );

  test('logout invalidates a pending submission and leaks no snapshot to the next account', () async {
    final before = store.readWorkerAssignments(worker).single;
    final pending = submit();
    worker.switchAccount(null);
    await expectLater(pending, failure(MockWorkflowFailureKind.staleContext));
    expect(store.isCurrent(before, worker), isFalse);
    worker.switchAccount(otherWorker);
    expect(
      store.readWorkerAssignments(worker).single.assignmentId,
      otherAssignment,
    );
    expect(
      store
          .readCompanyAssignments(manager, company)
          .firstWhere((row) => row.assignmentId == assignment)
          .submissions,
      isEmpty,
    );
  });

  test('duplicate fixture identities are rejected rather than silently overwritten', () {
    expect(
      () => build(rows: [fixture(), fixture()]),
      failure(MockWorkflowFailureKind.invalidFixture),
    );
    expect(
      () => build(objects: [object(), object()]),
      failure(MockWorkflowFailureKind.invalidFixture),
    );
    expect(
      () => MockWorkAttendanceWorkflow(
        users: [users().first, users().first],
        assignments: [],
      ),
      failure(MockWorkflowFailureKind.invalidFixture),
    );
  });
}
