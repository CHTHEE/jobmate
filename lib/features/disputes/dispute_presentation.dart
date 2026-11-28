import 'package:material_ui/material_ui.dart';

import '../../shared/theme/jobmate_theme.dart';

String disputeCategoryLabel(Object? value) => switch (value?.toString()) {
  'recruitment' => 'Recruitment dispute',
  'work' => 'Work and attendance dispute',
  'payment' => 'Payment dispute',
  _ => 'Dispute',
};

String disputeStatusLabel(Object? value) => switch (value?.toString()) {
  'open' => 'Submitted',
  'investigating' => 'Under review',
  'pending_information' => 'Information requested',
  'resolved' => 'Resolved',
  'rejected' => 'Rejected',
  _ => 'Status unavailable',
};

String disputeActionLabel(Object? value) => switch (value?.toString()) {
  'submitted' => 'Dispute submitted',
  'investigate' => 'Review started',
  'request_information' => 'Information requested',
  'respond_information' => 'Information provided',
  'resolve' => 'Dispute resolved',
  'reject' => 'Dispute rejected',
  _ => 'Case updated',
};

class DisputeActivityTimeline extends StatelessWidget {
  const DisputeActivityTimeline({
    super.key,
    required this.events,
    this.evidence = false,
  });

  final List<Map<String, dynamic>> events;
  final bool evidence;

