import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_widgets.dart';
import '../demo_work/demo_widgets.dart';
import '../demo_work/local_attachment.dart';
import '../demo_work/phase3_store.dart';
import '../jobs/job_display.dart';
import 'report_print.dart';

const attendanceDisclaimer =
    'Fictional assignments and device-clock timestamps. Location is simulated, not GPS-verified. Evidence stays in memory. Employer decisions are demo labels, not legal verification.';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key, this.store});
  final Phase3Store? store;
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  late final store = widget.store ?? Phase3Store.session;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> clock(DemoAttendance r, bool input) async {
    if (!await demoConfirm(
      context,
      input ? 'Check in to demo shift?' : 'Check out of demo shift?',
      'Device time: ${demoTime(DateTime.now())}. Location source: simulated.',
    )) {
      return;
    }
    if (!mounted || !context.mounted) return;
    try {
      store.clock(r.id, checkingIn: input);
      demoMessage(
        context,
        input ? 'Demo check-in recorded' : 'Demo check-out recorded',
      );
    } on StateError catch (e) {
      demoMessage(context, e.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final r = store.record('today');
      return DemoPage(
        title: 'Attendance Today',
        path: AppRoutes.attendance,
        role: 'job_seeker',
        children: [
          const Phase3Notice(attendanceDisclaimer),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton(
                onPressed: () => context.push(AppRoutes.attendanceHistory),
                child: const Text('Attendance History'),
              ),
              OutlinedButton(
                onPressed: () => context.push(AppRoutes.workEvidence),
                child: const Text('Work Evidence'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (r == null)
            const ModuleState(
              title: 'No active assignment',
              message: 'There is no assignment in this demo session.',
            )
          else
            WorkspaceCard(
              title: r.job,
              subtitle: 'Active demo assignment • ${r.worker}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${jobDate(r.start)} • ${demoTime(r.start)}–${demoTime(r.end)}',
                  ),
                  const Text('Demo workplace: Sample retail floor, Shah Alam'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(r.state)),
                      Chip(
                        avatar: const Icon(
                          Icons.location_on_outlined,
                          size: 18,
                        ),
                        label: Text(
                          r.locationReady
                              ? 'Simulated location ready'
                              : 'Location simulation not started',
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'No location permission is requested. This does not establish presence at a real workplace.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: r.locationReady
                        ? null
                        : () => store.simulateLocation(r.id),
                    child: const Text('Simulate location check (demo)'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Device clock: ${demoTime(DateTime.now())}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Elapsed demo time: ${demoDuration(r.elapsed(DateTime.now()))}',
                  ),
                  WorkspaceInfo('Check-in', demoTime(r.checkIn)),
                  WorkspaceInfo('Check-out', demoTime(r.checkOut)),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: r.locationReady && r.checkIn == null
                            ? () => clock(r, true)
                            : null,
                        child: const Text('Check In (demo)'),
                      ),
                      FilledButton(
                        onPressed: r.checkIn != null && r.checkOut == null
                            ? () => clock(r, false)
                            : null,
                        child: const Text('Check Out (demo)'),
                      ),
                    ],
                  ),
                  if (r.checkOut != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => context.push(AppRoutes.workEvidence),
                      child: const Text('Add Work Evidence'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    },
  );
}

class EvidencePage extends StatefulWidget {
  const EvidencePage({super.key, this.store});
  final Phase3Store? store;
  @override
  State<EvidencePage> createState() => _EvidencePageState();
}

class _EvidencePageState extends State<EvidencePage> {
  late final store = widget.store ?? Phase3Store.session;
  late final description = TextEditingController(
    text: store.evidenceDraft('today').description,
  );
  bool reading = false;
  String? error;
  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Future<void> choose() async {
    final generation = store.generation;
    setState(() {
      reading = true;
      error = null;
    });
    try {
      final selected = await pickDemoFiles();
      if (!mounted || generation != store.generation) return;
      final draft = store.evidenceDraft('today');
      if (draft.files.length + selected.length > 5) {
        throw const FormatException('A maximum of five files is allowed.');
      }
      setState(() => draft.files.addAll(selected));
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not read files. Your draft is preserved; retry the picker.',
        );
      }
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final r = store.record('today'), draft = store.evidenceDraft('today');
      return DemoPage(
        title: 'Work Evidence',
        path: AppRoutes.attendance,
        role: 'job_seeker',
        back: AppRoutes.attendance,
        children: [
          const Phase3Notice(attendanceDisclaimer),
          if (r == null)
            const ModuleState(
              title: 'Assignment unavailable',
              message: 'Return to Attendance Today.',
            )
          else if (r.evidence.isNotEmpty)
            WorkspaceCard(
              title: 'Demo evidence recorded',
              subtitle: 'No file was uploaded.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(r.description),
                  for (final file in r.evidence) AttachmentTile(file),
                  OutlinedButton(
                    onPressed: () =>
                        context.push('${AppRoutes.attendance}/${r.id}'),
                    child: const Text('View attendance details'),
                  ),
                ],
              ),
            )
          else
            WorkspaceCard(
              title: r.job,
              subtitle: 'Your local draft is retained when navigating within this session.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (r.checkOut == null)
                    const Text(
                      'Check out of the demo shift before submitting. You can prepare evidence now.',
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: description,
                    enabled: !reading,
                    maxLength: 2000,
                    minLines: 4,
                    maxLines: 8,
                    onChanged: (v) => draft.description = v,
                    decoration: const InputDecoration(
                      labelText: 'Work description (required)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const Text(
                    'PNG, JPEG or PDF • up to 5 files • 5 MiB each • local preview only',
                  ),
                  OutlinedButton.icon(
                    onPressed: reading ? null : choose,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      reading
                          ? 'Reading local files…'
                          : 'Choose evidence files',
                    ),
                  ),
                  if (reading) const LinearProgressIndicator(),
                  for (final file in draft.files)
                    AttachmentTile(
                      file,
                      onRemove: reading
                          ? null
                          : () => setState(() => draft.files.remove(file)),
                    ),
                  if (error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: reading || r.checkOut == null
                        ? null
                        : () {
                            try {
                              store.submitEvidence(r.id);
                              demoMessage(
                                context,
                                'Evidence saved to this demo session only',
                              );
                            } on StateError catch (e) {
                              setState(() => error = e.message.toString());
                            }
                          },
                    child: const Text('Submit Evidence (demo)'),
                  ),
                  TextButton(
                    onPressed: reading
                        ? null
                        : () async {
                            if (!await demoConfirm(
                              context,
                              'Discard evidence draft?',
                              'The selected local files and description will be removed from this draft.',
                            )) {
                              return;
                            }
                            if (!mounted || !context.mounted) return;
                            setState(() {
                              draft.files.clear();
                              draft.description = '';
                              description.clear();
                              error = null;
                            });
                          },
                    child: const Text('Discard draft'),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class AttendanceListPage extends StatefulWidget {
  const AttendanceListPage({super.key, this.employer = false, this.store});
  final bool employer;
  final Phase3Store? store;
  @override
  State<AttendanceListPage> createState() => _AttendanceListPageState();
}

class _AttendanceListPageState extends State<AttendanceListPage> {
  late final store = widget.store ?? Phase3Store.session;
  final search = TextEditingController();
  String job = '', status = '';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final source = store.attendance
          .where((r) => widget.employer ? r.checkOut != null : r.mine)
          .toList();
      final rows = source
          .where(
            (r) =>
                (job.isEmpty || r.job == job) &&
                (status.isEmpty ||
                    (status == 'Completed'
                        ? r.checkOut != null
                        : status == 'Issues'
                        ? r.review == 'Flagged'
                        : r.review == status)) &&
                '${r.job} ${r.worker} ${r.description}'.toLowerCase().contains(
                  search.text.toLowerCase().trim(),
                ),
          )
          .toList();
      final root = widget.employer
          ? AppRoutes.attendanceReview
          : AppRoutes.attendance;
      return DemoPage(
        title: widget.employer ? 'Attendance Review' : 'Attendance History',
        path: root,
        role: widget.employer ? 'employer' : 'job_seeker',
        back: widget.employer ? null : AppRoutes.attendance,
        children: [
          const Phase3Notice(attendanceDisclaimer),
          DemoStats({
            'All': source.length,
            'Pending review': source
                .where((r) => r.checkOut != null && r.review == 'Pending')
                .length,
            'Verified': source.where((r) => r.review == 'Verified').length,
            'Flagged': source.where((r) => r.review == 'Flagged').length,
          }),
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search job, worker or note',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              ModuleSelect(
                label: 'Demo job',
                value: job,
                options: {'': 'All jobs', for (final r in source) r.job: r.job},
                onChanged: (v) => setState(() => job = v),
              ),
              ModuleSelect(
                label: 'Status',
                value: status,
                options: {
                  '': 'All',
                  if (!widget.employer) 'Completed': 'Completed',
                  if (!widget.employer) 'Issues': 'Issues',
                  'Pending': 'Pending',
                  'Verified': 'Verified',
                  'Flagged': 'Flagged',
                },
                onChanged: (v) => setState(() => status = v),
              ),
              TextButton(
                onPressed: () => setState(() {
                  search.clear();
                  job = '';
                  status = '';
                }),
                child: const Text('Clear filters'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (rows.isEmpty)
            const ModuleState(
              title: 'No attendance records',
              message: 'Try another filter or complete a demo shift.',
            ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: WorkspaceCard(
                title: r.job,
                subtitle: '${r.worker} • ${jobDate(r.start)}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text(r.state)),
                        Chip(label: Text('${r.review} • demo review')),
                      ],
                    ),
                    Text(
                      '${demoTime(r.checkIn)} → ${demoTime(r.checkOut)} • ${r.evidence.length} evidence files',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => context.push('$root/${r.id}'),
                      child: Text(
                        widget.employer
                            ? 'Review Worker Attendance'
                            : 'View Details',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class AttendanceDetailPage extends StatelessWidget {
  const AttendanceDetailPage({
    super.key,
    required this.recordId,
    this.employer = false,
    this.report = false,
    this.store,
  });
  final String recordId;
  final bool employer, report;
  final Phase3Store? store;
  @override
  Widget build(BuildContext context) {
    final data = store ?? Phase3Store.session;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final r = data.record(recordId),
            root = employer ? AppRoutes.attendanceReview : AppRoutes.attendance;
        final facts = r == null
            ? <String, String>{}
            : {
                'Assignment': r.id,
                'Job': r.job,
                'Worker': r.worker,
                'Schedule date': jobDate(r.start),
                'Schedule': '${demoTime(r.start)}–${demoTime(r.end)}',
                'Workplace': 'Demo retail/event workplace, Shah Alam',
                'Check-in (device demo)': demoTime(r.checkIn),
                'Check-out (device demo)': demoTime(r.checkOut),
                'Elapsed demo time': demoDuration(r.elapsed(DateTime.now())),
                'Location source': 'Simulated • not GPS-verified',
                'Attendance': r.state,
                'Late indicator': r.checkIn == null
                    ? 'Not recorded'
                    : r.checkIn!.isAfter(
                        r.start.add(const Duration(minutes: 15)),
                      )
                    ? 'Late in demo (15-minute grace)'
                    : 'Within demo grace period',
                'Evidence files': '${r.evidence.length}',
                'Worker note': r.description.isEmpty
                    ? 'Not provided'
                    : r.description,
                'Employer review': '${r.review} • demo only',
                if (r.flagReason.isNotEmpty) 'Flag reason': r.flagReason,
              };
        return DemoPage(
          title: report
              ? 'Attendance & Work Completion Report'
              : 'Attendance Details',
          path: root,
          role: employer ? 'employer' : 'job_seeker',
          back: report
              ? '$root/$recordId'
              : employer
              ? root
              : AppRoutes.attendanceHistory,
          children: [
            const Phase3Notice(attendanceDisclaimer),
            if (r == null || (!employer && !r.mine))
              const ModuleState(
                title: 'Record unavailable',
                message: 'No matching record exists in this demo session.',
              )
            else ...[
              if (report)
                const Text(
                  'JobMate • RPT-01 • DEMO REPORT',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              WorkspaceCard(
                title: report ? 'Work completion summary' : r.job,
                subtitle: report
                    ? 'Generated from current demo session • not proof of attendance or employment'
                    : r.worker,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final fact in facts.entries)
                      WorkspaceInfo(fact.key, fact.value),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              WorkspaceCard(
                title: 'Evidence',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (r.evidence.isEmpty) const Text('No evidence provided'),
                    for (final file in r.evidence) AttachmentTile(file),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (report)
                OutlinedButton.icon(
                  onPressed: !kIsWeb
                      ? null
                      : () {
                          try {
                            if (!openReportPrint(attendanceReportHtml(facts))) {
                              demoMessage(
                                context,
                                'The print window was blocked. Allow popups and retry.',
                              );
                            }
                          } catch (_) {
                            demoMessage(
                              context,
                              'Could not open the print view. Retry from a Web browser.',
                            );
                          }
                        },
                  icon: const Icon(Icons.print_outlined),
                  label: Text(
                    kIsWeb
                        ? 'Open printable demo report'
                        : 'Printing is available on Web',
                  ),
                )
              else ...[
                OutlinedButton(
                  onPressed: () => context.push('$root/${r.id}/report'),
                  child: const Text('View Demo Report'),
                ),
                if (employer) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed:
                            r.review != 'Pending' ||
                                r.checkOut == null ||
                                r.evidence.isEmpty
                            ? null
                            : () async {
                                if (!await demoConfirm(
                                  context,
                                  'Verify demo work?',
                                  'Evidence has been reviewed in this sample environment. This is not a real verification.',
                                )) {
                                  return;
                                }
                                if (!context.mounted) return;
                                try {
                                  data.review(r.id, verify: true);
                                  demoMessage(
                                    context,
                                    'Demo work marked Verified',
                                  );
                                } on StateError catch (e) {
                                  demoMessage(context, e.message.toString());
                                }
                              },
                        child: const Text('Verify Work (demo)'),
                      ),
                      OutlinedButton(
                        onPressed: r.review != 'Pending' || r.checkOut == null
                            ? null
                            : () => moduleModal<void>(
                                context,
                                FlagWorkForm(record: r, store: data),
                              ),
                        child: const Text('Flag Work (demo)'),
                      ),
                    ],
                  ),
                  const Text(
                    'Verification requires completed attendance and evidence. Reviewed demo records cannot be changed here.',
                  ),
                ],
              ],
            ],
          ],
        );
      },
    );
  }
}

String attendanceReportHtml(Map<String, String> facts) {
  const escape = HtmlEscape();
  final rows = facts.entries
      .map(
        (e) =>
            '<tr><th>${escape.convert(e.key)}</th><td>${escape.convert(e.value)}</td></tr>',
      )
      .join();
  return '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>JobMate Demo Attendance Report</title><style>body{font:16px system-ui;color:#0f172a;max-width:800px;margin:32px auto;padding:24px}h1{color:#0f766e}table{width:100%;border-collapse:collapse}th,td{text-align:left;vertical-align:top;padding:12px;border-bottom:1px solid #cbd5e1;overflow-wrap:anywhere}th{width:35%}button{padding:12px;background:#0f766e;color:white;border:0;border-radius:8px}@media print{button{display:none}body{margin:0}tr{break-inside:avoid}}@page{size:A4;margin:18mm}</style><button onclick="window.print()">Print / Save as PDF</button><h1>JobMate</h1><h2>Attendance &amp; Work Completion</h2><p>RPT-01 • DEMO REPORT • Local sample data only</p><table>$rows</table><p>${escape.convert(attendanceDisclaimer)}</p></html>';
}

class FlagWorkForm extends StatefulWidget {
  const FlagWorkForm({super.key, required this.record, required this.store});
  final DemoAttendance record;
  final Phase3Store store;
  @override
  State<FlagWorkForm> createState() => _FlagWorkFormState();
}

class _FlagWorkFormState extends State<FlagWorkForm> {
  late final reason = TextEditingController(
    text: widget.store.flagDrafts[widget.record.id] ?? '',
  );
  String? error;
  bool leaving = false;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModalBody(
    title: 'Flag demo work',
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel (keep draft)'),
      ),
      FilledButton(
        onPressed: leaving
            ? null
            : () async {
                if (reason.text.trim().isEmpty) {
                  setState(() => error = 'Enter a flag reason.');
                  return;
                }
                if (!await demoConfirm(
                  context,
                  'Confirm demo flag?',
                  'The worker record will be marked Flagged in this session.',
                )) {
                  return;
                }
                if (!mounted || !context.mounted) return;
                try {
                  widget.store.review(
                    widget.record.id,
                    verify: false,
                    reason: reason.text,
                  );
                  widget.store.flagDrafts.remove(widget.record.id);
                  setState(() => leaving = true);
                  Navigator.pop(context);
                } on StateError catch (e) {
                  setState(() => error = e.message.toString());
                }
              },
        child: const Text('Flag Work (demo)'),
      ),
    ],
    children: [
      const Text(
        'DEMO ONLY • No worker or server is notified. The reason is visible to both sample roles.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: reason,
        maxLength: 1000,
        minLines: 3,
        maxLines: 6,
        onChanged: (v) => widget.store.flagDrafts[widget.record.id] = v,
        decoration: const InputDecoration(
          labelText: 'Flag reason (required)',
          helperText: 'Draft retained in this session when closing.',
        ),
      ),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
