import 'dart:async';

import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TestEmployerApplicantsSource implements EmployerApplicantsSource {
  String? actor = 'employer-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  final requests = <String>[];
  int contextLoads = 0;
  EmployerPostingContext data = const EmployerPostingContext(
    JobAccess({
      'company_id': 'company-id',
      'company_name': 'ABC Company',
    }, null),
    [
      {
        'job_id': 'real-job-id',
        'company_id': 'company-id',
        'title': 'Part-Time Cafe Crew',
        'status': 'published',
      },
      {
        'job_id': 'closed-job-id',
        'company_id': 'company-id',
        'title': 'Closed posting',
        'status': 'closed',
      },
    ],
  );
  List<Map<String, dynamic>> rows = [];
  Future<EmployerPostingContext> Function()? fetchJobs;
  Future<List<Map<String, dynamic>>> Function(String)? fetchApplicants;
  final resumeRequests = <String>[];
  Future<FunctionResponse> Function()? fetchResume;
  @override
  Future<FunctionResponse> viewResume(String id) {
    resumeRequests.add(id);
    return fetchResume?.call() ??
        Future.value(
          FunctionResponse(
            status: 200,
            data: {
              'signed_url': 'https://example.invalid/mock-resume.pdf',
              'expires_in': 60,
            },
          ),
        );
  }

  final updates = <(String, MyApplicationStatus, String?)>[];
  final offerRequests = <(String, String, String?)>[];
  Future<void> Function()? sendUpdate;
  @override
  Future<void> updateStatus(
    String id,
    MyApplicationStatus status,
    String? note,
  ) async {
    updates.add((id, status, note));
    if (sendUpdate != null) {
      await sendUpdate!();
      return;
    }
    rows = [
      for (final row in rows)
        if (row['application_id'] == id)
          {...row, 'status': status.name}
        else
          row,
    ];
  }

  @override
  Future<Map<String, dynamic>> issueCompensationOffer(
    String id,
    String requestId,
    String? note,
  ) async {
    offerRequests.add((id, requestId, note));
    final row = {
      'offer_id': '00000000-0000-4000-8000-000000000001',
      'application_id': id,
      'offer_version': 1,
      'employment_type': 'part_time',
      'salary_period': 'hourly',
      'salary_min_sen': '1500',
      'salary_max_sen': '2000',
      'currency': 'MYR',
      'issued_by': '00000000-0000-4000-8000-000000000003',
      'issued_at': '2026-11-04T10:11:37.58546Z',
      'payment_basis_supported': true,
      'is_current': true,
      'is_accepted': false,
    };
    rows = [
      for (final item in rows)
        if (item['application_id'] == id)
          {...item, 'status': MyApplicationStatus.offered.name}
        else
          item,
    ];
    return row;
  }

  @override
  String? get userId => actor;
  @override
  Stream<String?> get accountChanges => changes.stream;
  @override
  Future<EmployerPostingContext> loadJobs() {
    contextLoads++;
    return fetchJobs?.call() ?? Future.value(data);
  }

  @override
  Future<List<Map<String, dynamic>>> applicants(String jobId) {
    requests.add(jobId);
    return fetchApplicants?.call(jobId) ?? Future.value(rows);
  }

  void switchAccount(String? id) {
    actor = id;
    changes.add(id);
  }
}

Map<String, dynamic> applicantRow(String id, {String status = 'submitted'}) => {
  'application_id': id,
  'applicant_id': 'real-applicant-id',
  'applicant_name': 'Alex Thee',
  'resume_id': null,
  'cover_note': null,
  'status': status,
  'applied_at': '2026-11-04T10:11:37.58546Z',
  'updated_at': '2026-11-04T10:11:37.58546Z',
};