  String _title(Map<String, dynamic> event) {
    if (evidence) {
      return switch (event['action']) {
        'prepared' => 'Evidence upload prepared',
        'submitted' => 'Evidence submitted',
        _ => 'Evidence updated',
      };
    }
    final title = disputeActionLabel(event['action']);
    return title == 'Case updated' && event['new_status'] != null
        ? disputeStatusLabel(event['new_status'])
        : title;
  }

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const Text('No history recorded.');
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final (index, event) in events.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      Icon(
                        evidence
                            ? Icons.attach_file
                            : switch (event['action']) {
                                'resolve' => Icons.check_circle_outline,
                                'reject' => Icons.cancel_outlined,
                                'request_information' => Icons.help_outline,
                                'respond_information' => Icons.reply,
                                'submitted' => Icons.flag_outlined,
                                _ => Icons.history,
                              },
                        size: 18,
                        color: event['action'] == 'reject'
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                      if (index < events.length - 1)
                        Expanded(
                          child: SizedBox(
                            width: 1,
                            child: ColoredBox(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: index < events.length - 1 ? 14 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title(event), style: theme.textTheme.titleSmall),
                        if (event['note'] case final String note
                            when note.trim().isNotEmpty)
                          Text(note),
                        Text(
                          disputeDateTime(event['created_at']),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String disputeDateTime(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'Date unavailable';
  final myt = parsed.toUtc().add(const Duration(hours: 8));
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = myt.hour % 12 == 0 ? 12 : myt.hour % 12;
  final minute = myt.minute.toString().padLeft(2, '0');
  final period = myt.hour < 12 ? 'AM' : 'PM';
  return '${myt.day} ${months[myt.month - 1]} ${myt.year}, '
      '$hour:$minute $period MYT';
}

class DisputeStatusBadge extends StatelessWidget {
  const DisputeStatusBadge(this.status, {super.key});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'resolved' => Colors.green.shade800,
      'rejected' => Theme.of(context).colorScheme.error,
      'investigating' || 'pending_information' => Colors.amber.shade900,
      _ => JobMateTheme.darkTeal,
    };
    return Semantics(
      label: 'Dispute status: ${disputeStatusLabel(status)}',
      child: Chip(
        visualDensity: VisualDensity.compact,
        backgroundColor: color.withValues(alpha: .08),
        side: BorderSide(color: color.withValues(alpha: .2)),
        avatar: Icon(Icons.circle, size: 11, color: color),
        label: Text(
          disputeStatusLabel(status),
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class DisputeProgress extends StatelessWidget {
  const DisputeProgress({
    super.key,
    required this.status,
    required this.history,
  });

  final String? status;
  final List<Map<String, dynamic>> history;

  bool get _reviewObserved =>
      const {'investigating', 'pending_information'}.contains(status) ||
      history.any(
        (event) => const {
          'investigate',
          'request_information',
          'respond_information',
        }.contains(event['action']),
      );

  @override
  Widget build(BuildContext context) {
    final terminal = const {'resolved', 'rejected'}.contains(status);
    final labels = <String>[
      'Submitted',
      'Under review',
      status == 'rejected'
          ? 'Rejected'
          : status == 'resolved'
          ? 'Resolved'
          : 'Outcome',
    ];
    final stages = <_ProgressStage>[
      const _ProgressStage(completed: true, current: false),
      _ProgressStage(
        completed: terminal && _reviewObserved,
        current: !terminal && _reviewObserved,
      ),
      _ProgressStage(
        completed: terminal,
        current: false,
        rejected: status == 'rejected',
      ),
    ];
    if (!_reviewObserved && !terminal) {
      stages[0] = const _ProgressStage(completed: false, current: true);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final vertical = constraints.maxWidth < 520 * scale;
        final stageWidth = constraints.maxWidth / labels.length;
        return Semantics(
          label: 'Dispute progress: ${disputeStatusLabel(status)}',
          child: vertical
              ? Column(
                  children: [
                    for (var index = 0; index < labels.length; index++)
                      _VerticalProgressItem(
                        key: ValueKey(
                          'dispute-progress-${labels[index].toLowerCase().replaceAll(' ', '-')}-${_stageState(stages[index])}',
                        ),
                        label: labels[index],
                        stage: stages[index],
                        connector: index < labels.length - 1,
                        connectorComplete:
                            index < labels.length - 1 &&
                            stages[index].completed &&
                            stages[index + 1].completed,
                      ),
                  ],
                )
              : Stack(
                  children: [
                    for (var index = 0; index < labels.length - 1; index++)
                      PositionedDirectional(
                        start: stageWidth * (index + .5),
                        top: 13,
                        width: stageWidth,
                        height: 2,
                        child: ColoredBox(
                          color:
                              stages[index].completed &&
                                  stages[index + 1].completed
                              ? JobMateTheme.teal
                              : JobMateTheme.divider,
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = 0; index < labels.length; index++)
                          Expanded(
                            child: _HorizontalProgressItem(
                              key: ValueKey(
                                'dispute-progress-${labels[index].toLowerCase().replaceAll(' ', '-')}-${_stageState(stages[index])}',
                              ),
                              label: labels[index],
                              stage: stages[index],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }

  String _stageState(_ProgressStage stage) => stage.rejected
      ? 'rejected'
      : stage.completed
      ? 'completed'
      : stage.current
      ? 'current'
      : 'pending';
}

class _ProgressStage {
  const _ProgressStage({
    required this.completed,
    required this.current,
    this.rejected = false,
  });
  final bool completed, current, rejected;
}

class _ProgressDot extends StatelessWidget {
  const _ProgressDot(this.stage);
  final _ProgressStage stage;

  @override
  Widget build(BuildContext context) {
    final color = stage.rejected
        ? Theme.of(context).colorScheme.error
        : JobMateTheme.teal;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: stage.completed ? color : Colors.white,
        border: Border.all(
          color: stage.completed || stage.current
              ? color
              : JobMateTheme.divider,
          width: 2,
        ),
      ),
      child: stage.completed
          ? Icon(
              stage.rejected ? Icons.close : Icons.check,
              size: 17,
              color: Colors.white,
            )
          : stage.current
          ? Icon(Icons.circle, size: 9, color: color)
          : null,
    );
  }
}

class _HorizontalProgressItem extends StatelessWidget {
  const _HorizontalProgressItem({
    super.key,
    required this.label,
    required this.stage,
  });
  final String label;
  final _ProgressStage stage;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      _ProgressDot(stage),
      const SizedBox(height: 7),
      Text(label, textAlign: TextAlign.center),
    ],
  );
}

class _VerticalProgressItem extends StatelessWidget {
  const _VerticalProgressItem({
    super.key,
    required this.label,
    required this.stage,
    required this.connector,
    required this.connectorComplete,
  });
  final String label;
  final _ProgressStage stage;
  final bool connector;
  final bool connectorComplete;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              _ProgressDot(stage),
              if (connector)
                Expanded(
                  child: VerticalDivider(
                    width: 2,
                    thickness: 2,
                    color: connectorComplete
                        ? JobMateTheme.teal
                        : JobMateTheme.divider,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 4, bottom: connector ? 24 : 0),
            child: Text(label),
          ),
        ),
      ],
    ),
  );
}
