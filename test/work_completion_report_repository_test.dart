import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_data.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String id(int value) =>
    '00000000-0000-0000-0000-${value.toString().padLeft(12, '0')}';
const start = '2026-11-20T15:00:00Z';
const end = '2026-11-20T17:00:00Z';
const verifiedAt = '2026-11-21T09:00:00Z';

class FakeSource implements WorkCompletionReportSource {
  final changes = StreamController<void>.broadcast(sync: true);
  String? actor = id(1), company;
  String? role = 'job_seeker';
  Map<String, dynamic>? access;
  String? requestedCompany;
  bool denyEvidence = false, failWorkflow = false, failDisplay = false;
  void Function()? duringDisplay;
  final row = <String, dynamic>{
    'assignment_id': id(2),
    'application_id': id(3),
    'job_id': id(4),
    'company_id': id(5),
    'company_name': 'JobMate Company',
    'worker_id': id(1),
    'job_title': 'Retail assistant',
    'workplace_location': 'Kuala Lumpur',
    'scheduled_start': start,
    'scheduled_end': end,
    'check_in_at': start,
    'check_out_at': end,
    'verified_at': verifiedAt,
    'assignment_status': 'completed',
    'verification_status': 'verified',
  };
  final context = <String, dynamic>{
    'assignment_id': id(2),
    'contract_version': 1,
    'viewer_role': 'worker',
    'attendance_complete': true,
    'latest_round': 2,
    'assignment_status': 'completed',
    'verification_status': 'verified',
    'attempts': [],
    'history': [
      <String, dynamic>{
        'assignment_id': id(2),
        'verification_id': id(7),
        'action': 'verified',
        'submission_round': 2,
        'performed_by': id(8),
        'created_at': verifiedAt,
        'note': 'Private review reason',
      },
    ],
  };
  final files = [
    file(10, 1, 'Previous round'),
    file(11, 2, 'Current round'),
    file(12, 2, 'Current round'),
  ];
  static Map<String, dynamic> file(int key, int round, String description) => {
    'evidence_id': id(key),
    'submission_round': round,
    'description': description,
    'storage_path': '${id(2)}/private-$key.pdf',
    'file_name': 'Private.pdf',
    'mime_type': 'application/pdf',
    'submitted_by': id(1),
    'submitted_at': verifiedAt,
  };

  @override
  ReportReadScope get scope => (actorId: actor, companyId: company);
  @override
  Stream<void> get scopeChanges => changes.stream;
  @override
  Future<String?> activeRole(String actorId) async => role;
  @override
  Future<JobAccess> companyAccess(String companyId) async {
    requestedCompany = companyId;
    return JobAccess(access, access == null ? 'Denied or ambiguous' : null);
  }

  @override
  Future<List<Map<String, dynamic>>> assignments(String? companyId) async => [
    {...row},
    {...row, 'assignment_id': id(14), 'assignment_status': 'active'},
  ];
  @override
  Future<Object?> workflow(String assignmentId) async {
    if (failWorkflow) throw const PostgrestException(message: 'Offline');
    return context;
  }

  @override
  Future<List<Map<String, dynamic>>> evidence(String assignmentId) async {
    if (denyEvidence) {
      throw const PostgrestException(
        message: 'Any private message',
        code: '42501',
      );
    }
    return files;
  }

  @override
  Future<ReportDisplayDetails> displayDetails(
    WorkAssignment assignment,
    ReportReadScope scope,
  ) async {
    duringDisplay?.call();
    if (failDisplay) throw const FormatException('Optional data unavailable');
    return (workerName: 'Assigned Worker', employmentType: 'part_time');
  }

  void asEmployer() {
    actor = id(8);
    company = id(5);
    role = 'employer';
    access = {'company_id': id(5), 'company_name': 'JobMate Company'};
    context['viewer_role'] = 'employer';
  }
}

