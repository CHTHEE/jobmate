import 'package:flutter/material.dart';

import 'work_attendance_models.dart';
import 'work_evidence_repository.dart';

enum MockWorkEvidenceReviewAction { requestMore, verify }

/// A final, network-free fake. No client, injected network callbacks, RPCs,
/// Storage operations or repository mutations. Results exist in memory only.
final class MockWorkEvidenceReviewOperations {
  MockWorkEvidenceReviewOperations({
    List<bool> outcomes = const [],
    this.delay = Duration.zero,
  }) : _outcomes = List.unmodifiable(outcomes);
  final List<bool> _outcomes;
  final Duration delay;
  final List<(MockWorkEvidenceReviewAction, String, String?)> _calls = [];
  List<(MockWorkEvidenceReviewAction, String, String?)> get calls =>
      List.unmodifiable(_calls);

  // Future live contract: request_more_work_evidence(p_assignment_id, p_reason).
  Future<void> requestMoreEvidence(String assignmentId, String reason) =>
      _simulate(MockWorkEvidenceReviewAction.requestMore, assignmentId, reason);
  // Future live contract: verify_work_assignment(p_assignment_id). Both void.
  Future<void> verifyAssignment(String assignmentId) =>
      _simulate(MockWorkEvidenceReviewAction.verify, assignmentId, null);

  Future<void> _simulate(
    MockWorkEvidenceReviewAction action,
    String id,
    String? reason,
  ) async {
    final index = _calls.length;
    _calls.add((action, id, reason));
    await Future<void>.delayed(delay);
    if (index < _outcomes.length && !_outcomes[index]) {
      throw StateError('Simulated review failure');
    }
  }
}

/// Only displayed with explicit mock injection into an authorized employer
/// metadata viewer. Metadata is a necessary gate, not proof of Storage integrity
/// or the submission's expected file count; those remain server-only checks.
class MockWorkEvidenceReviewPanel extends StatefulWidget {
  const MockWorkEvidenceReviewPanel({
    super.key,
    required this.repository,
    required this.operations,
  });
  final WorkEvidenceRepository repository;
  final MockWorkEvidenceReviewOperations operations;
  @override
  State<MockWorkEvidenceReviewPanel> createState() =>
      _MockWorkEvidenceReviewPanelState();
}

