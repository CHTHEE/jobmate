import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_widgets.dart';
import '../demo_work/demo_widgets.dart';
import '../demo_work/local_attachment.dart';
import '../jobs/job_display.dart';
import 'phase4_store.dart';
import 'evaluation_pages.dart';

const paymentDisclaimer =
    'JobMate records payments made OUTSIDE the app. This demo never transfers money, processes cards, holds a wallet balance or confirms a bank transaction. All amounts, parties and proof files here are sample/local data.';
String paymentRoot(bool employer) =>
    employer ? AppRoutes.employerPayments : AppRoutes.payments;

class PaymentRecordPage extends StatefulWidget {
  const PaymentRecordPage({super.key, this.store});
  final Phase4Store? store;
  @override
  State<PaymentRecordPage> createState() => _PaymentRecordPageState();
}

class _PaymentRecordPageState extends State<PaymentRecordPage> {
  late final store = widget.store ?? Phase4Store.session;
  late final amount = TextEditingController(text: store.paymentDraft.amount),
      date = TextEditingController(text: store.paymentDraft.date),
      reference = TextEditingController(text: store.paymentDraft.reference),
      note = TextEditingController(text: store.paymentDraft.note);
  late String worker = store.paymentDraft.worker.isNotEmpty
      ? store.paymentDraft.worker
      : store.assignment(store.paymentDraft.assignmentId)?.worker ?? '';
  bool reading = false, submitting = false;
  String? error, created;
  @override
  void dispose() {
    amount.dispose();
    date.dispose();
    reference.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> proof() async {
    final generation = store.generation;
    setState(() {
      reading = true;
      error = null;
    });
    try {
      final files = await pickDemoFiles();
      if (!mounted || generation != store.generation) return;
      if (files.length > 1) {
        throw const FormatException('Select only one proof file.');
      }
      if (files.isNotEmpty) {
        setState(() => store.paymentDraft.proof = files.single);
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not read payment proof. Retry; your draft is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  Future<void> record() async {
    if (reading || submitting) return;
    if (!await demoConfirm(
      context,
      'Record external payment in demo?',
      'You are recording an employer-declared sample payment. This will NOT send money or establish actual receipt.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => submitting = true);
    try {
      final p = store.recordPayment();
      setState(() {
        created = p.id;
        error = null;
      });
    } on StateError catch (e) {
      setState(() => error = e.message.toString());
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final draft = store.paymentDraft,
          assignments = store.assignments
              .where(
                (a) => a.completed && (worker.isEmpty || a.worker == worker),
              )
              .toList();
      return DemoPage(
        title: created == null
            ? 'Record External Payment'
            : 'Payment Recorded (demo)',
        path: AppRoutes.employerPayments,
        role: 'employer',
        back: AppRoutes.employerPayments,
        children: [
          const Phase3Notice(paymentDisclaimer),
          if (created != null)
            WorkspaceCard(
              title: 'Demo payment record created',
              subtitle: 'No funds were moved and no bank receipt was verified.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Sample record: $created'),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () =>
                        context.go('${AppRoutes.employerPayments}/$created'),
                    child: const Text('View Payment Details'),
                  ),
                  OutlinedButton(
                    onPressed: () => context.go(AppRoutes.employerPayments),
                    child: const Text('View Payment History'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      created = null;
                      worker = '';
                      amount.clear();
                      date.clear();
                      reference.clear();
                      note.clear();
                    }),
                    child: const Text('Record Another Demo Payment'),
                  ),
                ],
              ),
            )
          else
            WorkspaceCard(
              title: 'Employer-declared payment',
              subtitle: 'Only completed sample assignments are selectable. Your draft survives in-app navigation.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 16,
                    children: [
                      ModuleSelect(
                        label: 'Worker (required)',
                        value: worker,
                        options: {
                          '': 'Select worker',
                          for (final a in store.assignments.where(
                            (a) => a.completed,
                          ))
                            a.worker: a.worker,
                        },
                        onChanged: (v) => setState(() {
                          worker = v;
                          draft.worker = v;
                          draft.assignmentId = '';
                        }),
                      ),
                      ModuleSelect(
                        label: 'Completed assignment',
                        value: draft.assignmentId,
                        options: {
                          '': 'Select assignment',
                          for (final a in assignments)
                            a.id: '${a.job} • ${a.id}',
                        },
                        onChanged: (v) =>
                            setState(() => draft.assignmentId = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amount,
                    enabled: !reading && !submitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) => draft.amount = v,
                    decoration: const InputDecoration(
                      labelText: 'Amount in RM (required)',
                      hintText: 'e.g. 180.00',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: date,
                    enabled: !reading && !submitting,
                    onChanged: (v) => draft.date = v,
                    decoration: InputDecoration(
                      labelText: 'Payment date (YYYY-MM-DD)',
                      suffixIcon: IconButton(
                        tooltip: 'Choose payment date',
                        onPressed: reading
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final selected = await showDatePicker(
                                  context: context,
                                  initialDate: now,
                                  firstDate: DateTime(2000),
                                  lastDate: now,
                                );
                                if (selected != null && mounted) {
                                  setState(() {
                                    date.text = jobDate(selected);
                                    draft.date = date.text;
                                  });
                                }
                              },
                        icon: const Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ModuleSelect(
                    label: 'Payment method',
                    value: draft.method,
                    options: {
                      for (final m in [
                        'Bank transfer',
                        'Cash',
                        'E-wallet',
                        'Other',
                      ])
                        m: m,
                    },
                    onChanged: (v) => setState(() => draft.method = v),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: reference,
                    maxLength: 100,
                    onChanged: (v) => draft.reference = v,
                    decoration: const InputDecoration(
                      labelText: 'Reference (optional)',
                    ),
                  ),
                  TextField(
                    controller: note,
                    maxLength: 1000,
                    minLines: 3,
                    maxLines: 5,
                    onChanged: (v) => draft.note = v,
                    decoration: const InputDecoration(
                      labelText: 'Payment note (optional)',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: reading ? null : proof,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      reading
                          ? 'Reading local proof…'
                          : 'Choose optional proof (local only)',
                    ),
                  ),
                  if (reading) const LinearProgressIndicator(),
                  if (draft.proof != null)
                    AttachmentTile(
                      draft.proof!,
                      onRemove: reading
                          ? null
                          : () => setState(() => draft.proof = null),
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
                    onPressed: reading || submitting ? null : record,
                    child: const Text('Record Payment (demo)'),
                  ),
                  TextButton(
                    onPressed: reading
                        ? null
                        : () async {
                            if (!await demoConfirm(
                              context,
                              'Discard payment draft?',
                              'This removes the unsaved local form and proof selection.',
                            )) {
                              return;
                            }
                            if (!mounted) return;
                            setState(() {
                              store.paymentDraft = PaymentDraft();
                              worker = '';
                              amount.clear();
                              date.clear();
                              reference.clear();
                              note.clear();
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

class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({super.key, this.employer = false, this.store});
  final bool employer;
  final Phase4Store? store;
  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  late final store = widget.store ?? Phase4Store.session;
  final search = TextEditingController();
  String status = '', tab = 'All';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final base = store.payments
          .where(
            (p) => sampleAssignmentVisible(
              store.assignment(p.assignmentId)!,
              widget.employer,
            ),
          )
          .toList();
      final rows = base.where((p) {
        final a = store.assignment(p.assignmentId)!;
        return (status.isEmpty || p.state.label == status) &&
            (tab == 'All' ||
                (tab == 'Pending'
                    ? [
                        PaymentState.pending,
                        PaymentState.overdue,
                      ].contains(p.state)
                    : [
                        PaymentState.confirmed,
                        PaymentState.disputed,
                      ].contains(p.state))) &&
            '${a.job} ${a.worker} ${a.company} ${p.reference}'
                .toLowerCase()
                .contains(search.text.trim().toLowerCase());
      }).toList()..sort((a, b) => b.date.compareTo(a.date));
      return DemoPage(
        title: widget.employer
            ? 'Employer Payment History'
            : 'My Payment Records',
        path: paymentRoot(widget.employer),
        role: widget.employer ? 'employer' : 'job_seeker',
        children: [
          const Phase3Notice(paymentDisclaimer),
          DemoStats({
            for (final s in PaymentState.values)
              s.label: base.where((p) => p.state == s).length,
          }),
          if (widget.employer)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: FilledButton.icon(
                onPressed: () => context.push(AppRoutes.recordPayment),
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Record External Payment (demo)'),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              for (final v in ['All', 'Pending', 'History'])
                ChoiceChip(
                  label: Text(v),
                  selected: tab == v,
                  onSelected: (_) => setState(() => tab = v),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search job, party or reference',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ModuleSelect(
                label: 'Payment status',
                value: status,
                options: {
                  '': 'All statuses',
                  for (final s in PaymentState.values) s.label: s.label,
                },
                onChanged: (v) => setState(() => status = v),
              ),
              TextButton(
                onPressed: () => setState(() {
                  search.clear();
                  status = '';
                  tab = 'All';
                }),
                child: const Text('Clear filters'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (rows.isEmpty)
            const ModuleState(
              title: 'No payment records found',
              message: 'Try another search/status. This page displays sample external-payment records, not a bank balance.',
            ),
          for (final p in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: WorkspaceCard(
                title: store.assignment(p.assignmentId)!.job,
                subtitle: widget.employer
                    ? store.assignment(p.assignmentId)!.worker
                    : store.assignment(p.assignmentId)!.company,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${sampleMoney(p.amount)} • ${jobDate(p.date)}'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(label: Text('${p.state.label} • demo')),
                    ),
                    const Text(
                      'Employer-declared external payment; not a transaction processed by JobMate.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => context.push(
                        '${paymentRoot(widget.employer)}/${p.id}',
                      ),
                      child: const Text('View Payment Details'),
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

class PaymentDetailPage extends StatelessWidget {
  const PaymentDetailPage({
    super.key,
    required this.paymentId,
    this.employer = false,
    this.store,
  });
  final String paymentId;
  final bool employer;
  final Phase4Store? store;
  @override
  Widget build(BuildContext context) {
    final data = store ?? Phase4Store.session;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final p = data.payment(paymentId),
            a = p == null ? null : data.assignment(p.assignmentId);
        return DemoPage(
          title: 'Payment Details',
          path: paymentRoot(employer),
          role: employer ? 'employer' : 'job_seeker',
          back: paymentRoot(employer),
          children: [
            const Phase3Notice(paymentDisclaimer),
            if (p == null || a == null || !sampleAssignmentVisible(a, employer))
              const ModuleState(
                title: 'Payment unavailable',
                message: 'No payment record exists for this demo view.',
              )
            else
              WorkspaceCard(
                title: sampleMoney(p.amount),
                subtitle: '${p.id} • ${p.state.label} (demo)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final fact in {
                      'Job': a.job,
                      'Worker': a.worker,
                      'Employer': a.company,
                      'Completed assignment': a.id,
                      'Payment date': jobDate(p.date),
                      'Method': p.method,
                      'Reference': p.reference.isEmpty
                          ? 'Not provided'
                          : p.reference,
                      'Note': p.note.isEmpty ? 'Not provided' : p.note,
                    }.entries)
                      WorkspaceInfo(fact.key, fact.value),
                    if (p.proof != null)
                      AttachmentTile(p.proof!)
                    else
                      const Text(
                        'No proof attached. Nothing has been uploaded.',
                      ),
                    if (p.disputeId != null)
                      Text(
                        'Linked demo case: ${p.disputeId} • ${data.dispute(p.disputeId!)?.state.label}. Case closure does not automatically confirm payment.',
                      ),
                    if (!employer) ...[
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed:
                            ![
                              PaymentState.pending,
                              PaymentState.overdue,
                            ].contains(p.state)
                            ? null
                            : () async {
                                if (!await demoConfirm(
                                  context,
                                  'Confirm sample receipt?',
                                  'This records only a local confirmation of the fictional external payment.',
                                )) {
                                  return;
                                }
                                if (!context.mounted) return;
                                try {
                                  data.confirmReceipt(p.id);
                                  demoMessage(
                                    context,
                                    'Receipt confirmed in demo only',
                                  );
                                } on StateError catch (e) {
                                  demoMessage(context, e.message.toString());
                                }
                              },
                        child: const Text('Confirm Receipt (demo)'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed:
                            ![
                              PaymentState.pending,
                              PaymentState.overdue,
                            ].contains(p.state)
                            ? null
                            : () => moduleModal<void>(
                                context,
                                PaymentIssueForm(paymentId: p.id, store: data),
                              ),
                        child: const Text('Report Payment Issue (demo)'),
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
}

class PaymentIssueForm extends StatefulWidget {
  const PaymentIssueForm({
    super.key,
    required this.paymentId,
    required this.store,
  });
  final String paymentId;
  final Phase4Store store;
  @override
  State<PaymentIssueForm> createState() => _PaymentIssueFormState();
}

class _PaymentIssueFormState extends State<PaymentIssueForm> {
  late final keyName = 'payment-issue:${widget.paymentId}';
  late final reason = TextEditingController(
    text: widget.store.formDrafts[keyName] ?? '',
  );
  String? error;
  bool success = false;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModalBody(
    title: success ? 'Demo payment issue recorded' : 'Report Payment Issue',
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(success ? 'Done' : 'Cancel (keep draft)'),
      ),
      if (!success)
        FilledButton(
          onPressed: () {
            try {
              widget.store.reportPayment(widget.paymentId, reason.text);
              widget.store.formDrafts.remove(keyName);
              setState(() => success = true);
            } on StateError catch (e) {
              setState(() => error = e.message.toString());
            }
          },
          child: const Text('Record Demo Dispute'),
        ),
    ],
    children: [
      const Text(
        'DEMO ONLY • No complaint is sent, no money is reversed and no review SLA is promised.',
      ),
      if (success)
        Text(
          'Sample case ${widget.store.payment(widget.paymentId)?.disputeId} is linked to the demo admin dispute list.',
        )
      else ...[
        const SizedBox(height: 16),
        TextField(
          controller: reason,
          maxLength: 1000,
          minLines: 3,
          maxLines: 6,
          onChanged: (v) => widget.store.formDrafts[keyName] = v,
          decoration: const InputDecoration(
            labelText: 'Issue reason / details (required)',
          ),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ],
  );
}