void main() {
  late FakeSource source;
  late WorkCompletionReportRepository repository;
  var minute = 0;
  setUp(() {
    minute = 0;
    source = FakeSource();
    repository = WorkCompletionReportRepository(
      source,
      clock: () => DateTime.utc(2026, 11, 23, 0, minute++),
    );
  });
  tearDown(() => source.changes.close());

  Future<WorkCompletionReportData> report() async =>
      (await repository.load(id(2)) as WorkCompletionReportReady).data;
  Future<void> fails(
    WorkCompletionReportFailure reason, {
    String? assignment,
  }) async {
    final result = await repository.load(assignment ?? id(2));
    expect(
      result,
      isA<WorkCompletionReportUnavailable>().having(
        (result) => result.reason,
        'reason',
        reason,
      ),
    );
  }

  test(
    'worker report uses only verified files despite an active sibling',
    () async {
      final data = await report();
      expect(data.jobTitle, 'Retail assistant');
      expect(data.companyName, 'JobMate Company');
      expect(data.workerName, 'Assigned Worker');
      expect(data.employmentTypeLabel, 'Part-time');
      expect(data.verifiedRound, 2);
      expect(data.submittedFileCount, 2);
      expect(data.submittedDescriptions, ['Current round']);
      expect(data.verifiedBy, 'Employer');
      expect(data.checkInLocation.status, isNull);
      expect(data.checkInLocation.originalEventAt, DateTime.parse(start));
      expect(data.markedCompleteAtVerification, DateTime.parse(verifiedAt));
    },
  );

  test('closed engagement does not gate a historical assignment', () async {
    source.row['closure_status'] = 'closed';
    expect((await report()).assignmentStatus, WorkAssignmentStatus.completed);
  });

  test(
    'employer uses the selected affiliation and fails mismatched access',
    () async {
      source.asEmployer();
      expect((await report()).companyName, 'JobMate Company');
      expect(source.requestedCompany, id(5));
      source.access!['company_id'] = id(28);
      await fails(WorkCompletionReportFailure.unavailable);
    },
  );

  test('missing or ambiguous company access fails closed', () async {
    source.asEmployer();
    source.access = null;
    await fails(WorkCompletionReportFailure.unavailable);
  });

  test(
    'optional metadata failure preserves core data and a fresh generation time',
    () async {
      source.failDisplay = true;
      final first = await report();
      final second = await report();
      expect(first.workerName, isNull);
      expect(first.employmentTypeLabel, isNull);
      expect(
        second.generatedAt.difference(first.generatedAt),
        const Duration(minutes: 1),
      );
    },
  );

  Map<String, dynamic> resolution(String decision) => {
    'assignment_id': id(2),
    'contract_version': 2,
    'version': 'a' * 32,
    'can_confirm_absence': false,
    'can_correct': false,
    'checkout_recovery_enforced': true,
    'recovery_cutoff': verifiedAt,
    'original_location': {'check_in_status': 'denied'},
    'resolution': {
      'request_id': id(30),
      'resolved_by': id(8),
      'decision': decision,
      'reason': 'Private correction reason',
      'resolved_at': verifiedAt,
      'corrected_check_in_at': decision == 'corrected'
          ? '2026-11-20T14:55:00Z'
          : null,
      'corrected_check_out_at': decision == 'corrected'
          ? '2026-11-20T17:10:00Z'
          : null,
    },
  };

  test(
    'corrected attendance uses effective times with original event metadata',
    () async {
      source.row['attendance_resolution'] = resolution('corrected');
      final data = await report();
      expect(data.attendanceSource, ReportAttendanceSource.corrected);
      expect(
        data.recordedAttendanceDuration,
        const Duration(hours: 2, minutes: 15),
      );
      expect(data.checkInOffset, const Duration(minutes: -5));
      expect(data.checkOutOffset, const Duration(minutes: 10));
      expect(data.checkInLocation.status, ReportLocationStatus.denied);
      expect(data.checkInLocation.originalEventAt, DateTime.parse(start));
      expect(data.checkInLocation.originalEventAt, isNot(data.checkInAt));
    },
  );

  test('confirmed absence blocks the report', () async {
    source.row['attendance_resolution'] = resolution('confirmed_absent');
    await fails(WorkCompletionReportFailure.ineligible);
  });

  for (final state in [
    'scheduled',
    'active',
    'awaiting_verification',
    'cancelled',
    'disputed',
  ]) {
    test('assignment status $state is ineligible', () async {
      source.row['assignment_status'] = state;
      await fails(WorkCompletionReportFailure.ineligible);
    });
  }
  for (final state in [
    'not_submitted',
    'pending_review',
    'more_evidence_required',
    'disputed',
  ]) {
    test('verification status $state is ineligible', () async {
      source.row['verification_status'] = state;
      await fails(WorkCompletionReportFailure.ineligible);
    });
  }
  for (final bad in <(String, Object?)>[
    ('verified_at', null),
    ('verified_at', '2026-11-21T09:00:00'),
    ('check_in_at', null),
    ('check_out_at', null),
    ('scheduled_end', start),
    ('check_out_at', '2026-11-20T14:59:59Z'),
  ]) {
    test('invalid assignment field $bad fails incomplete', () async {
      source.row[bad.$1] = bad.$2;
      await fails(WorkCompletionReportFailure.incomplete);
    });
  }
  for (final bad in <(String, Object?)>[
    ('assignment_status', 'active'),
    ('verification_status', 'pending_review'),
    ('attendance_complete', false),
    ('latest_round', 0),
    ('latest_round', 3),
    ('history', []),
    ('assignment_id', id(55)),
  ]) {
    test('inconsistent workflow field $bad fails incomplete', () async {
      source.context[bad.$1] = bad.$2;
      await fails(WorkCompletionReportFailure.incomplete);
    });
  }

  test(
    'legacy null-round verification cannot establish verified round',
    () async {
      (source.context['history'] as List).single['submission_round'] = null;
      await fails(WorkCompletionReportFailure.incomplete);
    },
  );

  test(
    'duplicate metadata fails incomplete instead of inflating count',
    () async {
      source.files.add({...source.files.last});
      await fails(WorkCompletionReportFailure.incomplete);
    },
  );
  test('no metadata for verified round fails incomplete', () async {
    source.files.removeWhere((file) => file['submission_round'] == 2);
    await fails(WorkCompletionReportFailure.incomplete);
  });
  test('more than five files fails incomplete', () async {
    for (var key = 40; key < 44; key++) {
      source.files.add(FakeSource.file(key, 2, 'Excess file'));
    }
    await fails(WorkCompletionReportFailure.incomplete);
  });
  test('contradictory path scope fails incomplete', () async {
    source.files.last['storage_path'] = '${id(26)}/Private.pdf';
    await fails(WorkCompletionReportFailure.incomplete);
  });
  test('contradictory evidence worker fails unavailable', () async {
    source.files.last['submitted_by'] = id(21);
    await fails(WorkCompletionReportFailure.unavailable);
  });
  test(
    'foreign assignment and wrong projected worker fail unavailable',
    () async {
      await fails(WorkCompletionReportFailure.unavailable, assignment: id(24));
      source.row['worker_id'] = id(27);
      await fails(WorkCompletionReportFailure.unavailable);
    },
  );
  test('wrong projected employer company fails unavailable', () async {
    source.asEmployer();
    source.row['company_id'] = id(28);
    await fails(WorkCompletionReportFailure.unavailable);
  });
  test(
    'unexpected viewer role, inactive account and admin fail unavailable',
    () async {
      source.context['viewer_role'] = 'employer';
      await fails(WorkCompletionReportFailure.unavailable);
      source.role = null;
      await fails(WorkCompletionReportFailure.unavailable);
      source.role = 'administrator';
      await fails(WorkCompletionReportFailure.unavailable);
    },
  );
  test('switching account away and back invalidates the read', () async {
    source.duringDisplay = () {
      source.actor = id(9);
      source.changes.add(null);
      source.actor = id(1);
      source.changes.add(null);
    };
    await fails(WorkCompletionReportFailure.unavailable);
  });
  test('company selection change invalidates the read', () async {
    source.asEmployer();
    source.duringDisplay = () => source.company = id(29);
    await fails(WorkCompletionReportFailure.unavailable);
  });
  test(
    'company permission revoked during display read fails unavailable',
    () async {
      source.asEmployer();
      source.duringDisplay = () => source.access = null;
      await fails(WorkCompletionReportFailure.unavailable);
    },
  );
  test('core record changes are rejected on refresh', () async {
    source.duringDisplay = () => source.row['check_out_at'] = verifiedAt;
    await fails(WorkCompletionReportFailure.incomplete);
  });
  test('verification revoked during display read blocks the report', () async {
    source.duringDisplay = () => source.row['verification_status'] = 'disputed';
    await fails(WorkCompletionReportFailure.ineligible);
  });
  test(
    'fresh history with a different valid round still rejects stale assembly',
    () async {
      source.duringDisplay = () {
        source.context['latest_round'] = 3;
        (source.context['history'] as List).single['submission_round'] = 3;
      };
      await fails(WorkCompletionReportFailure.incomplete);
    },
  );
  test(
    'required read denial and transient read failure are distinct',
    () async {
      source.denyEvidence = true;
      await fails(WorkCompletionReportFailure.unavailable);
      source.failWorkflow = true;
      await fails(WorkCompletionReportFailure.retry);
    },
  );

  test(
    'Supabase employer adapter scopes membership to the selected company',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final companyFilters = <String?>[];
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        final path = request.uri.path.split('/').last;
        final company = request.uri.queryParameters['company_id'];
        if (path == 'company_memberships') companyFilters.add(company);
        final response = switch (path) {
          'users' => {'role': 'employer', 'status': 'active'},
          'company_memberships' => [
            if (company == null || company == 'eq.${id(5)}')
              {'company_id': id(5), 'member_role': 'employer'},
            if (company == null || company == 'eq.${id(6)}')
              {'company_id': id(6), 'member_role': 'owner'},
          ],
          'companies' => {
            'company_id': id(5),
            'company_name': 'Scoped Company',
            'verification_status': 'verified',
          },
          _ => {},
        };
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'test-token',
          'token_type': 'bearer',
          'user': {'id': id(8)},
        }),
      );
      final adapter = SupabaseWorkCompletionReportSource(
        client,
        selectedCompanyId: () => id(5),
        companyChanges: const Stream.empty(),
      );
      final access = await adapter.companyAccess(id(5));
      expect(access.allowed, isTrue);
      expect(access.company?['company_name'], 'Scoped Company');
      expect(companyFilters, ['eq.${id(5)}']);
    },
  );
}
