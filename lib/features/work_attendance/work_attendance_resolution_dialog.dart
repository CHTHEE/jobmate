import 'package:flutter/material.dart';

import 'work_attendance_models.dart';
import 'work_attendance_resolution.dart';
import 'work_attendance_lifecycle.dart';
import 'work_shift_ui.dart';

String _resolutionTime(DateTime value) =>
    '${shiftDateLabel(value)} ${shiftTimeLabel(value)} MYT';

class WorkAttendanceResolutionDialog extends StatefulWidget {
  const WorkAttendanceResolutionDialog({
    super.key,
    required this.assignment,
    required this.source,
    this.workerName,
  });
  final CompanyWorkAssignment assignment;
  final WorkAttendanceResolutionSource source;
  final String? workerName;
  @override
  State<WorkAttendanceResolutionDialog> createState() =>
      _ResolutionDialogState();
}

class _ResolutionDialogState extends State<WorkAttendanceResolutionDialog> {
  late final controller = WorkAttendanceResolutionController(
    widget.source,
    widget.assignment.assignmentId,
  );
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _decision;
  DateTime? _input, _output;
  bool _preview = false,
      _leaving = false,
      _closing = false,
      _confirmedActual = false;
  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    controller.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (controller.busy || _closing) return;
    _closing = true;
    try {
      if (controller.current &&
          !controller.resolved &&
          (_reason.text.isNotEmpty || _decision != null) &&
          !controller.uncertain) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard attendance review?'),
            content: const Text(
              'Your unsaved decision and reason will be discarded.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (discard != true || !mounted) return;
      }
      if (!mounted) return;
      setState(() => _leaving = true);
      Navigator.pop(context, controller.resolved);
    } finally {
      _closing = false;
    }
  }

  Future<void> _pick(bool checkingIn) async {
    final initial =
        (_input ??
                widget.assignment.checkInAt ??
                widget.assignment.scheduledStart)
            .toUtc()
            .add(const Duration(hours: 8));
    final other =
        (_output ??
                widget.assignment.checkOutAt ??
                widget.assignment.scheduledEnd)
            .toUtc()
            .add(const Duration(hours: 8));
    final value = checkingIn ? initial : other;
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(value.year, value.month, value.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted || !controller.current) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          alwaysUse24HourFormat: false,
          textScaler: TextScaler.linear(
            MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.3),
          ),
        ),
        child: TimePickerTheme(
          data: Theme.of(context).timePickerTheme.copyWith(
            padding: MediaQuery.sizeOf(context).width < 360
                ? const EdgeInsets.symmetric(horizontal: 4, vertical: 16)
                : null,
          ),
          child: child!,
        ),
      ),
    );
    if (time == null || !mounted || !controller.current) return;
    final utc = DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).subtract(const Duration(hours: 8));
    setState(() {
      if (checkingIn) {
        _input = utc;
      } else {
        _output = utc;
      }
      _confirmedActual = false;
    });
  }

  String? _timeError() {
    if (_decision != 'corrected') return null;
    if (_input == null || _output == null) {
      return 'Select both actual corrected attendance times.';
    }
    if (_output!.isBefore(_input!)) {
      return 'Checkout must not precede check-in.';
    }
    final row = widget.assignment;
    if (_input!.isBefore(
          row.scheduledStart.subtract(const Duration(minutes: 60)),
        ) ||
        _input!.isAfter(row.scheduledEnd)) {
      return 'Corrected check-in must be within the allowed shift check-in window.';
    }
    if (row.attendanceAsOf case final snapshot?) {
      if (_input!.isAfter(snapshot) || _output!.isAfter(snapshot)) {
        return 'Corrected times cannot be in the future. Refresh server attendance if needed.';
      }
    }
    if (!_confirmedActual) {
      return 'Confirm that these are the actual attendance times.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving && !controller.busy,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        final stale =
            !controller.resolved &&
            snapshot != null &&
            widget.assignment.resolution != null &&
            snapshot.version != widget.assignment.resolution!.version;
        return AlertDialog(
          title: Text(
            controller.resolved
                ? 'Attendance resolved'
                : _preview
                ? 'Confirm attendance resolution'
                : 'Review Attendance',
          ),
          content: SizedBox(
            width: 560,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .65,
              ),
              child: SingleChildScrollView(
                child: !controller.current
                    ? const Text('Account changed. Close this review.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.assignment.jobTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            widget.workerName == null
                                ? 'Assigned worker'
                                : 'Worker: ${widget.workerName}',
                          ),
                          Text(
                            '${shiftDateLabel(widget.assignment.scheduledStart)} · ${shiftTimeRange(widget.assignment.scheduledStart, widget.assignment.scheduledEnd)}',
                          ),
                          if (!controller.resolved)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: const Text(
                                'Original attendance & correction rules',
                              ),
                              expandedCrossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              expandedAlignment: Alignment.centerLeft,
                              children: [
                                SelectableText(
                                  'Assignment: ${widget.assignment.assignmentId}',
                                ),
                                Text(
                                  'Scheduled: ${_resolutionTime(widget.assignment.scheduledStart)} - ${_resolutionTime(widget.assignment.scheduledEnd)}',
                                ),
                                if (snapshot != null)
                                  Text(
                                    'Ordinary checkout cutoff: ${_resolutionTime(snapshot.recoveryCutoff)} (inclusive). Manual correction does not approve working hours or pay.',
                                  ),
                                Text(
                                  'Original check-in: ${widget.assignment.checkInAt == null ? 'Not recorded' : _resolutionTime(widget.assignment.checkInAt!)}',
                                ),
                                Text(
                                  'Original checkout: ${widget.assignment.checkOutAt == null ? 'Not recorded' : _resolutionTime(widget.assignment.checkOutAt!)}',
                                ),
                                const Text(
                                  'Original GPS remains unchanged. GPS and private evidence remain available from the shift details.',
                                ),
                                Text(
                                  'Original GPS capture: check-in ${snapshot?.originalCheckInLocationStatus ?? 'not recorded'}; checkout ${snapshot?.originalCheckOutLocationStatus ?? 'not recorded'}.',
                                ),
                              ],
                            ),
                          if (controller.busy) const LinearProgressIndicator(),
                          if (controller.message != null &&
                              !controller.resolved)
                            Semantics(
                              liveRegion: true,
                              child: Text(controller.message!),
                            ),
                          if (controller.resolved) ...[
                            Icon(
                              Icons.check_circle_outline,
                              color: attendanceToneColors(
                                context,
                                AttendanceTone.positive,
                              ).$2,
                              size: 40,
                            ),
                            const Text(
                              'The attendance decision has been recorded.',
                            ),
                            Text(
                              snapshot!.decision == 'confirmed_absent'
                                  ? 'Confirmed Absent'
                                  : 'Corrected Attendance',
                            ),
                            Text('Reason: ${snapshot.reason}'),
                            const Text(
                              'Original attendance and GPS remain preserved. No payment has been approved.',
                            ),
                            Text(
                              'Resolved: ${_resolutionTime(snapshot.resolvedAt!)}',
                            ),
                          ] else if (stale)
                            const Text(
                              'Attendance changed since this shift was opened. Close and refresh before reviewing it.',
                            )
                          else if (snapshot == null)
                            TextButton(
                              onPressed: controller.busy
                                  ? null
                                  : controller.load,
                              child: const Text('Refresh attendance review'),
                            )
                          else if (!snapshot.canReview && !controller.uncertain)
                            const Text(
                              'This shift is no longer eligible for attendance resolution. Close and refresh the assignment.',
                            )
                          else if (!controller.uncertain) ...[
                            const SizedBox(height: 12),
                            if (_preview) ...[
                              Text(
                                _decision == 'confirmed_absent'
                                    ? 'Decision: Confirm absence'
                                    : 'Decision: Correct attendance',
                              ),
                              Text('Reason: ${_reason.text.trim()}'),
                              if (_decision == 'corrected') ...[
                                Text(
                                  'Corrected check-in: ${_resolutionTime(_input!)}',
                                ),
                                Text(
                                  'Corrected checkout: ${_resolutionTime(_output!)}',
                                ),
                                if (_output!.isAfter(
                                  widget.assignment.scheduledEnd.add(
                                    const Duration(hours: 24),
                                  ),
                                ))
                                  const Text(
                                    'This is an employer-reviewed actual checkout after the ordinary recovery cutoff. The interval is not approved payable time.',
                                  ),
                              ],
                              const Text(
                                'This records an immutable employer decision for this shift only. It does not verify work, approve payment or change reputation. Originals remain preserved.',
                              ),
                            ] else
                              Form(
                                key: _form,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      initialValue: _decision,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        label: RequiredFieldLabel(
                                          'Resolution decision',
                                        ),
                                      ),
                                      items: [
                                        if (snapshot.canConfirmAbsence)
                                          const DropdownMenuItem(
                                            value: 'confirmed_absent',
                                            child: Text('Confirm absence'),
                                          ),
                                        if (snapshot.canCorrect)
                                          const DropdownMenuItem(
                                            value: 'corrected',
                                            child: Text('Correct attendance'),
                                          ),
                                      ],
                                      onChanged: controller.busy
                                          ? null
                                          : (v) =>
                                                setState(() => _decision = v),
                                      validator: (v) => v == null
                                          ? 'Choose an eligible decision.'
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    if (_decision == 'corrected') ...[
                                      OutlinedButton.icon(
                                        onPressed: controller.busy
                                            ? null
                                            : () => _pick(true),
                                        icon: const Icon(Icons.access_time),
                                        label: Text(
                                          _input == null
                                              ? 'Choose corrected check-in (MYT)'
                                              : 'Check-in: ${_resolutionTime(_input!)}',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        onPressed: controller.busy
                                            ? null
                                            : () => _pick(false),
                                        icon: const Icon(Icons.access_time),
                                        label: Text(
                                          _output == null
                                              ? 'Choose corrected checkout (MYT)'
                                              : 'Checkout: ${_resolutionTime(_output!)}',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        titleAlignment:
                                            ListTileTitleAlignment.top,
                                        value: _confirmedActual,
                                        onChanged: controller.busy
                                            ? null
                                            : (v) => setState(
                                                () => _confirmedActual =
                                                    v == true,
                                              ),
                                        title: const Text(
                                          'These are the actual attendance times, not assumed scheduled hours.',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Corrected checkout +24 hours is the advisory evidence target. Late evidence is not automatically rejected.',
                                      ),
                                    ],
                                    TextFormField(
                                      controller: _reason,
                                      enabled: !controller.busy,
                                      minLines: 2,
                                      maxLines: 4,
                                      maxLength: 2000,
                                      onChanged: (_) => setState(() {}),
                                      decoration: InputDecoration(
                                        label: const RequiredFieldLabel(
                                          'Reason',
                                        ),
                                        hintText:
                                            _decision == 'confirmed_absent'
                                            ? 'Explain why absence is confirmed'
                                            : 'Explain why attendance needs correction',
                                        helperText: 'Recorded in the audit and visible to the worker.',
                                        helperMaxLines: 2,
                                        alignLabelWithHint: true,
                                      ),
                                      validator: (v) =>
                                          v == null ||
                                              !RegExp(r'\S').hasMatch(v)
                                          ? 'Enter a resolution reason.'
                                          : null,
                                    ),
                                    FormField<void>(
                                      validator: (_) => _timeError(),
                                      builder: (state) {
                                        final message =
                                            state.errorText ??
                                            ((_input != null || _output != null)
                                                ? _timeError()
                                                : null);
                                        return message == null
                                            ? const SizedBox.shrink()
                                            : Semantics(
                                                liveRegion: true,
                                                child: Text(
                                                  message,
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .error,
                                                  ),
                                                ),
                                              );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: controller.busy ? null : _close,
              child: Text(controller.resolved ? 'Done' : 'Close'),
            ),
            if (controller.current &&
                !controller.resolved &&
                controller.uncertain) ...[
              TextButton(
                onPressed: controller.busy ? null : controller.load,
                child: const Text('Check saved resolution'),
              ),
              FilledButton(
                onPressed: controller.busy ? null : controller.retrySame,
                child: const Text('Retry same resolution'),
              ),
            ],
            if (controller.current &&
                !controller.resolved &&
                !controller.uncertain &&
                !stale &&
                snapshot?.canReview == true) ...[
              if (_preview)
                TextButton(
                  onPressed: controller.busy
                      ? null
                      : () => setState(() => _preview = false),
                  child: const Text('Edit'),
                ),
              FilledButton(
                onPressed:
                    controller.busy ||
                        _decision == null ||
                        _reason.text.trim().isEmpty ||
                        _reason.text.runes.length > 2000 ||
                        _timeError() != null
                    ? null
                    : () async {
                        if (!_preview) {
                          if (_form.currentState?.validate() != true) return;
                          setState(() => _preview = true);
                        } else {
                          await controller.submit(
                            decision: _decision!,
                            reason: _reason.text,
                            input: _decision == 'corrected' ? _input : null,
                            output: _decision == 'corrected' ? _output : null,
                          );
                        }
                      },
                child: Text(
                  _preview
                      ? (_decision == 'confirmed_absent'
                            ? 'Confirm absence'
                            : 'Confirm correction')
                      : 'Review decision',
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}
