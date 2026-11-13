import 'package:flutter/material.dart';

import 'work_attendance_location_service.dart';
import 'work_attendance_models.dart';

/// Returns the selected location only when the worker confirms attendance.
/// Returns null when the worker cancels.
class WorkAttendanceLocationDialog extends StatefulWidget {
  const WorkAttendanceLocationDialog({
    super.key,
    required this.jobTitle,
    required this.checkingIn,
    required this.canContinue,
    this.captureLocation,
  });

  final String jobTitle;
  final bool checkingIn;
  final bool Function() canContinue;

  /// Optional override for tests; production uses the device GPS service.
  final Future<WorkAttendanceLocation> Function()? captureLocation;

  @override
  State<WorkAttendanceLocationDialog> createState() =>
      _WorkAttendanceLocationDialogState();
}

class _WorkAttendanceLocationDialogState
    extends State<WorkAttendanceLocationDialog> {
  final _locationService = WorkAttendanceLocationService();

  WorkAttendanceLocation? _location;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _capture();
  }

  Future<void> _capture() async {
    if (_loading || !widget.canContinue()) return;

    setState(() {
      _loading = true;
      _location = null;
    });

    final result =
        await (widget.captureLocation?.call() ?? _locationService.capture());

    if (!mounted) return;

    setState(() {
      _location = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = _location;
    final granted = location?.status == 'granted';
    final action = widget.checkingIn ? 'check-in' : 'check-out';

    return AlertDialog(
      title: Text('Confirm $action'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.jobTitle),
            const SizedBox(height: 16),
            if (!widget.canContinue())
              const Text(
                'Your account changed. Close this dialog and reopen attendance.',
              )
            else if (_loading) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              const Text(
                'Requesting your current device location. '
                'This may take up to 15 seconds.',
              ),
            ] else if (granted) ...[
              const Text(
                'Location captured successfully.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(
                'Latitude: ${location?.latitude}\n'
                'Longitude: ${location?.longitude}',
              ),
              const SizedBox(height: 8),
              const Text(
                'These coordinates will be submitted with your attendance record.',
              ),
            ] else if (location != null) ...[
              Text(
                location.status == 'denied'
                    ? 'Location permission was denied.'
                    : 'Your device location is unavailable.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can retry GPS or continue without location. '
                'If you continue, the attendance record will show '
                'that GPS was not captured.',
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'The server records the official attendance time '
              'and checks whether this action is allowed.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (!_loading && widget.canContinue())
          TextButton(onPressed: _capture, child: const Text('Retry GPS')),
        if (!_loading && location != null && widget.canContinue())
          FilledButton(
            onPressed: () => Navigator.pop(context, location),
            child: Text(granted ? 'Confirm $action' : 'Continue without GPS'),
          ),
      ],
    );
  }
}
