import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_page.dart';
import 'job_form_page.dart';
import 'job_postings_repository.dart';

/// A pushed route instance owns its form key and exit guard. A second Create
/// Job route must never reuse the key of a form still below it in the stack.
GoRoute jobFormRoute(String path, {JobPostingsRepository? repository}) {
  final guards = <LocalKey, Future<bool> Function()>{};
  return GoRoute(
    path: path,
    onExit: (_, state) async => await guards[state.pageKey]?.call() ?? true,
    pageBuilder: (_, state) => appPage(
      state,
      _JobFormRouteBody(
        key: ValueKey(
          '${state.pageKey.value}:${state.pathParameters['jobId'] ?? ''}',
        ),
        routeKey: state.pageKey,
        guards: guards,
        repository: repository,
        jobId: state.pathParameters['jobId'],
      ),
    ),
  );
}

class _JobFormRouteBody extends StatefulWidget {
  const _JobFormRouteBody({
    super.key,
    required this.routeKey,
    required this.guards,
    this.repository,
    this.jobId,
  });

  final LocalKey routeKey;
  final Map<LocalKey, Future<bool> Function()> guards;
  final JobPostingsRepository? repository;
  final String? jobId;

  @override
  State<_JobFormRouteBody> createState() => _JobFormRouteBodyState();
}

class _JobFormRouteBodyState extends State<_JobFormRouteBody> {
  final _formKey = GlobalKey<JobFormPageState>();

  Future<bool> _confirmExit() async =>
      await _formKey.currentState?.confirmExit() ?? true;

  @override
  void initState() {
    super.initState();
    widget.guards[widget.routeKey] = _confirmExit;
  }

  @override
  void dispose() {
    if (widget.guards[widget.routeKey] == _confirmExit) {
      widget.guards.remove(widget.routeKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => JobFormPage(
    key: _formKey,
    repository: widget.repository,
    jobId: widget.jobId,
  );
}
