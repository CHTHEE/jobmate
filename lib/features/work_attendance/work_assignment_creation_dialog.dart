import 'package:flutter/material.dart';

import '../../shared/widgets/mobile_back_action.dart';
import 'work_assignment_creation_repository.dart';

/// Caller owns the repository. This dialog never creates on opening or retrying
/// reads; only the final, explicit confirmation dispatches a creation request.
class WorkAssignmentCreationDialog extends StatefulWidget {
  const WorkAssignmentCreationDialog({
    super.key,
    required this.repository,
    required this.companyId,
  });
  final WorkAssignmentCreationRepository repository;
  final String companyId;

  @override
  State<WorkAssignmentCreationDialog> createState() =>
      _WorkAssignmentCreationDialogState();
}

class _WorkAssignmentCreationDialogState
    extends State<WorkAssignmentCreationDialog> {
  final _form = GlobalKey<FormState>();
  final _startDate = TextEditingController(),
      _startTime = TextEditingController();
  final _endDate = TextEditingController(), _endTime = TextEditingController();
  final _location = TextEditingController();
  late final String? _actor = widget.repository.source.userId;
  WorkAssignmentCandidate? _candidate;
  String? _job;
  bool _confirm = false, _busy = false, _leaving = false, _closing = false;
  WorkAssignmentCreateResult? _result;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_changed);
    widget.repository.load(companyId: widget.companyId);
  }

  void _changed() {
    if (!mounted) return;
    if (widget.repository.source.userId != _actor) {
      _candidate = null;
      _job = null;
      _confirm = false;
      _result = null;
      for (final c in [_startDate, _startTime, _endDate, _endTime, _location]) {
        c.clear();
      }
    } else if (!_confirm && !widget.repository.state.loading) {
      final rows = widget.repository.state.candidates;
      if (!rows.any((c) => c.jobId == _job)) _job = null;
      if (!rows.any((c) => identical(c, _candidate))) _candidate = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.repository.removeListener(_changed);
    for (final c in [_startDate, _startTime, _endDate, _endTime, _location]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _close([String? assignmentId]) async {
    if (_closing || _busy) return;
    _closing = true;
    final dirty =
        _candidate != null ||
        [
          _startDate,
          _startTime,
          _endDate,
          _endTime,
          _location,
        ].any((c) => c.text.isNotEmpty);
    final leave =
        assignmentId != null || await confirmDiscardChanges(context, dirty);
    _closing = false;
    if (!mounted || !leave) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(assignmentId);
    });
  }

  DateTime? get _start =>
      workAssignmentMalaysiaUtc(_startDate.text, _startTime.text);
  DateTime? get _end => workAssignmentMalaysiaUtc(_endDate.text, _endTime.text);

  Future<void> _pick(TextEditingController controller, bool date) async {
    if (_busy) return;
    final malaysia = DateTime.now().toUtc().add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    String? value;
    if (date) {
      final existing = workAssignmentMalaysiaUtc(
        controller.text,
        '00:00',
      )?.add(const Duration(hours: 8));
      final chosen = await showDatePicker(
        context: context,
        initialDate:
            existing ?? DateTime(malaysia.year, malaysia.month, malaysia.day),
        firstDate: DateTime(1),
        lastDate: DateTime(9999, 12, 31),
      );
      if (chosen != null) {
        value =
            '${chosen.year.toString().padLeft(4, '0')}-${two(chosen.month)}-${two(chosen.day)}';
      }
    } else {
      final existing = workAssignmentMalaysiaUtc(
        '2026-01-01',
        controller.text,
      )?.add(const Duration(hours: 8));
      final chosen = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: existing?.hour ?? malaysia.hour,
          minute: existing?.minute ?? malaysia.minute,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (chosen != null) value = '${two(chosen.hour)}:${two(chosen.minute)}';
    }
    if (mounted &&
        !_busy &&
        widget.repository.source.userId == _actor &&
        value != null) {
      setState(() {
        controller.text = value!;
        _result = null;
      });
    }
  }

  Future<void> _submit({bool reconcile = false}) async {
    if (_busy ||
        _candidate == null ||
        widget.repository.source.userId != _actor) {
      return;
    }
    setState(() => _busy = true);
    final result = reconcile
        ? await widget.repository.reconcile(_candidate!)
        : await widget.repository.create(
            candidate: _candidate!,
            start: _start!,
            end: _end!,
            location: _location.text,
          );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
    if (widget.repository.source.userId != _actor) {
      _changed();
      return;
    }
    if (result.status == WorkAssignmentCreateStatus.success) {
      await _close(result.assignmentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final state = repository.state;
    final accountChanged = repository.source.userId != _actor;
    final locked =
        _candidate != null &&
        [
          WorkAssignmentCreateStatus.uncertain,
          WorkAssignmentCreateStatus.submitting,
          WorkAssignmentCreateStatus.success,
        ].contains(repository.statusFor(_candidate!));
    final jobs = {for (final c in state.candidates) c.jobId: c.jobTitle};
    Widget input(
      TextEditingController controller,
      String label,
      String? Function(String?) validate,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        keyboardType: controller == _location
            ? TextInputType.streetAddress
            : TextInputType.datetime,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: controller == _location
              ? null
              : IconButton(
                  tooltip: 'Choose $label',
                  onPressed: _busy
                      ? null
                      : () => _pick(
                          controller,
                          controller == _startDate || controller == _endDate,
                        ),
                  icon: Icon(
                    controller == _startDate || controller == _endDate
                        ? Icons.calendar_today
                        : Icons.schedule,
                  ),
                ),
        ),
        validator: validate,
        onChanged: (_) => setState(() => _result = null),
      ),
    );
    String? date(String? value) =>
        workAssignmentMalaysiaUtc(value ?? '', '00:00') == null
        ? 'Use a valid date: YYYY-MM-DD.'
        : null;
    String? time(String? value) =>
        workAssignmentMalaysiaUtc('2026-01-01', value ?? '') == null
        ? 'Use 24-hour time: HH:mm.'
        : null;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AlertDialog(
        title: Text(_confirm ? 'Confirm new assignment' : 'Create Assignment'),
        content: SizedBox(
          width: 520,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .60,
            ),
            child: SingleChildScrollView(
              child: accountChanged
                  ? const Text(
                      'Account changed. Close this dialog and sign in again.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_busy)
                          const LinearProgressIndicator(
                            semanticsLabel: 'Creating or checking assignment',
                          ),
                        if (_result != null)
                          Semantics(
                            liveRegion: true,
                            child: Text(_result!.message),
                          ),
                        if (_confirm && _candidate != null) ...[
                          Text('Company: ${_candidate!.companyName}'),
                          Text('Job: ${_candidate!.jobTitle}'),
                          Text('Worker: ${_candidate!.applicantName}'),
                          Text(
                            'Start (MYT): ${_startDate.text} ${_startTime.text}',
                          ),
                          Text('End (MYT): ${_endDate.text} ${_endTime.text}'),
                          Text('Workplace: ${_location.text.trim()}'),
                          const SizedBox(height: 12),
                          const Text(
                            'Confirming creates a real assignment. Existing assignments are not edited. If the result is uncertain, check assignments before taking any further action.',
                          ),
                        ] else if (state.loading)
                          const Center(child: CircularProgressIndicator())
                        else if (state.error != null) ...[
                          Text(state.error!),
                          TextButton(
                            onPressed: () =>
                                repository.load(companyId: widget.companyId),
                            child: const Text('Retry loading applications'),
                          ),
                        ] else if (state.candidates.isEmpty)
                          const Text(
                            'No eligible hired applications. Applications with any existing assignment are excluded.',
                          )
                        else
                          Form(
                            key: _form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Malaysia time (MYT, UTC+08:00). Dates use YYYY-MM-DD and times use 24-hour HH:mm; the device timezone is ignored.',
                                ),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  initialValue: _job,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Company job',
                                  ),
                                  items: jobs.entries
                                      .map(
                                        (j) => DropdownMenuItem(
                                          value: j.key,
                                          child: Text(
                                            j.value,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(() {
                                          _job = value;
                                          _candidate = null;
                                          _result = null;
                                        }),
                                  validator: (v) =>
                                      v == null ? 'Select a job.' : null,
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  key: ValueKey(_job),
                                  initialValue: _candidate?.applicationId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Hired application',
                                  ),
                                  items: state.candidates
                                      .where((c) => c.jobId == _job)
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c.applicationId,
                                          child: Text(
                                            c.applicantName,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(() {
                                          _candidate = state.candidates
                                              .singleWhere(
                                                (c) => c.applicationId == value,
                                              );
                                          _result = null;
                                        }),
                                  validator: (v) => _candidate == null
                                      ? 'Select a hired application.'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                if (_candidate != null)
                                  Text(
                                    'Company: ${_candidate!.companyName}\nWorker: ${_candidate!.applicantName}',
                                  ),
                                const SizedBox(height: 12),
                                input(_startDate, 'Start date (MYT)', date),
                                input(_startTime, 'Start time (MYT)', time),
                                input(_endDate, 'End date (MYT)', date),
                                input(_endTime, 'End time (MYT)', time),
                                input(
                                  _location,
                                  'Workplace location',
                                  (v) =>
                                      v == null ||
                                          v.trim().isEmpty ||
                                          v.runes.length > 500
                                      ? 'Enter a workplace location of up to 500 characters.'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => _close(),
            child: const Text('Close'),
          ),
          if (!accountChanged && _confirm && !locked)
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _confirm = false;
                      _changed();
                    },
              child: const Text('Edit'),
            ),
          if (!accountChanged && _confirm && locked)
            OutlinedButton(
              onPressed: _busy ? null : () => _submit(reconcile: true),
              child: const Text('Check current assignment'),
            ),
          if (!accountChanged &&
              !locked &&
              state.error == null &&
              !state.loading &&
              (_confirm || state.candidates.isNotEmpty))
            FilledButton(
              onPressed: _busy
                  ? null
                  : () {
                      if (_confirm) {
                        _submit();
                        return;
                      }
                      if (!_form.currentState!.validate()) return;
                      if (_start == null ||
                          _end == null ||
                          !_end!.isAfter(_start!)) {
                        setState(
                          () => _result = const WorkAssignmentCreateResult(
                            WorkAssignmentCreateStatus.rejected,
                            'End must be after start.',
                          ),
                        );
                        return;
                      }
                      setState(() => _confirm = true);
                    },
              child: Text(_confirm ? 'Confirm creation' : 'Review assignment'),
            ),
        ],
      ),
    );
  }
}
