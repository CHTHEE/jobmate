import 'dart:async';

import 'package:flutter/material.dart';

import 'work_assignment_creation_repository.dart';
import 'work_attendance_models.dart';

typedef WorkAssignmentNameLoader = Future<String?> Function(
  CompanyWorkAssignment assignment,
  String companyId,
);

/// Names come only from the existing company-authorized job/applicant RPCs.
/// No protected Module 4 tables or unrelated user profiles are queried.
class WorkAssignmentPeopleRepository {
  WorkAssignmentPeopleRepository(this.source);
  final WorkAssignmentCreationSource source;
  Future<String?> workerName(
    CompanyWorkAssignment assignment,
    String companyId,
  ) async {
    final actor = source.userId;
    if (actor == null) return null;
    var changed = false;
    final subscription = source.accountChanges.listen((id) {
      if (id != actor) changed = true;
    });
    bool current() => !changed && source.userId == actor;
    try {
      final access = await source.loadAccess();
      if (!current() ||
          !access.allowed ||
          workUuid(access.company?['company_id']) != companyId) {
        return null;
      }
      final jobs = await source.listJobs(companyId);
      if (!current() || jobs.total != jobs.rows.length) return null;
      final matches = jobs.rows
          .where(
            (j) =>
                j['job_id'] == assignment.jobId && j['company_id'] == companyId,
          )
          .toList();
      if (matches.length != 1) return null;
      final applicants = await source.listApplicants(assignment.jobId);
      if (!current() || applicants.total != applicants.rows.length) return null;
      final rows = applicants.rows
          .where(
            (a) =>
                a['application_id'] == assignment.applicationId &&
                a['applicant_id'] == assignment.workerId,
          )
          .toList();
      final finalAccess = await source.loadAccess();
      if (!current() ||
          !finalAccess.allowed ||
          workUuid(finalAccess.company?['company_id']) != companyId ||
          rows.length != 1) {
        return null;
      }
      final name = rows.single['applicant_name'];
      return name is String && name.trim().isNotEmpty ? name.trim() : null;
    } catch (_) {
      return null;
    } finally {
      unawaited(subscription.cancel());
    }
  }
}

class WorkAssignmentWorkerName extends StatefulWidget {
  const WorkAssignmentWorkerName({
    super.key,
    required this.assignment,
    required this.companyId,
    this.loader,
    this.profileHeader = false,
  });
  final CompanyWorkAssignment assignment;
  final String companyId;
  final WorkAssignmentNameLoader? loader;
  final bool profileHeader;
  @override
  State<WorkAssignmentWorkerName> createState() =>
      _WorkAssignmentWorkerNameState();
}

class _WorkAssignmentWorkerNameState extends State<WorkAssignmentWorkerName> {
  late Future<String?> name =
      widget.loader?.call(widget.assignment, widget.companyId) ??
      Future.value();
  @override
  void didUpdateWidget(covariant WorkAssignmentWorkerName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assignment != widget.assignment ||
        oldWidget.companyId != widget.companyId ||
        oldWidget.loader != widget.loader) {
      name =
          widget.loader?.call(widget.assignment, widget.companyId) ??
          Future.value();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: name,
    builder: (context, snapshot) {
      final value = snapshot.connectionState == ConnectionState.done
          ? snapshot.data
          : null;
      final label = value == null ? 'Assigned worker' : 'Worker: $value';
      if (!widget.profileHeader) return Text(label);
      final parts =
          value
              ?.trim()
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty) ??
          <String>[];
      final initials = parts
          .take(2)
          .map((p) => p.characters.first.toUpperCase())
          .join();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            child: initials.isEmpty
                ? const Icon(Icons.person_outline)
                : Text(initials),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  'Hired',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