class _MockWorkEvidenceReviewPanelState
    extends State<MockWorkEvidenceReviewPanel> {
  int _generation = 0;
  bool _busy = false, _sending = false, _completed = false;
  String? _message;

  bool get _requestEligible {
    final repo = widget.repository;
    final row = repo.assignment;
    return repo.employer &&
        !repo.loading &&
        repo.error == null &&
        repo.attendance.source.userId != null &&
        row?.assignmentStatus == WorkAssignmentStatus.awaitingVerification &&
        row?.verificationStatus == WorkVerificationStatus.pendingReview &&
        repo.evidence.isNotEmpty;
  }

  bool get _verifyEligible {
    if (!_requestEligible) return false;
    final row = widget.repository.assignment!;
    if (row.checkInAt == null ||
        row.checkOutAt == null ||
        row.checkOutAt!.isBefore(row.checkInAt!)) {
      return false;
    }
    var latest = 0;
    for (final file in widget.repository.evidence) {
      if (file.submissionRound > latest) latest = file.submissionRound;
    }
    final count = widget.repository.evidence
        .where((file) => file.submissionRound == latest)
        .length;
    return count >= 1 && count <= 5;
  }

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_contextChanged);
  }

  void _contextChanged() {
    ++_generation;
    if (mounted) {
      setState(() {
        _message = null;
        _busy = false;
        _sending = false;
        _completed = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant MockWorkEvidenceReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      oldWidget.repository.removeListener(_contextChanged);
      widget.repository.addListener(_contextChanged);
    }
    if (!identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.operations, widget.operations)) {
      _contextChanged();
    }
  }

  Future<void> _review(MockWorkEvidenceReviewAction action) async {
    if (_busy ||
        _completed ||
        !_requestEligible ||
        (action == MockWorkEvidenceReviewAction.verify && !_verifyEligible)) {
      return;
    }
    final repo = widget.repository;
    final operations = widget.operations;
    final actor = repo.attendance.source.userId;
    final assignment = repo.assignment!;
    final generation = _generation;
    bool current() =>
        mounted &&
        generation == _generation &&
        identical(repo, widget.repository) &&
        identical(operations, widget.operations) &&
        actor == repo.attendance.source.userId &&
        identical(assignment, repo.assignment) &&
        _requestEligible &&
        (action != MockWorkEvidenceReviewAction.verify || _verifyEligible);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final reason = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MockReviewConfirmation(
          repository: repo,
          action: action,
          current: current,
        ),
      );
      if (reason == null || !current()) return;
      setState(() {
        _message = 'Simulating review...';
        _sending = true;
      });
      if (action == MockWorkEvidenceReviewAction.requestMore) {
        await operations.requestMoreEvidence(assignment.assignmentId, reason);
      } else {
        await operations.verifyAssignment(assignment.assignmentId);
      }
      if (!current()) return;
      setState(() {
        _completed = true;
        _message = action == MockWorkEvidenceReviewAction.requestMore
            ? 'Mock evidence request succeeded. Real assignment and database state are unchanged.'
            : 'Mock verification succeeded. Real assignment and database state are unchanged.';
      });
    } catch (_) {
      if (current()) {
        setState(
          () => _message =
              'Mock review failed. No database changes were made. Try again.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _sending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    widget.repository.removeListener(_contextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_requestEligible) return const SizedBox.shrink();
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'MOCK employer evidence review',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Simulation only. No review RPCs are called and no real records change.',
            ),
            const Text(
              'Private-file existence and the expected submission file count are not verified by this metadata viewer.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: _busy || _completed
                      ? null
                      : () => _review(MockWorkEvidenceReviewAction.requestMore),
                  child: const Text('Request More Evidence'),
                ),
                if (_verifyEligible)
                  OutlinedButton(
                    onPressed: _busy || _completed
                        ? null
                        : () => _review(MockWorkEvidenceReviewAction.verify),
                    child: const Text('Verify'),
                  ),
              ],
            ),
            if (_sending)
              const LinearProgressIndicator(
                semanticsLabel: 'Mock review in progress',
              ),
            if (_message != null)
              Semantics(liveRegion: true, child: Text(_message!)),
          ],
        ),
      ),
    );
  }
}

class _MockReviewConfirmation extends StatefulWidget {
  const _MockReviewConfirmation({
    required this.repository,
    required this.action,
    required this.current,
  });
  final WorkEvidenceRepository repository;
  final MockWorkEvidenceReviewAction action;
  final bool Function() current;
  @override
  State<_MockReviewConfirmation> createState() =>
      _MockReviewConfirmationState();
}

class _MockReviewConfirmationState extends State<_MockReviewConfirmation> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repository,
    builder: (context, _) {
      final active = widget.current();
      final request = widget.action == MockWorkEvidenceReviewAction.requestMore;
      final length = _reason.text.trim().runes.length;
      final valid = !request || (length >= 1 && length <= 1000);
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(
            request ? 'Mock: Request More Evidence' : 'Mock: Verify assignment',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Confirm this simulation only. No database state will change.',
                ),
                if (!active)
                  const Text(
                    'Context changed. Cancel and reopen from an authorized assignment.',
                  )
                else if (request)
                  TextField(
                    key: const ValueKey('mock-review-reason'),
                    controller: _reason,
                    minLines: 2,
                    maxLines: 5,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Reason (required)',
                      errorText: valid
                          ? null
                          : 'Enter a reason of 1-1,000 trimmed characters.',
                      errorMaxLines: 3,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: active && valid
                  ? () => Navigator.of(context).pop(_reason.text.trim())
                  : null,
              child: Text(
                request ? 'Confirm mock request' : 'Confirm mock verification',
              ),
            ),
          ],
        ),
      );
    },
  );
}
